-- Eskemia · Permisos parametrizables (plan de Compras, etapa 1).
-- El código consulta permisos, nunca nombres de rol. Los roles los configura cada empresa.
--
-- perfiles.rol queda sin uso y se borra en otra migración, cuando todas las tablets
-- tengan el front nuevo: las versiones instaladas todavía la leen.

create type public.tipo_rol as enum ('INTERNO', 'EXTERNO');

-- Global: lo define el sistema, no la empresa.
create table public.permisos (
  codigo      text primary key,
  modulo      text not null,
  descripcion text not null
);

create table public.roles (
  id                          uuid primary key default gen_random_uuid(),
  tenant_id                   uuid not null references public.tenants (id),
  nombre                      text not null check (btrim(nombre) <> ''),
  tipo                        public.tipo_rol not null default 'INTERNO',
  nivel_aprobacion            int not null default 0 check (nivel_aprobacion >= 0),
  limite_monto_sin_aprobacion numeric(14, 2) check (limite_monto_sin_aprobacion >= 0),
  activo                      boolean not null default true,
  creado_en                   timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, nombre)
);

create table public.rol_permisos (
  tenant_id      uuid not null,
  rol_id         uuid not null,
  permiso_codigo text not null references public.permisos (codigo),
  primary key (rol_id, permiso_codigo),
  foreign key (tenant_id, rol_id) references public.roles (tenant_id, id)
);

create table public.sectores (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  nombre    text not null check (btrim(nombre) <> ''),
  activo    boolean not null default true,
  creado_en timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, nombre)
);

alter table public.perfiles add unique (tenant_id, user_id);

-- sede_id nulo: el rol vale en todas las sedes del tenant.
-- proveedor_id: para el portal de proveedor, sin uso en el MVP.
create table public.usuario_roles (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  user_id      uuid not null,
  rol_id       uuid not null,
  sede_id      uuid,
  sector_id    uuid,
  proveedor_id uuid,
  creado_en    timestamptz not null default now(),
  unique nulls not distinct (user_id, rol_id, sede_id, sector_id),
  foreign key (tenant_id, user_id) references public.perfiles (tenant_id, user_id),
  foreign key (tenant_id, rol_id) references public.roles (tenant_id, id),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  foreign key (tenant_id, sector_id) references public.sectores (tenant_id, id),
  foreign key (tenant_id, proveedor_id) references public.proveedores (tenant_id, id)
);
create index usuario_roles_rol_idx on public.usuario_roles (rol_id);

create table public.configuracion_empresa (
  tenant_id               uuid primary key references public.tenants (id),
  permitir_autoaprobacion boolean not null default true,
  actualizado_en          timestamptz not null default now()
);

insert into public.permisos (codigo, modulo, descripcion) values
  ('compras.catalogo.ver', 'compras', 'Ver marketplace'),
  ('compras.catalogo.gestionar', 'compras', 'Alta y edición de productos, códigos, proveedores, precios e importación'),
  ('compras.pedido.crear', 'compras', 'Armar y confirmar pedidos'),
  ('compras.oc.ver_todas', 'compras', 'Ver órdenes de compra de otros usuarios'),
  ('compras.oc.aprobar', 'compras', 'Aprobar o rechazar órdenes de compra, hasta su nivel de aprobación'),
  ('compras.oc.anular', 'compras', 'Anular órdenes de compra sin recepciones'),
  ('compras.oc.cerrar_saldo', 'compras', 'Cerrar saldo pendiente'),
  ('compras.aprobacion.configurar', 'compras', 'Editar reglas de aprobación'),
  ('recepcion.pendientes.ver', 'recepcion', 'Ver lista de órdenes de compra pendientes'),
  ('recepcion.pendientes.ver_en_aprobacion', 'recepcion', 'Ver también órdenes aún no aprobadas'),
  ('recepcion.precios.ver', 'recepcion', 'Ver precios en órdenes de compra'),
  ('recepcion.recepcion.operar', 'recepcion', 'Operar el kiosco'),
  ('recepcion.recepcion.validar', 'recepcion', 'Validar o rechazar recepciones'),
  ('recepcion.recepcion.marcar_ingresada', 'recepcion', 'Marcar una recepción validada como ingresada a sistema'),
  ('recepcion.eventos.ver', 'recepcion', 'Ver la línea de tiempo de eventos y quiénes actuaron'),
  ('admin.usuarios.gestionar', 'admin', 'Usuarios, roles y permisos'),
  ('admin.eventos.verificar', 'admin', 'Verificar la cadena de hash de eventos');

-- Roles iniciales de una empresa: después los edita ella.
create function app_private.crear_roles_semilla(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comprador text[] := array['compras.catalogo.ver', 'compras.pedido.crear'];
  v_encargado text[] := v_comprador || array[
    'compras.oc.ver_todas', 'compras.oc.aprobar', 'compras.oc.anular', 'compras.catalogo.gestionar'
  ];
  v_operario text[] := array['recepcion.pendientes.ver', 'recepcion.recepcion.operar'];
  v_rol record;
  v_id uuid;
begin
  for v_rol in
    select * from (values
      ('Comprador', 0, v_comprador),
      ('Encargado de compras', 1, v_encargado),
      ('Gerente', 2, v_encargado || array['compras.oc.cerrar_saldo', 'compras.aprobacion.configurar']),
      ('Operario de recepción', 0, v_operario),
      ('Supervisor de recepción', 0, v_operario || array[
        'recepcion.recepcion.validar', 'recepcion.recepcion.marcar_ingresada',
        'recepcion.eventos.ver', 'recepcion.pendientes.ver_en_aprobacion'
      ]),
      ('Administración', 0, array[
        'compras.oc.ver_todas', 'recepcion.precios.ver', 'recepcion.recepcion.validar',
        'recepcion.recepcion.marcar_ingresada', 'recepcion.eventos.ver'
      ]),
      ('Admin', 3, (select array_agg(p.codigo) from public.permisos p))
    ) as t (nombre, nivel, permisos)
  loop
    insert into public.roles (tenant_id, nombre, nivel_aprobacion)
    values (p_tenant_id, v_rol.nombre, v_rol.nivel)
    returning id into v_id;

    insert into public.rol_permisos (tenant_id, rol_id, permiso_codigo)
    select p_tenant_id, v_id, unnest(v_rol.permisos);
  end loop;

  insert into public.configuracion_empresa (tenant_id) values (p_tenant_id);
end;
$$;

select app_private.crear_roles_semilla(t.id) from public.tenants t;

-- Migra los usuarios existentes: conservan lo que podían hacer.
insert into public.usuario_roles (tenant_id, user_id, rol_id, sede_id)
select p.tenant_id, p.user_id, r.id, p.sede_id
from public.perfiles p
join public.roles r on r.tenant_id = p.tenant_id and r.nombre = case p.rol
  when 'operario' then 'Operario de recepción'
  when 'supervisor' then 'Supervisor de recepción'
  when 'admin' then 'Admin'
end;

-- ---------------------------------------------------------------------------
-- Consultas de permisos
-- ---------------------------------------------------------------------------

-- p_sede_id nulo: alcanza con tener el permiso en alguna sede.
create function app_private.tiene_permiso(p_codigo text, p_sede_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuario_roles ur
    join public.roles r on r.id = ur.rol_id and r.activo
    join public.rol_permisos rp on rp.rol_id = r.id
    join public.perfiles p on p.user_id = ur.user_id and p.activo
    where ur.user_id = (select auth.uid())
      and rp.permiso_codigo = p_codigo
      and (p_sede_id is null or ur.sede_id is null or ur.sede_id = p_sede_id)
  );
$$;

-- Ve su tenant en las sedes donde tiene un rol, y los catálogos compartidos (sede nula).
create or replace function app_private.puede_ver_sede(p_tenant_id uuid, p_sede_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_tenant_id = app_private.tenant_actual()
    and (
      p_sede_id is null
      or exists (
        select 1
        from public.usuario_roles ur
        join public.roles r on r.id = ur.rol_id and r.activo
        where ur.user_id = (select auth.uid())
          and (ur.sede_id is null or ur.sede_id = p_sede_id)
      )
    ),
    false
  );
$$;

create function app_private.perfil_activo()
returns public.perfiles
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles;
begin
  select * into v_perfil from public.perfiles p
  where p.user_id = auth.uid() and p.activo;

  if not found then
    raise exception 'SIN_PERMISO: el usuario no tiene un perfil activo' using errcode = '42501';
  end if;
  return v_perfil;
end;
$$;

create function app_private.exigir_permiso(p_codigo text, p_sede_id uuid default null)
returns public.perfiles
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.perfil_activo();
begin
  if not app_private.tiene_permiso(p_codigo, p_sede_id) then
    raise exception 'SIN_PERMISO: falta el permiso %', p_codigo using errcode = '42501';
  end if;
  return v_perfil;
end;
$$;

-- Administrar usuarios afecta a toda la empresa: un rol limitado a una sede no alcanza.
create function app_private.exigir_gestion_usuarios()
returns public.perfiles
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.perfil_activo();
begin
  if not exists (
    select 1
    from public.usuario_roles ur
    join public.roles r on r.id = ur.rol_id and r.activo
    join public.rol_permisos rp on rp.rol_id = r.id
    where ur.user_id = v_perfil.user_id
      and ur.sede_id is null
      and rp.permiso_codigo = 'admin.usuarios.gestionar'
  ) then
    raise exception 'SIN_PERMISO: falta el permiso admin.usuarios.gestionar en todas las sedes'
      using errcode = '42501';
  end if;
  return v_perfil;
end;
$$;

-- Evita que una empresa se quede sin nadie que pueda administrar usuarios.
create function app_private.exigir_gestor_restante(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.usuario_roles ur
    join public.roles r on r.id = ur.rol_id and r.activo
    join public.rol_permisos rp on rp.rol_id = r.id
    join public.perfiles p on p.user_id = ur.user_id and p.activo
    where ur.tenant_id = p_tenant_id
      and ur.sede_id is null
      and rp.permiso_codigo = 'admin.usuarios.gestionar'
  ) then
    raise exception 'PRECONDICION: la empresa se quedaría sin nadie que administre usuarios'
      using errcode = 'P0001';
  end if;
end;
$$;

-- El front lo guarda para decidir qué mostrar sin conexión. La autorización real está acá.
create function public.mis_permisos()
returns table (permiso text, sede_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permiso_codigo, ur.sede_id
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id
  join public.perfiles p on p.user_id = ur.user_id and p.activo
  where ur.user_id = (select auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Administración de roles
-- ---------------------------------------------------------------------------

create function public.crear_rol(p_nombre text, p_nivel_aprobacion int default 0)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_gestion_usuarios();
  v_nombre text := btrim(p_nombre);
  v_id uuid;
begin
  if coalesce(v_nombre, '') = '' then
    raise exception 'PRECONDICION: falta el nombre del rol' using errcode = 'P0001';
  end if;
  if coalesce(p_nivel_aprobacion, -1) < 0 then
    raise exception 'PRECONDICION: el nivel de aprobación no es válido' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.roles r
    where r.tenant_id = v_perfil.tenant_id and lower(r.nombre) = lower(v_nombre)
  ) then
    raise exception 'PRECONDICION: ya existe un rol con ese nombre' using errcode = 'P0001';
  end if;

  insert into public.roles (tenant_id, nombre, nivel_aprobacion)
  values (v_perfil.tenant_id, v_nombre, p_nivel_aprobacion)
  returning id into v_id;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'rol', v_id, 'alta',
    jsonb_build_object('nombre', v_nombre, 'nivel_aprobacion', p_nivel_aprobacion)
  );
  return v_id;
end;
$$;

create function public.fijar_permiso_rol(p_rol_id uuid, p_permiso text, p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_gestion_usuarios();
begin
  if not exists (
    select 1 from public.roles r
    where r.id = p_rol_id and r.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: rol inexistente' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.permisos p where p.codigo = p_permiso) then
    raise exception 'NO_ENCONTRADO: permiso inexistente' using errcode = 'P0002';
  end if;

  if p_activo then
    insert into public.rol_permisos (tenant_id, rol_id, permiso_codigo)
    values (v_perfil.tenant_id, p_rol_id, p_permiso)
    on conflict (rol_id, permiso_codigo) do nothing;
  else
    delete from public.rol_permisos rp
    where rp.rol_id = p_rol_id and rp.permiso_codigo = p_permiso;
    perform app_private.exigir_gestor_restante(v_perfil.tenant_id);
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'rol', p_rol_id, case when p_activo then 'permiso_agregado' else 'permiso_quitado' end,
    jsonb_build_object('permiso', p_permiso)
  );
end;
$$;

create function public.asignar_rol(
  p_user_id uuid,
  p_rol_id uuid,
  p_sede_id uuid default null,
  p_sector_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_gestion_usuarios();
  v_id uuid;
begin
  if not exists (
    select 1 from public.perfiles p
    where p.user_id = p_user_id and p.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: usuario inexistente' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.roles r
    where r.id = p_rol_id and r.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: rol inexistente' using errcode = 'P0002';
  end if;
  if p_sede_id is not null and not exists (
    select 1 from public.sedes s
    where s.id = p_sede_id and s.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  if p_sector_id is not null and not exists (
    select 1 from public.sectores s
    where s.id = p_sector_id and s.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: sector inexistente' using errcode = 'P0002';
  end if;

  select ur.id into v_id from public.usuario_roles ur
  where ur.user_id = p_user_id
    and ur.rol_id = p_rol_id
    and ur.sede_id is not distinct from p_sede_id
    and ur.sector_id is not distinct from p_sector_id;
  if found then
    return v_id;
  end if;

  insert into public.usuario_roles (tenant_id, user_id, rol_id, sede_id, sector_id)
  values (v_perfil.tenant_id, p_user_id, p_rol_id, p_sede_id, p_sector_id)
  returning id into v_id;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, p_sede_id, 'usuario_rol', v_id, 'asignado',
    jsonb_build_object('user_id', p_user_id, 'rol_id', p_rol_id, 'sector_id', p_sector_id)
  );
  return v_id;
end;
$$;

create function public.quitar_rol(p_usuario_rol_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_gestion_usuarios();
  v_fila public.usuario_roles;
begin
  delete from public.usuario_roles ur
  where ur.id = p_usuario_rol_id and ur.tenant_id = v_perfil.tenant_id
  returning * into v_fila;

  if not found then
    raise exception 'NO_ENCONTRADO: asignación inexistente' using errcode = 'P0002';
  end if;
  perform app_private.exigir_gestor_restante(v_perfil.tenant_id);

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_fila.sede_id, 'usuario_rol', v_fila.id, 'quitado',
    jsonb_build_object('user_id', v_fila.user_id, 'rol_id', v_fila.rol_id, 'sector_id', v_fila.sector_id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS y privilegios
-- ---------------------------------------------------------------------------

-- Los privilegios por defecto de public dan todo a anon: hay que quitarlos en cada tabla nueva.
revoke all on public.permisos, public.roles, public.rol_permisos, public.sectores,
  public.usuario_roles, public.configuracion_empresa
  from public, anon, authenticated, service_role;
grant select on public.permisos, public.roles, public.rol_permisos, public.sectores,
  public.usuario_roles, public.configuracion_empresa
  to authenticated, service_role;

alter table public.permisos              enable row level security;
alter table public.roles                 enable row level security;
alter table public.rol_permisos          enable row level security;
alter table public.sectores              enable row level security;
alter table public.usuario_roles         enable row level security;
alter table public.configuracion_empresa enable row level security;

create policy permisos_select on public.permisos
  for select to authenticated
  using (true);

create policy roles_select on public.roles
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and app_private.tiene_permiso('admin.usuarios.gestionar')
  );

create policy rol_permisos_select on public.rol_permisos
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and app_private.tiene_permiso('admin.usuarios.gestionar')
  );

create policy sectores_select on public.sectores
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

create policy usuario_roles_select on public.usuario_roles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      tenant_id = app_private.tenant_actual()
      and app_private.tiene_permiso('admin.usuarios.gestionar')
    )
  );

create policy configuracion_empresa_select on public.configuracion_empresa
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

drop policy perfiles_select on public.perfiles;
create policy perfiles_select on public.perfiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      (
        app_private.tiene_permiso('recepcion.eventos.ver')
        or app_private.tiene_permiso('admin.usuarios.gestionar')
      )
      and app_private.puede_ver_sede(tenant_id, sede_id)
    )
  );

drop policy eventos_select on public.eventos;
create policy eventos_select on public.eventos
  for select to authenticated
  using (
    app_private.tiene_permiso('recepcion.eventos.ver', sede_id)
    and app_private.puede_ver_sede(tenant_id, sede_id)
  );

drop function app_private.rol_actual();
drop function app_private.sede_actual();

revoke all on function app_private.crear_roles_semilla(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.perfil_activo() from public, anon, authenticated, service_role;
revoke all on function app_private.exigir_permiso(text, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.exigir_gestion_usuarios() from public, anon, authenticated, service_role;
revoke all on function app_private.exigir_gestor_restante(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.tiene_permiso(text, uuid) from public, anon;
grant execute on function app_private.tiene_permiso(text, uuid) to authenticated, service_role;

revoke all on function public.mis_permisos() from public, anon, authenticated, service_role;
revoke all on function public.crear_rol(text, int) from public, anon, authenticated, service_role;
revoke all on function public.fijar_permiso_rol(uuid, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.asignar_rol(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.quitar_rol(uuid) from public, anon, authenticated, service_role;
grant execute on function public.mis_permisos() to authenticated;
grant execute on function public.crear_rol(text, int) to authenticated;
grant execute on function public.fijar_permiso_rol(uuid, text, boolean) to authenticated;
grant execute on function public.asignar_rol(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.quitar_rol(uuid) to authenticated;
