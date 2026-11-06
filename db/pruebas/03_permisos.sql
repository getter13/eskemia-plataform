-- Eskemia · Tests de permisos (pgTAP). Portado de supabase/tests/permisos.sql (legado).
--
-- Qué verifica: alcance por sede del operario, que no valida ni administra, y que el
-- Admin opera en todas las sedes, gestiona roles con idempotencia y no puede dejar a la
-- organización sin administración.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).

select pruebas.escenario();
select * from no_plan();

-- Operario: su sede, sin validar ni administrar ------------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  v_org uuid := pruebas.id('org');
  v_sede uuid := pruebas.id('sede');
  v_otra uuid := pruebas.id('sede2');
  v_proveedor uuid;
  v_recepcion uuid := gen_random_uuid();
begin
  perform pruebas.no('el operario opera en su sede', not nucleo.tiene_permiso(v_org, 'recepcion.recepcion.operar', v_sede));
  perform pruebas.no('el operario no opera en otra sede', nucleo.tiene_permiso(v_org, 'recepcion.recepcion.operar', v_otra));
  perform pruebas.no('el operario no valida', nucleo.tiene_permiso(v_org, 'recepcion.recepcion.validar'));
  perform pruebas.no('el operario tiene 2 permisos', (select count(*) from api.mis_permisos(v_org)) <> 2);
  perform pruebas.no('el operario no lee eventos', exists (select 1 from api.eventos));
  perform pruebas.no('el operario no ve otra sede', exists (select 1 from api.sedes s where s.id = v_otra));

  v_proveedor := api.alta_rapida_proveedor(v_org, gen_random_uuid(), 'Proveedor de test', '30999999991');
  perform api.abrir_recepcion(v_org, v_recepcion, v_proveedor, 'TEST-1', v_sede, null, null, null);
  perform pruebas.no('el operario ve las recepciones de su sede', not exists (select 1 from api.recepciones));

  perform pruebas.falla('no abre una recepción en otra sede', 'SIN_PERMISO',
    format('select api.abrir_recepcion(%L, gen_random_uuid(), %L, %L, %L, null, null, null)', v_org, v_proveedor, 'TEST-2', v_otra));
  perform pruebas.falla('el operario no valida una recepción', 'SIN_PERMISO',
    format('select api.validar_recepcion(%L, null)', v_recepcion));
  perform pruebas.falla('el operario no marca ingresada', 'SIN_PERMISO',
    format('select api.marcar_ingresada(%L)', v_recepcion));
  perform pruebas.falla('el operario no verifica la cadena', 'SIN_PERMISO',
    format('select api.verificar_cadena_eventos(%L)', v_org));
  perform pruebas.falla('el operario no crea roles', 'SIN_PERMISO',
    format('select api.crear_rol(%L, %L, 0)', v_org, 'Rol de test'));
end;
$$;
reset role;

-- Admin: todas las sedes y administración de roles ----------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
declare
  v_org uuid := pruebas.id('org');
  v_otra uuid := pruebas.id('sede2');
  v_operario constant uuid := 'e0000000-0000-4000-8000-000000000002';
  v_rol uuid;
  v_rol_admin uuid;
  v_asignacion uuid;
  v_asignacion_admin uuid;
begin
  perform pruebas.no('el admin tiene los 18 permisos',
    (select count(distinct permiso) from api.mis_permisos(v_org)) <> 18);
  perform pruebas.no('el admin opera en todas las sedes', not nucleo.tiene_permiso(v_org, 'recepcion.recepcion.operar', v_otra));
  perform pruebas.no('el admin ve todas las sedes', not exists (select 1 from api.sedes s where s.id = v_otra));
  perform pruebas.no('el admin lee eventos', not exists (select 1 from api.eventos));
  perform pruebas.no('el admin ve a los miembros', (select count(*) from api.miembros) < 2);
  perform pruebas.no('la cadena de eventos verifica', not (api.verificar_cadena_eventos(v_org) ->> 'ok')::boolean);

  v_rol := api.crear_rol(v_org, 'Rol de test', 1);
  perform pruebas.falla('rol con nombre repetido rechazado', 'PRECONDICION',
    format('select api.crear_rol(%L, %L, 0)', v_org, 'rol de TEST'));

  perform api.fijar_permiso_rol(v_rol, 'compras.catalogo.ver', true);
  perform api.fijar_permiso_rol(v_rol, 'compras.catalogo.ver', true);
  v_asignacion := api.asignar_rol(v_operario, v_rol, v_otra, null);
  perform pruebas.no('asignar_rol es idempotente', api.asignar_rol(v_operario, v_rol, v_otra, null) <> v_asignacion);
  perform api.quitar_rol(v_asignacion);

  select r.id into v_rol_admin from api.roles r where r.organizacion_id = v_org and r.nombre = 'Admin';
  select mr.id into v_asignacion_admin from api.membresia_roles mr
  where mr.cuenta_id = 'e0000000-0000-4000-8000-000000000001' and mr.rol_id = v_rol_admin;

  perform pruebas.falla('no deja a la organización sin administrador', 'PRECONDICION',
    format('select api.quitar_rol(%L)', v_asignacion_admin));
  perform pruebas.falla('no deja a la organización sin gestión de usuarios', 'PRECONDICION',
    format('select api.fijar_permiso_rol(%L, %L, false)', v_rol_admin, 'nucleo.usuarios.gestionar'));
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
