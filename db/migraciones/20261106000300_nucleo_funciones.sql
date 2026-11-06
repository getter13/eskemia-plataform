-- Eskemia · Línea base v1 · 03: funciones base del núcleo.
--
-- Qué hace: pertenencia (es_miembro), permisos por código (tiene_permiso / exigir_permiso),
-- módulos habilitados, resolución de sede, eventos encadenados, alta de cuenta al
-- registrarse, slug y roles semilla de una organización nueva.
-- Dónde encaja: reemplaza a app_private.perfil_activo/tenant_actual/tiene_permiso del
-- legado, que suponían un único perfil por usuario. Acá todo recibe la organización.
-- Todas: SECURITY DEFINER (dueño postgres, BYPASSRLS) y search_path vacío.
-- Errores: el prefijo del mensaje es el contrato con el front
--   SIN_PERMISO (42501) · NO_ENCONTRADO (P0002) · PRECONDICION (P0001) ·
--   MODULO_DESHABILITADO (42501).

-- ---------------------------------------------------------------------------
-- Pertenencia y permisos
-- ---------------------------------------------------------------------------

/** true si la cuenta actual tiene membresía ACTIVA en la organización. Base de toda
 *  política RLS: se usa como (select nucleo.es_miembro(organizacion_id)). */
create function nucleo.es_miembro(p_organizacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from nucleo.membresias m
    where m.cuenta_id = (select auth.uid())
      and m.organizacion_id = p_organizacion_id
      and m.estado = 'ACTIVA'
  );
$$;

/** true si el módulo está habilitado en la organización junto con los módulos que
 *  requiere (Recepción requiere Compras). Un código que no es un módulo registrado (por
 *  ejemplo 'nucleo') se considera siempre habilitado. */
create function nucleo.modulo_habilitado(p_organizacion_id uuid, p_modulo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select bool_and(exists (
      select 1 from nucleo.modulos_habilitados mh
      where mh.organizacion_id = p_organizacion_id and mh.modulo_codigo = x.codigo
    ))
    from nucleo.modulos mo
    cross join lateral unnest(array[mo.codigo] || mo.requiere) as x (codigo)
    where mo.codigo = p_modulo
  ), true);
$$;

/** true si la cuenta actual tiene el permiso en la organización, para la sede dada
 *  (sede nula = cualquier sede). Exige membresía activa, rol activo y módulo habilitado.
 *  Un rol asignado sin sede vale para todas las sedes. */
create function nucleo.tiene_permiso(p_organizacion_id uuid, p_codigo text, p_sede_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from nucleo.membresias m
    join nucleo.membresia_roles mr on mr.membresia_id = m.id
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = p_codigo
    join nucleo.permisos p on p.codigo = rp.permiso_codigo
    where m.cuenta_id = (select auth.uid())
      and m.organizacion_id = p_organizacion_id
      and m.estado = 'ACTIVA'
      and (p_sede_id is null or mr.sede_id is null or mr.sede_id = p_sede_id)
      and nucleo.modulo_habilitado(p_organizacion_id, p.modulo)
  );
$$;

/** true si la cuenta actual es miembro y alcanza la sede: sede nula (dato de toda la
 *  organización) o algún rol activo en esa sede o en todas. Port de puede_ver_sede. */
create function nucleo.puede_ver_sede(p_organizacion_id uuid, p_sede_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select nucleo.es_miembro(p_organizacion_id)
    and (
      p_sede_id is null
      or exists (
        select 1
        from nucleo.membresias m
        join nucleo.membresia_roles mr on mr.membresia_id = m.id
        join nucleo.roles r on r.id = mr.rol_id and r.activo
        where m.cuenta_id = (select auth.uid())
          and m.organizacion_id = p_organizacion_id
          and m.estado = 'ACTIVA'
          and (mr.sede_id is null or mr.sede_id = p_sede_id)
      )
    );
$$;

/** Devuelve la membresía activa de la cuenta actual en la organización.
 *  Lanza SIN_PERMISO si no la tiene. */
create function nucleo.membresia_activa(p_organizacion_id uuid)
returns nucleo.membresias
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias;
begin
  select * into v_membresia from nucleo.membresias m
  where m.cuenta_id = (select auth.uid())
    and m.organizacion_id = p_organizacion_id
    and m.estado = 'ACTIVA';
  if not found then
    raise exception 'SIN_PERMISO: no sos miembro activo de esta organización' using errcode = '42501';
  end if;
  return v_membresia;
end;
$$;

/** Exige el permiso (y su módulo habilitado) y devuelve la membresía activa.
 *  Lanza SIN_PERMISO o MODULO_DESHABILITADO. */
create function nucleo.exigir_permiso(p_organizacion_id uuid, p_codigo text, p_sede_id uuid default null)
returns nucleo.membresias
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.membresia_activa(p_organizacion_id);
  v_modulo text;
begin
  if not nucleo.tiene_permiso(p_organizacion_id, p_codigo, p_sede_id) then
    select p.modulo into v_modulo from nucleo.permisos p where p.codigo = p_codigo;
    if v_modulo is not null and not nucleo.modulo_habilitado(p_organizacion_id, v_modulo) then
      raise exception 'MODULO_DESHABILITADO: el módulo % no está habilitado en esta organización', v_modulo
        using errcode = '42501';
    end if;
    raise exception 'SIN_PERMISO: falta el permiso %', p_codigo using errcode = '42501';
  end if;
  return v_membresia;
end;
$$;

/** Para RPC que reciben el id de una entidad: valida que la organización dueña exista y
 *  que la cuenta sea miembro. Si no, NO_ENCONTRADO: no revela datos de otra organización. */
create function nucleo.exigir_miembro(p_organizacion_id uuid, p_que text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_organizacion_id is null or not nucleo.es_miembro(p_organizacion_id) then
    raise exception 'NO_ENCONTRADO: % inexistente', p_que using errcode = 'P0002';
  end if;
  return p_organizacion_id;
end;
$$;

/** Sede de una operación. Sin sede explícita se infiere: la única sede donde la
 *  membresía tiene el permiso o, si lo tiene en todas, la única sede activa.
 *  Valida que la sede sea de la organización y que el permiso la alcance. */
create function nucleo.resolver_sede(p_membresia nucleo.membresias, p_sede_id uuid, p_permiso text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sede uuid := p_sede_id;
  v_global boolean;
  v_sedes uuid[];
begin
  if v_sede is null then
    select bool_or(mr.sede_id is null), array_agg(distinct mr.sede_id) filter (where mr.sede_id is not null)
    into v_global, v_sedes
    from nucleo.membresia_roles mr
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = p_permiso
    where mr.membresia_id = p_membresia.id;

    if v_global then
      select array_agg(s.id) into v_sedes from nucleo.sedes s
      where s.organizacion_id = p_membresia.organizacion_id and s.activa;
    end if;
    if coalesce(array_length(v_sedes, 1), 0) = 1 then
      v_sede := v_sedes[1];
    end if;
  end if;

  if v_sede is null then
    raise exception 'PRECONDICION: hay que indicar la sede' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from nucleo.sedes s
    where s.id = v_sede and s.organizacion_id = p_membresia.organizacion_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  if not nucleo.tiene_permiso(p_membresia.organizacion_id, p_permiso, v_sede) then
    raise exception 'SIN_PERMISO: la sede no corresponde al usuario' using errcode = '42501';
  end if;
  return v_sede;
end;
$$;

/** Mayor nivel de aprobación de una cuenta en una sede, entre sus roles activos con
 *  compras.oc.aprobar. 0 si no aprueba. */
create function nucleo.nivel_aprobacion(p_organizacion_id uuid, p_cuenta_id uuid, p_sede_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(r.nivel_aprobacion), 0)
  from nucleo.membresias m
  join nucleo.membresia_roles mr on mr.membresia_id = m.id
  join nucleo.roles r on r.id = mr.rol_id and r.activo
  join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
  where m.organizacion_id = p_organizacion_id
    and m.cuenta_id = p_cuenta_id
    and m.estado = 'ACTIVA'
    and (mr.sede_id is null or mr.sede_id = p_sede_id);
$$;

/** Exige nucleo.usuarios.gestionar en TODAS las sedes (rol sin sede) y devuelve la
 *  membresía. Port de exigir_gestion_usuarios. */
create function nucleo.exigir_gestion_usuarios(p_organizacion_id uuid)
returns nucleo.membresias
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.membresia_activa(p_organizacion_id);
begin
  if not exists (
    select 1
    from nucleo.membresia_roles mr
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id
    where mr.membresia_id = v_membresia.id
      and mr.sede_id is null
      and rp.permiso_codigo = 'nucleo.usuarios.gestionar'
  ) then
    raise exception 'SIN_PERMISO: falta el permiso nucleo.usuarios.gestionar en todas las sedes'
      using errcode = '42501';
  end if;
  return v_membresia;
end;
$$;

/** Invariantes de administración, a correr después de quitar roles, permisos o
 *  suspender: alguien tiene que poder administrar usuarios, y el titular tiene que
 *  seguir activo y como administrador. */
create function nucleo.exigir_administracion_vigente(p_organizacion_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from nucleo.membresia_roles mr
    join nucleo.membresias m on m.id = mr.membresia_id and m.estado = 'ACTIVA'
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id
    where mr.organizacion_id = p_organizacion_id
      and mr.sede_id is null
      and rp.permiso_codigo = 'nucleo.usuarios.gestionar'
  ) then
    raise exception 'PRECONDICION: la organización se quedaría sin nadie que administre usuarios'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from nucleo.organizaciones o
    join nucleo.membresias m on m.organizacion_id = o.id and m.cuenta_id = o.titular_id and m.estado = 'ACTIVA'
    join nucleo.membresia_roles mr on mr.membresia_id = m.id and mr.sede_id is null
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'nucleo.usuarios.gestionar'
    where o.id = p_organizacion_id
  ) then
    raise exception 'PRECONDICION: el titular no puede quedar suspendido ni sin rol de administración'
      using errcode = 'P0001';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Eventos: append-only, encadenados por organización
-- ---------------------------------------------------------------------------

/** Hash sha256 del evento, encadenado con el anterior de la misma organización. */
create function nucleo.hash_evento(e nucleo.eventos)
returns text
language sql
stable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      coalesce(e.hash_prev, '') || jsonb_build_object(
        'organizacion_id', e.organizacion_id,
        'sede_id', e.sede_id,
        'secuencia', e.secuencia,
        'entidad', e.entidad,
        'entidad_id', e.entidad_id,
        'accion', e.accion,
        'payload', e.payload,
        'usuario_id', e.usuario_id,
        'dispositivo_id', e.dispositivo_id,
        'creado_en', to_char(e.creado_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
      )::text,
      'sha256'
    ),
    'hex'
  );
$$;

/** Trigger: asigna secuencia, hash_prev, hash y creado_en. Serializa por organización
 *  hasta el fin de la transacción para que la cadena no se bifurque. */
create function nucleo.eventos_encadenar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_secuencia bigint;
  v_hash text;
begin
  perform pg_advisory_xact_lock(hashtextextended('eventos:' || new.organizacion_id::text, 0));

  select e.secuencia, e.hash into v_secuencia, v_hash
  from nucleo.eventos e
  where e.organizacion_id = new.organizacion_id
  order by e.secuencia desc
  limit 1;

  new.secuencia := coalesce(v_secuencia, 0) + 1;
  new.hash_prev := v_hash;
  new.creado_en := clock_timestamp();
  new.hash := nucleo.hash_evento(new);
  return new;
end;
$$;

/** Trigger: eventos no admite update, delete ni truncate. */
create function nucleo.eventos_inmutables()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'eventos es append-only: % no permitido', tg_op using errcode = '42501';
end;
$$;

create trigger eventos_encadenar before insert on nucleo.eventos
  for each row execute function nucleo.eventos_encadenar();
create trigger eventos_sin_update_delete before update or delete on nucleo.eventos
  for each row execute function nucleo.eventos_inmutables();
create trigger eventos_sin_truncate before truncate on nucleo.eventos
  for each statement execute function nucleo.eventos_inmutables();

/** Escribe un evento a nombre de la cuenta actual. Lo usan todas las RPC de escritura. */
create function nucleo.registrar_evento(
  p_organizacion_id uuid,
  p_sede_id uuid,
  p_entidad text,
  p_entidad_id uuid,
  p_accion text,
  p_payload jsonb default '{}'::jsonb,
  p_dispositivo_id uuid default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into nucleo.eventos
    (organizacion_id, sede_id, secuencia, entidad, entidad_id, accion, payload,
     usuario_id, dispositivo_id, hash)
  values
    (p_organizacion_id, p_sede_id, 0, p_entidad, p_entidad_id, p_accion, p_payload,
     auth.uid(), p_dispositivo_id, '');
$$;

-- ---------------------------------------------------------------------------
-- Cuentas, slug y roles semilla
-- ---------------------------------------------------------------------------

/** Trigger sobre auth.users: crea la cuenta global al registrarse. Toma nombre y
 *  apellido de los metadatos del registro, si vienen. */
create function nucleo.crear_cuenta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into nucleo.cuentas (id, nombre, apellido)
  values (
    new.id,
    nullif(btrim(new.raw_user_meta_data ->> 'nombre'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'apellido'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger crear_cuenta after insert on auth.users
  for each row execute function nucleo.crear_cuenta();

/** Slug único a partir del nombre: minúsculas, sin acentos, guiones; sufijo -2, -3…
 *  si ya existe. */
create function nucleo.generar_slug(p_nombre text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base text := left(
    btrim(regexp_replace(lower(extensions.unaccent(coalesce(p_nombre, ''))), '[^a-z0-9]+', '-', 'g'), '-'),
    50
  );
  v_slug text;
  v_n int := 1;
begin
  v_base := btrim(v_base, '-');
  if v_base = '' then
    v_base := 'organizacion';
  end if;
  v_slug := v_base;
  while exists (select 1 from nucleo.organizaciones o where o.slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n;
  end loop;
  return v_slug;
end;
$$;

/** Roles semilla de una organización nueva, con sus permisos. Admin recibe todos.
 *  Devuelve el id del rol Admin. Mismos roles y permisos que el legado; admin.* pasó a
 *  nucleo.*. */
create function nucleo.crear_roles_semilla(p_organizacion_id uuid)
returns uuid
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
  v_admin uuid;
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
      ('Admin', 3, (select array_agg(p.codigo) from nucleo.permisos p))
    ) as t (nombre, nivel, permisos)
  loop
    insert into nucleo.roles (organizacion_id, nombre, nivel_aprobacion, es_sistema)
    values (p_organizacion_id, v_rol.nombre, v_rol.nivel, true)
    returning id into v_id;

    insert into nucleo.rol_permisos (organizacion_id, rol_id, permiso_codigo)
    select p_organizacion_id, v_id, unnest(v_rol.permisos);

    if v_rol.nombre = 'Admin' then
      v_admin := v_id;
    end if;
  end loop;
  return v_admin;
end;
$$;
