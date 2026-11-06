-- Eskemia · Catálogo de tarjetas del Inicio y validación en la base.
--
-- Qué hace: crea nucleo.tarjetas_inicio (catálogo global: qué tarjetas existen, de qué
-- módulo son y qué permiso exigen), la función nucleo.tarjeta_elegible, y ajusta
-- api.guardar_inicio (rechaza tarjetas no elegibles) y api.mi_inicio (oculta las que la
-- persona perdió). Suma api.tarjetas_disponibles para el "Agregar tarjeta" del front.
-- Dónde encaja: CLAUDE.md, sección "Inicio": una tarjeta es elegible si el módulo está
-- habilitado en la organización y la persona tiene el permiso; lo valida la base, no la
-- pantalla. El front declara título, tamaño y componente en modulos/registro.ts; acá
-- vive solo lo necesario para validar. El catálogo se carga en db/semillas.

create table nucleo.tarjetas_inicio (
  codigo         text primary key check (codigo ~ '^[a-z_]+\.[a-z_]+$'),
  -- Prefijo del código. 'nucleo' (Usuarios, Perfil de empresa) no es un módulo
  -- registrado: modulo_habilitado() lo da siempre por habilitado.
  modulo         text not null check (codigo like modulo || '.%'),
  -- Nulo: alcanza con ser miembro activo y tener el módulo habilitado.
  permiso_codigo text references nucleo.permisos (codigo),
  titulo         text not null check (btrim(titulo) <> '')
);

alter table nucleo.tarjetas_inicio enable row level security;
alter table nucleo.tarjetas_inicio force row level security;
revoke all on nucleo.tarjetas_inicio from public, anon, authenticated;
grant select on nucleo.tarjetas_inicio to authenticated;
create policy tarjetas_inicio_select on nucleo.tarjetas_inicio for select to authenticated
  using (true);

-- Una elección guardada siempre apunta a una tarjeta del catálogo.
alter table nucleo.inicio_tarjetas
  add constraint inicio_tarjetas_tarjeta_fk foreign key (tarjeta_codigo)
  references nucleo.tarjetas_inicio (codigo) on delete cascade;

/** true si la cuenta actual puede tener la tarjeta en su Inicio de esa organización:
 *  la tarjeta existe, su módulo está habilitado (con los que requiere) y, si exige un
 *  permiso, la cuenta lo tiene en alguna sede. */
create function nucleo.tarjeta_elegible(p_organizacion_id uuid, p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from nucleo.tarjetas_inicio t
    where t.codigo = p_codigo
      and nucleo.es_miembro(p_organizacion_id)
      and nucleo.modulo_habilitado(p_organizacion_id, t.modulo)
      and (t.permiso_codigo is null or nucleo.tiene_permiso(p_organizacion_id, t.permiso_codigo))
  );
$$;

/** api.guardar_inicio
 *  Qué hace: reemplaza la elección de tarjetas del Inicio de la cuenta actual en la
 *    organización. El orden es el del arreglo.
 *  Precondiciones: membresía activa; p_tarjetas es un arreglo de
 *    {codigo: 'modulo.tarjeta', visible: bool} sin códigos repetidos (máx. 50); cada
 *    tarjeta es elegible (nucleo.tarjeta_elegible).
 *  Permisos: ninguno propio (es una preferencia personal); cada tarjeta exige el suyo.
 *  Eventos: inicio/guardado. */
create or replace function api.guardar_inicio(p_organizacion_id uuid, p_tarjetas jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.membresia_activa(p_organizacion_id);
  v_no_elegibles text;
begin
  if jsonb_typeof(p_tarjetas) <> 'array' or jsonb_array_length(p_tarjetas) > 50 then
    raise exception 'PRECONDICION: las tarjetas tienen que ser una lista de hasta 50' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_tarjetas) t
    where coalesce(t ->> 'codigo', '') !~ '^[a-z_]+\.[a-z_]+$'
  ) then
    raise exception 'PRECONDICION: hay una tarjeta con un código no válido' using errcode = 'P0001';
  end if;
  if (select count(*) <> count(distinct t ->> 'codigo') from jsonb_array_elements(p_tarjetas) t) then
    raise exception 'PRECONDICION: hay tarjetas repetidas' using errcode = 'P0001';
  end if;

  select string_agg(t ->> 'codigo', ', ') into v_no_elegibles
  from jsonb_array_elements(p_tarjetas) t
  where not nucleo.tarjeta_elegible(p_organizacion_id, t ->> 'codigo');
  if v_no_elegibles is not null then
    raise exception 'PRECONDICION: estas tarjetas no están disponibles para vos: %', v_no_elegibles
      using errcode = 'P0001';
  end if;

  delete from nucleo.inicio_tarjetas it
  where it.organizacion_id = p_organizacion_id and it.cuenta_id = v_membresia.cuenta_id;

  insert into nucleo.inicio_tarjetas (organizacion_id, cuenta_id, tarjeta_codigo, orden, visible)
  select p_organizacion_id, v_membresia.cuenta_id, t.valor ->> 'codigo', (t.orden - 1)::int,
         coalesce((t.valor ->> 'visible')::boolean, true)
  from jsonb_array_elements(p_tarjetas) with ordinality as t (valor, orden);

  perform nucleo.registrar_evento(
    p_organizacion_id, null, 'inicio', v_membresia.id, 'guardado',
    jsonb_build_object('tarjetas', jsonb_array_length(p_tarjetas))
  );
end;
$$;

-- El Inicio de la cuenta actual, sin las tarjetas que dejó de poder ver (permiso
-- retirado o módulo deshabilitado): desaparecen sin romper nada y vuelven si se restituye.
create or replace view api.mi_inicio with (security_invoker = true) as
  select it.organizacion_id, it.tarjeta_codigo, it.orden, it.visible
  from nucleo.inicio_tarjetas it
  where it.cuenta_id = (select auth.uid())
    and nucleo.tarjeta_elegible(it.organizacion_id, it.tarjeta_codigo);

-- Tarjetas que la cuenta actual puede agregar, por organización.
create view api.tarjetas_disponibles with (security_invoker = true) as
  select o.id as organizacion_id, t.codigo, t.modulo, t.titulo
  from nucleo.organizaciones o
  cross join nucleo.tarjetas_inicio t
  where nucleo.tarjeta_elegible(o.id, t.codigo);

grant select on api.tarjetas_disponibles to authenticated;
