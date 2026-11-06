-- Eskemia · Tests de permisos. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/permisos.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

-- ---------------------------------------------------------------------------
-- Estructura y privilegios
-- ---------------------------------------------------------------------------
do $$
declare
  v_tabla text;
  v_funcion text;
begin
  for v_tabla in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  loop
    raise exception 'TEST: la tabla % no tiene RLS', v_tabla;
  end loop;

  for v_tabla in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and (
        has_table_privilege('anon', c.oid, 'select')
        or has_table_privilege('authenticated', c.oid, 'insert,update,delete')
      )
  loop
    raise exception 'TEST: privilegios de más en la tabla %', v_tabla;
  end loop;

  select p.proname into v_funcion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app_private')
    and p.prokind = 'f'
    and pg_get_functiondef(p.oid) ~ '(rol_actual|sede_actual|exigir_perfil|rol_usuario|\.rol\M)'
  limit 1;
  if found then
    raise exception 'TEST: la función % todavía consulta roles fijos', v_funcion;
  end if;

  if has_function_privilege('anon', 'public.mis_permisos()', 'execute')
     or has_function_privilege('anon', 'public.asignar_rol(uuid, uuid, uuid, uuid)', 'execute') then
    raise exception 'TEST: anon puede ejecutar RPC de permisos';
  end if;

  if (select count(*) from public.permisos) <> 17 then
    raise exception 'TEST: el catálogo de permisos no tiene 17 códigos';
  end if;
  if (select count(*) from public.roles) % 7 <> 0
     or not exists (select 1 from public.configuracion_empresa) then
    raise exception 'TEST: faltan roles semilla o configuración de empresa';
  end if;
  if exists (
    select 1 from public.perfiles p
    where not exists (select 1 from public.usuario_roles ur where ur.user_id = p.user_id)
  ) then
    raise exception 'TEST: hay perfiles sin rol migrado';
  end if;
end;
$$;

-- Segunda sede, para probar el alcance por sede.
insert into public.sedes (id, tenant_id, nombre)
values ('00000000-0000-4000-8000-0000000000f2', '00000000-0000-4000-8000-000000000001', 'Sede de test');

-- ---------------------------------------------------------------------------
-- Operario: su sede, sin validar ni administrar
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_sede constant uuid := '00000000-0000-4000-8000-000000000002';
  v_otra constant uuid := '00000000-0000-4000-8000-0000000000f2';
  v_proveedor uuid;
  v_recepcion uuid := gen_random_uuid();
begin
  if not app_private.tiene_permiso('recepcion.recepcion.operar', v_sede) then
    raise exception 'TEST: el operario debería operar en su sede';
  end if;
  if app_private.tiene_permiso('recepcion.recepcion.operar', v_otra) then
    raise exception 'TEST: el operario no debería operar en otra sede';
  end if;
  if app_private.tiene_permiso('recepcion.recepcion.validar') then
    raise exception 'TEST: el operario no debería validar';
  end if;
  if (select count(*) from public.mis_permisos()) <> 2 then
    raise exception 'TEST: el operario debería tener 2 permisos';
  end if;
  if exists (select 1 from public.eventos) then
    raise exception 'TEST: el operario no debería leer eventos';
  end if;
  if exists (select 1 from public.roles) then
    raise exception 'TEST: el operario no debería leer roles';
  end if;
  if (select count(*) from public.perfiles) <> 1 then
    raise exception 'TEST: el operario solo debería ver su perfil';
  end if;
  if exists (select 1 from public.sedes s where s.id = v_otra) then
    raise exception 'TEST: el operario no debería ver otra sede';
  end if;
  if not exists (select 1 from public.recepciones) then
    raise exception 'TEST: el operario debería ver las recepciones de su sede';
  end if;

  select pr.id into v_proveedor from public.proveedores pr limit 1;
  perform public.abrir_recepcion(v_recepcion, v_proveedor, 'TEST-1', v_sede);

  begin
    perform public.abrir_recepcion(gen_random_uuid(), v_proveedor, 'TEST-2', v_otra);
    raise exception 'TEST: abrió una recepción en otra sede' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.validar_recepcion(v_recepcion);
    raise exception 'TEST: el operario validó una recepción' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.marcar_ingresada(v_recepcion);
    raise exception 'TEST: el operario marcó una ingresada' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.verificar_cadena_eventos();
    raise exception 'TEST: el operario verificó la cadena' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.crear_rol('Rol de test');
    raise exception 'TEST: el operario creó un rol' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: todas las sedes y administración de roles
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_operario constant uuid := '00000000-0000-4000-c000-000000000001';
  v_admin constant uuid := '00000000-0000-4000-c000-000000000002';
  v_otra constant uuid := '00000000-0000-4000-8000-0000000000f2';
  v_rol uuid;
  v_rol_admin uuid;
  v_asignacion uuid;
  v_asignacion_admin uuid;
begin
  if (select count(*) from public.mis_permisos()) <> 17 then
    raise exception 'TEST: el admin debería tener los 17 permisos';
  end if;
  if not app_private.tiene_permiso('recepcion.recepcion.operar', v_otra) then
    raise exception 'TEST: el admin debería operar en todas las sedes';
  end if;
  if not exists (select 1 from public.sedes s where s.id = v_otra) then
    raise exception 'TEST: el admin debería ver todas las sedes';
  end if;
  if not exists (select 1 from public.eventos) then
    raise exception 'TEST: el admin debería leer eventos';
  end if;
  if (select count(*) from public.perfiles) < 2 then
    raise exception 'TEST: el admin debería ver los perfiles';
  end if;
  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST: la cadena de eventos está rota';
  end if;

  v_rol := public.crear_rol('Rol de test', 1);
  begin
    perform public.crear_rol('rol de TEST');
    raise exception 'TEST: aceptó un rol con nombre repetido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  perform public.fijar_permiso_rol(v_rol, 'compras.catalogo.ver', true);
  perform public.fijar_permiso_rol(v_rol, 'compras.catalogo.ver', true);
  v_asignacion := public.asignar_rol(v_operario, v_rol, v_otra);
  if public.asignar_rol(v_operario, v_rol, v_otra) <> v_asignacion then
    raise exception 'TEST: asignar_rol debería ser idempotente';
  end if;
  perform public.quitar_rol(v_asignacion);

  select r.id into v_rol_admin from public.roles r where r.nombre = 'Admin';
  select ur.id into v_asignacion_admin from public.usuario_roles ur
  where ur.user_id = v_admin and ur.rol_id = v_rol_admin;

  begin
    perform public.quitar_rol(v_asignacion_admin);
    raise exception 'TEST: dejó a la empresa sin administrador' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  begin
    perform public.fijar_permiso_rol(v_rol_admin, 'admin.usuarios.gestionar', false);
    raise exception 'TEST: dejó a la empresa sin permiso de administración' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
end;
$$;

reset role;
select 'permisos: todos los tests pasaron' as resultado;
rollback;
