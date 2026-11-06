-- Eskemia · Línea base v1 · 05: RPC del núcleo (esquema api).
--
-- Qué hace: alta de organización, invitaciones, administración de miembros y roles,
-- permisos de la sesión, verificación de eventos e Inicio personalizable.
-- Dónde encaja: única vía de escritura del núcleo (CLAUDE.md: nunca updates directos).
-- Cada RPC documenta: qué hace, precondiciones, permisos que exige y eventos que escribe.
-- La cola de emails (pgmq 'emails') se crea en la migración 13.

/** api.crear_organizacion
 *  Qué hace: crea la organización con slug único, su perfil vacío, una sede "Principal",
 *    los roles semilla, la membresía ACTIVA del titular con rol Admin en todas las sedes y
 *    habilita todos los módulos registrados.
 *  Precondiciones: sesión iniciada; nombre no vacío; puesto (opcional) del catálogo global.
 *  Permisos: ninguno (cualquier cuenta puede crear su organización).
 *  Eventos: organizacion/creada.
 *  Devuelve: {id, slug}. */
create function api.crear_organizacion(p_nombre text, p_descripcion text default null, p_puesto_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuenta uuid := auth.uid();
  v_nombre text := btrim(p_nombre);
  v_org uuid;
  v_slug text;
  v_admin uuid;
  v_membresia uuid;
  v_sede uuid;
begin
  if v_cuenta is null or not exists (select 1 from nucleo.cuentas c where c.id = v_cuenta) then
    raise exception 'SIN_PERMISO: hay que iniciar sesión' using errcode = '42501';
  end if;
  if coalesce(v_nombre, '') = '' then
    raise exception 'PRECONDICION: falta el nombre de la organización' using errcode = 'P0001';
  end if;
  if p_puesto_id is not null and not exists (
    select 1 from nucleo.puestos p where p.id = p_puesto_id and p.organizacion_id is null and p.activo
  ) then
    raise exception 'NO_ENCONTRADO: puesto inexistente' using errcode = 'P0002';
  end if;

  v_slug := nucleo.generar_slug(v_nombre);
  insert into nucleo.organizaciones (slug, nombre, descripcion, titular_id)
  values (v_slug, v_nombre, nullif(btrim(p_descripcion), ''), v_cuenta)
  returning id into v_org;

  insert into nucleo.perfil_organizacion (organizacion_id) values (v_org);
  insert into nucleo.sedes (organizacion_id, nombre) values (v_org, 'Principal') returning id into v_sede;

  v_admin := nucleo.crear_roles_semilla(v_org);

  insert into nucleo.membresias (organizacion_id, cuenta_id, puesto_id, estado, unida_en)
  values (v_org, v_cuenta, p_puesto_id, 'ACTIVA', now())
  returning id into v_membresia;

  insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id)
  values (v_org, v_membresia, v_admin);

  insert into nucleo.modulos_habilitados (organizacion_id, modulo_codigo)
  select v_org, m.codigo from nucleo.modulos m;

  perform nucleo.registrar_evento(
    v_org, null, 'organizacion', v_org, 'creada',
    jsonb_build_object('nombre', v_nombre, 'slug', v_slug, 'sede_id', v_sede)
  );
  return jsonb_build_object('id', v_org, 'slug', v_slug);
end;
$$;

/** api.invitar
 *  Qué hace: crea una invitación de un solo uso (vence a los 7 días) y encola el email
 *    con el enlace. Una invitación pendiente previa al mismo email queda REVOCADA.
 *  Precondiciones: email válido y que no sea ya miembro activo; rol, sede y puesto de la
 *    organización (o puesto global).
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: invitacion/creada (sin el token).
 *  Devuelve: id de la invitación. El token viaja solo en el mensaje de la cola. */
create function api.invitar(
  p_organizacion_id uuid,
  p_email text,
  p_puesto_id uuid,
  p_rol_id uuid,
  p_sede_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.exigir_gestion_usuarios(p_organizacion_id);
  v_email text := lower(btrim(p_email));
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
  v_org nucleo.organizaciones;
begin
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'PRECONDICION: el email no es válido' using errcode = 'P0001';
  end if;
  if not exists (select 1 from nucleo.roles r where r.id = p_rol_id and r.organizacion_id = p_organizacion_id) then
    raise exception 'NO_ENCONTRADO: rol inexistente' using errcode = 'P0002';
  end if;
  if p_sede_id is not null and not exists (
    select 1 from nucleo.sedes s where s.id = p_sede_id and s.organizacion_id = p_organizacion_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  if p_puesto_id is not null and not exists (
    select 1 from nucleo.puestos p
    where p.id = p_puesto_id and (p.organizacion_id is null or p.organizacion_id = p_organizacion_id)
  ) then
    raise exception 'NO_ENCONTRADO: puesto inexistente' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from nucleo.membresias m join auth.users u on u.id = m.cuenta_id
    where m.organizacion_id = p_organizacion_id and m.estado = 'ACTIVA' and lower(u.email) = v_email
  ) then
    raise exception 'PRECONDICION: esa persona ya es miembro de la organización' using errcode = 'P0001';
  end if;

  update nucleo.invitaciones i set estado = 'REVOCADA'
  where i.organizacion_id = p_organizacion_id and i.email = v_email and i.estado = 'PENDIENTE';

  insert into nucleo.invitaciones
    (organizacion_id, email, puesto_id, rol_id, sede_id, token_hash, vence_en, creada_por)
  values
    (p_organizacion_id, v_email, p_puesto_id, p_rol_id, p_sede_id,
     encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '7 days', v_membresia.cuenta_id)
  returning id into v_id;

  select * into v_org from nucleo.organizaciones o where o.id = p_organizacion_id;
  perform pgmq.send('emails', jsonb_build_object(
    'tipo', 'invitacion',
    'para', v_email,
    'invitacion_id', v_id,
    'token', v_token,
    'organizacion', v_org.nombre,
    'invitada_por', v_membresia.cuenta_id
  ));

  perform nucleo.registrar_evento(
    p_organizacion_id, p_sede_id, 'invitacion', v_id, 'creada',
    jsonb_build_object('email', v_email, 'rol_id', p_rol_id, 'puesto_id', p_puesto_id)
  );
  return v_id;
end;
$$;

/** api.aceptar_invitacion
 *  Qué hace: canjea el token: crea (o reactiva si estaba INVITADA) la membresía ACTIVA,
 *    le asigna el rol y la sede de la invitación y la marca ACEPTADA.
 *  Precondiciones: sesión iniciada; token pendiente y vigente; el email de la cuenta es
 *    el invitado; la cuenta no está suspendida en esa organización.
 *  Permisos: ninguno más allá de tener el token.
 *  Eventos: invitacion/aceptada.
 *  Devuelve: {organizacion_id, slug}. */
create function api.aceptar_invitacion(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuenta uuid := auth.uid();
  v_inv nucleo.invitaciones;
  v_email text;
  v_membresia nucleo.membresias;
begin
  if v_cuenta is null then
    raise exception 'SIN_PERMISO: hay que iniciar sesión' using errcode = '42501';
  end if;

  select * into v_inv from nucleo.invitaciones i
  where i.token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  for update;
  if not found or v_inv.estado <> 'PENDIENTE' then
    raise exception 'NO_ENCONTRADO: la invitación no existe o ya se usó' using errcode = 'P0002';
  end if;
  -- Vencida se deduce de vence_en (marcarla acá no sirve: el error deshace el update).
  if v_inv.vence_en < now() then
    raise exception 'PRECONDICION: la invitación venció: pedí una nueva' using errcode = 'P0001';
  end if;

  select lower(u.email) into v_email from auth.users u where u.id = v_cuenta;
  if v_email is distinct from v_inv.email then
    raise exception 'SIN_PERMISO: la invitación es para otro email' using errcode = '42501';
  end if;

  select * into v_membresia from nucleo.membresias m
  where m.organizacion_id = v_inv.organizacion_id and m.cuenta_id = v_cuenta;
  if found and v_membresia.estado = 'SUSPENDIDA' then
    raise exception 'PRECONDICION: tu acceso a esta organización está suspendido' using errcode = 'P0001';
  end if;

  if not found then
    insert into nucleo.membresias (organizacion_id, cuenta_id, puesto_id, estado, invitada_por, unida_en)
    values (v_inv.organizacion_id, v_cuenta, v_inv.puesto_id, 'ACTIVA', v_inv.creada_por, now())
    returning * into v_membresia;
  elsif v_membresia.estado = 'INVITADA' then
    update nucleo.membresias
    set estado = 'ACTIVA', unida_en = now(), puesto_id = coalesce(v_inv.puesto_id, puesto_id)
    where id = v_membresia.id;
  end if;

  insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id, sede_id)
  values (v_inv.organizacion_id, v_membresia.id, v_inv.rol_id, v_inv.sede_id)
  on conflict do nothing;

  update nucleo.invitaciones
  set estado = 'ACEPTADA', aceptada_por = v_cuenta, aceptada_en = now()
  where id = v_inv.id;

  perform nucleo.registrar_evento(
    v_inv.organizacion_id, v_inv.sede_id, 'invitacion', v_inv.id, 'aceptada',
    jsonb_build_object('membresia_id', v_membresia.id, 'rol_id', v_inv.rol_id)
  );
  return jsonb_build_object(
    'organizacion_id', v_inv.organizacion_id,
    'slug', (select o.slug from nucleo.organizaciones o where o.id = v_inv.organizacion_id)
  );
end;
$$;

/** api.cambiar_estado_miembro
 *  Qué hace: suspende o reactiva una membresía.
 *  Precondiciones: estado ACTIVA o SUSPENDIDA; el titular no puede quedar suspendido y
 *    siempre queda alguien que administre usuarios.
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: membresia/estado:<nuevo>. */
create function api.cambiar_estado_miembro(p_membresia_id uuid, p_estado text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fila nucleo.membresias;
begin
  select * into v_fila from nucleo.membresias m where m.id = p_membresia_id;
  perform nucleo.exigir_miembro(v_fila.organizacion_id, 'miembro');
  perform nucleo.exigir_gestion_usuarios(v_fila.organizacion_id);
  if p_estado not in ('ACTIVA', 'SUSPENDIDA') then
    raise exception 'PRECONDICION: estado no válido' using errcode = 'P0001';
  end if;
  if v_fila.estado = p_estado then
    return;
  end if;
  if v_fila.estado = 'INVITADA' then
    raise exception 'PRECONDICION: la invitación todavía no se aceptó' using errcode = 'P0001';
  end if;

  update nucleo.membresias set estado = p_estado where id = p_membresia_id;
  perform nucleo.exigir_administracion_vigente(v_fila.organizacion_id);

  perform nucleo.registrar_evento(
    v_fila.organizacion_id, null, 'membresia', p_membresia_id, 'estado:' || p_estado,
    jsonb_build_object('cuenta_id', v_fila.cuenta_id, 'desde', v_fila.estado)
  );
end;
$$;

/** api.transferir_titularidad
 *  Qué hace: pasa la titularidad a otro miembro activo. Si el nuevo titular no
 *    administra usuarios en todas las sedes, recibe el rol Admin.
 *  Precondiciones: quien llama es el titular; el destino es miembro activo y distinto.
 *  Permisos: ser el titular.
 *  Eventos: organizacion/titularidad_transferida. */
create function api.transferir_titularidad(p_organizacion_id uuid, p_cuenta_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org nucleo.organizaciones;
  v_destino nucleo.membresias;
  v_admin uuid;
begin
  perform nucleo.exigir_miembro(p_organizacion_id, 'organización');
  select * into v_org from nucleo.organizaciones o where o.id = p_organizacion_id for update;
  if v_org.titular_id <> auth.uid() then
    raise exception 'SIN_PERMISO: solo el titular puede transferir la titularidad' using errcode = '42501';
  end if;
  select * into v_destino from nucleo.membresias m
  where m.organizacion_id = p_organizacion_id and m.cuenta_id = p_cuenta_id and m.estado = 'ACTIVA';
  if not found or p_cuenta_id = v_org.titular_id then
    raise exception 'NO_ENCONTRADO: el destino tiene que ser otro miembro activo' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from nucleo.membresia_roles mr
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'nucleo.usuarios.gestionar'
    where mr.membresia_id = v_destino.id and mr.sede_id is null
  ) then
    select r.id into v_admin from nucleo.roles r
    where r.organizacion_id = p_organizacion_id and r.nombre = 'Admin' and r.es_sistema;
    insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id)
    values (p_organizacion_id, v_destino.id, v_admin)
    on conflict do nothing;
  end if;

  update nucleo.organizaciones set titular_id = p_cuenta_id where id = p_organizacion_id;
  perform nucleo.exigir_administracion_vigente(p_organizacion_id);

  perform nucleo.registrar_evento(
    p_organizacion_id, null, 'organizacion', p_organizacion_id, 'titularidad_transferida',
    jsonb_build_object('desde', v_org.titular_id, 'hacia', p_cuenta_id)
  );
end;
$$;

/** api.mis_permisos
 *  Qué hace: permisos efectivos de la cuenta actual en la organización, con su alcance
 *    (sede nula = todas). Omite los de módulos deshabilitados.
 *  Precondiciones: ninguna (sin membresía activa devuelve vacío).
 *  Permisos: ninguno. Eventos: ninguno (solo lectura). */
create function api.mis_permisos(p_organizacion_id uuid)
returns table (permiso text, sede_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permiso_codigo, mr.sede_id
  from nucleo.membresias m
  join nucleo.membresia_roles mr on mr.membresia_id = m.id
  join nucleo.roles r on r.id = mr.rol_id and r.activo
  join nucleo.rol_permisos rp on rp.rol_id = r.id
  join nucleo.permisos p on p.codigo = rp.permiso_codigo
  where m.cuenta_id = (select auth.uid())
    and m.organizacion_id = p_organizacion_id
    and m.estado = 'ACTIVA'
    and nucleo.modulo_habilitado(p_organizacion_id, p.modulo);
$$;

/** api.verificar_cadena_eventos
 *  Qué hace: recorre los eventos de la organización y verifica secuencia y hashes.
 *  Permisos: nucleo.eventos.verificar. Eventos: ninguno.
 *  Devuelve: {ok, total, rota_en}. */
create function api.verificar_cadena_eventos(p_organizacion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'nucleo.eventos.verificar');
  e nucleo.eventos;
  v_prev text := null;
  v_esperada bigint := 1;
begin
  for e in
    select * from nucleo.eventos ev
    where ev.organizacion_id = v_membresia.organizacion_id
    order by ev.secuencia
  loop
    if e.secuencia <> v_esperada
       or e.hash_prev is distinct from v_prev
       or e.hash <> nucleo.hash_evento(e) then
      return jsonb_build_object('ok', false, 'total', v_esperada - 1, 'rota_en', v_esperada);
    end if;
    v_prev := e.hash;
    v_esperada := v_esperada + 1;
  end loop;
  return jsonb_build_object('ok', true, 'total', v_esperada - 1, 'rota_en', null);
end;
$$;

/** api.crear_rol
 *  Qué hace: crea un rol vacío (sin permisos) en la organización.
 *  Precondiciones: nombre no vacío y único; nivel >= 0.
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: rol/alta. */
create function api.crear_rol(p_organizacion_id uuid, p_nombre text, p_nivel_aprobacion int default 0)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.exigir_gestion_usuarios(p_organizacion_id);
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
    select 1 from nucleo.roles r
    where r.organizacion_id = v_membresia.organizacion_id and lower(r.nombre) = lower(v_nombre)
  ) then
    raise exception 'PRECONDICION: ya existe un rol con ese nombre' using errcode = 'P0001';
  end if;

  insert into nucleo.roles (organizacion_id, nombre, nivel_aprobacion)
  values (v_membresia.organizacion_id, v_nombre, p_nivel_aprobacion)
  returning id into v_id;

  perform nucleo.registrar_evento(
    v_membresia.organizacion_id, null, 'rol', v_id, 'alta',
    jsonb_build_object('nombre', v_nombre, 'nivel_aprobacion', p_nivel_aprobacion)
  );
  return v_id;
end;
$$;

/** api.asignar_rol
 *  Qué hace: asigna un rol a un miembro, con alcance opcional de sede y sector.
 *    Idempotente: si la asignación ya existe, devuelve su id.
 *  Precondiciones: la cuenta tiene membresía en la organización del rol; sede y sector
 *    de la misma organización.
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: membresia_rol/asignado. */
create function api.asignar_rol(p_cuenta_id uuid, p_rol_id uuid, p_sede_id uuid default null, p_sector_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select r.organizacion_id from nucleo.roles r where r.id = p_rol_id), 'rol');
  v_gestor nucleo.membresias := nucleo.exigir_gestion_usuarios(v_org);
  v_destino uuid;
  v_id uuid;
begin
  select m.id into v_destino from nucleo.membresias m
  where m.cuenta_id = p_cuenta_id and m.organizacion_id = v_org;
  if not found then
    raise exception 'NO_ENCONTRADO: usuario inexistente' using errcode = 'P0002';
  end if;
  if p_sede_id is not null and not exists (
    select 1 from nucleo.sedes s where s.id = p_sede_id and s.organizacion_id = v_org
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  if p_sector_id is not null and not exists (
    select 1 from nucleo.sectores s where s.id = p_sector_id and s.organizacion_id = v_org
  ) then
    raise exception 'NO_ENCONTRADO: sector inexistente' using errcode = 'P0002';
  end if;

  select mr.id into v_id from nucleo.membresia_roles mr
  where mr.membresia_id = v_destino
    and mr.rol_id = p_rol_id
    and mr.sede_id is not distinct from p_sede_id
    and mr.sector_id is not distinct from p_sector_id;
  if found then
    return v_id;
  end if;

  insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id, sede_id, sector_id)
  values (v_org, v_destino, p_rol_id, p_sede_id, p_sector_id)
  returning id into v_id;

  perform nucleo.registrar_evento(
    v_org, p_sede_id, 'membresia_rol', v_id, 'asignado',
    jsonb_build_object('cuenta_id', p_cuenta_id, 'rol_id', p_rol_id, 'sector_id', p_sector_id,
                       'por', v_gestor.cuenta_id)
  );
  return v_id;
end;
$$;

/** api.quitar_rol
 *  Qué hace: quita una asignación de rol.
 *  Precondiciones: siguen vigentes la administración de usuarios y el titular como Admin.
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: membresia_rol/quitado. */
create function api.quitar_rol(p_membresia_rol_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select mr.organizacion_id from nucleo.membresia_roles mr where mr.id = p_membresia_rol_id), 'asignación');
  v_gestor nucleo.membresias := nucleo.exigir_gestion_usuarios(v_org);
  v_fila nucleo.membresia_roles;
begin
  delete from nucleo.membresia_roles mr
  where mr.id = p_membresia_rol_id and mr.organizacion_id = v_org
  returning * into v_fila;
  perform nucleo.exigir_administracion_vigente(v_org);

  perform nucleo.registrar_evento(
    v_org, v_fila.sede_id, 'membresia_rol', v_fila.id, 'quitado',
    jsonb_build_object('membresia_id', v_fila.membresia_id, 'rol_id', v_fila.rol_id,
                       'sector_id', v_fila.sector_id, 'por', v_gestor.cuenta_id)
  );
end;
$$;

/** api.fijar_permiso_rol
 *  Qué hace: agrega o quita un permiso de un rol.
 *  Precondiciones: rol de la organización y permiso del catálogo; al quitar, siguen
 *    vigentes la administración de usuarios y el titular como Admin.
 *  Permisos: nucleo.usuarios.gestionar en todas las sedes.
 *  Eventos: rol/permiso_agregado o rol/permiso_quitado. */
create function api.fijar_permiso_rol(p_rol_id uuid, p_permiso text, p_activo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select r.organizacion_id from nucleo.roles r where r.id = p_rol_id), 'rol');
  v_gestor nucleo.membresias := nucleo.exigir_gestion_usuarios(v_org);
begin
  if not exists (select 1 from nucleo.permisos p where p.codigo = p_permiso) then
    raise exception 'NO_ENCONTRADO: permiso inexistente' using errcode = 'P0002';
  end if;

  if p_activo then
    insert into nucleo.rol_permisos (organizacion_id, rol_id, permiso_codigo)
    values (v_org, p_rol_id, p_permiso)
    on conflict (rol_id, permiso_codigo) do nothing;
  else
    delete from nucleo.rol_permisos rp where rp.rol_id = p_rol_id and rp.permiso_codigo = p_permiso;
    perform nucleo.exigir_administracion_vigente(v_org);
  end if;

  perform nucleo.registrar_evento(
    v_org, null, 'rol', p_rol_id, case when p_activo then 'permiso_agregado' else 'permiso_quitado' end,
    jsonb_build_object('permiso', p_permiso, 'por', v_gestor.cuenta_id)
  );
end;
$$;

/** api.fijar_limite_rol
 *  Qué hace: fija el monto hasta el que un rol pide sin aprobación (nulo = sin límite).
 *  Precondiciones: límite >= 0; rol de la organización.
 *  Permisos: compras.aprobacion.configurar.
 *  Eventos: rol/limite_monto. */
create function api.fijar_limite_rol(p_rol_id uuid, p_limite numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select r.organizacion_id from nucleo.roles r where r.id = p_rol_id), 'rol');
  v_membresia nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.aprobacion.configurar');
begin
  if p_limite < 0 then
    raise exception 'PRECONDICION: el límite no puede ser negativo' using errcode = 'P0001';
  end if;
  update nucleo.roles r set limite_monto_sin_aprobacion = p_limite
  where r.id = p_rol_id and r.organizacion_id = v_membresia.organizacion_id;

  perform nucleo.registrar_evento(
    v_org, null, 'rol', p_rol_id, 'limite_monto', jsonb_build_object('limite', p_limite)
  );
end;
$$;

/** api.guardar_inicio
 *  Qué hace: reemplaza la elección de tarjetas del Inicio de la cuenta actual en la
 *    organización. El orden es el del arreglo.
 *  Precondiciones: membresía activa; p_tarjetas es un arreglo de
 *    {codigo: 'modulo.tarjeta', visible: bool} sin códigos repetidos (máx. 50).
 *  Permisos: ninguno (es una preferencia personal).
 *  Eventos: inicio/guardado. */
create function api.guardar_inicio(p_organizacion_id uuid, p_tarjetas jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_membresia nucleo.membresias := nucleo.membresia_activa(p_organizacion_id);
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
