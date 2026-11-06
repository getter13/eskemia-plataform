-- Eskemia · Tests de las RPC del núcleo (pgTAP).
--
-- Qué verifica: alta de organización, invitaciones (canje, email equivocado, reuso y
-- vencimiento), suspensión, invariantes del titular, transferencia de titularidad,
-- Inicio personalizable, bloqueo por módulo deshabilitado y cadena de eventos.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).

select pruebas.usuario('10000000-0000-4000-8000-000000000001', 'tita@eskemia.test', 'Tita');
select pruebas.usuario('10000000-0000-4000-8000-000000000002', 'carla@eskemia.test', 'Carla');
select pruebas.usuario('10000000-0000-4000-8000-000000000003', 'otto@eskemia.test', 'Otto');
select pruebas.usuario('10000000-0000-4000-8000-000000000004', 'dani@eskemia.test', 'Dani');

-- Alta de organización ----------------------------------------------------------
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('org', $$select api.crear_organizacion('Fábrica Sur', 'Pastas frescas', (select id from api.puestos where nombre = 'Gerencia'))$$);
select pruebas.anotar('org2', $$select api.crear_organizacion('Fábrica  Sur')$$);
select pruebas.anotar('org_vacia', $$select api.crear_organizacion('   ')$$);
reset role;

create temp view org as select (valor::jsonb ->> 'id')::uuid as id from r where clave = 'org';
grant select on org to authenticated;

select * from no_plan();

select is((select valor::jsonb ->> 'slug' from r where clave = 'org'), 'fabrica-sur', 'slug sin acentos');
select is((select valor::jsonb ->> 'slug' from r where clave = 'org2'), 'fabrica-sur-2', 'slug repetido lleva sufijo');
select matches((select valor from r where clave = 'org_vacia'), '^ERROR: PRECONDICION', 'nombre vacío rechazado');
select is((select count(*)::int from nucleo.roles where organizacion_id = (select id from org)), 7, '7 roles semilla');
select is((select nombre from nucleo.sedes where organizacion_id = (select id from org)), 'Principal', 'sede Principal');
select is((select count(*)::int from nucleo.modulos_habilitados where organizacion_id = (select id from org)), 3, 'módulos habilitados');
select ok(exists (
  select 1 from nucleo.membresias m
  join nucleo.membresia_roles mr on mr.membresia_id = m.id and mr.sede_id is null
  join nucleo.roles ro on ro.id = mr.rol_id and ro.nombre = 'Admin'
  where m.organizacion_id = (select id from org) and m.cuenta_id = '10000000-0000-4000-8000-000000000001'
    and m.estado = 'ACTIVA' and m.puesto_id is not null
), 'la titular es miembro activo con Admin en todas las sedes y su puesto');
select ok(exists (
  select 1 from nucleo.eventos where organizacion_id = (select id from org) and entidad = 'organizacion' and accion = 'creada'
), 'evento organizacion/creada');

select pruebas.como(null);
select pruebas.anotar('sin_sesion', $$select api.crear_organizacion('Fantasma')$$);
reset role;
select matches((select valor from r where clave = 'sin_sesion'), '^ERROR: SIN_PERMISO', 'sin sesión no crea organizaciones');

-- Invitaciones ------------------------------------------------------------------
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('inv_carla', $$select api.invitar((select id from org), '  Carla@Eskemia.test ', null,
  (select id from api.roles where organizacion_id = (select id from org) and nombre = 'Comprador'),
  (select id from api.sedes where organizacion_id = (select id from org)))$$);
select pruebas.anotar('inv_dani', $$select api.invitar((select id from org), 'dani@eskemia.test', null,
  (select id from api.roles where organizacion_id = (select id from org) and nombre = 'Comprador'))$$);
select pruebas.anotar('inv_mail_malo', $$select api.invitar((select id from org), 'no-es-un-mail', null,
  (select id from api.roles where organizacion_id = (select id from org) and nombre = 'Comprador'))$$);
reset role;

create temp view tokens as
  select q.message ->> 'para' as para, q.message ->> 'token' as token
  from pgmq.q_emails q where q.message ->> 'tipo' = 'invitacion';
grant select on tokens to authenticated;

select is((select count(*)::int from tokens where para in ('carla@eskemia.test', 'dani@eskemia.test')), 2,
  'cada invitación encola su email (normalizado)');
select ok((select token_hash from nucleo.invitaciones where email = 'carla@eskemia.test')
  <> (select token from tokens where para = 'carla@eskemia.test'), 'la base guarda el hash, no el token');
select matches((select valor from r where clave = 'inv_mail_malo'), '^ERROR: PRECONDICION', 'email inválido rechazado');

select pruebas.como('10000000-0000-4000-8000-000000000003');
select pruebas.anotar('acepta_otto', $$select api.aceptar_invitacion((select token from tokens where para = 'carla@eskemia.test'))$$);
select pruebas.como('10000000-0000-4000-8000-000000000002');
select pruebas.anotar('acepta_carla', $$select api.aceptar_invitacion((select token from tokens where para = 'carla@eskemia.test'))$$);
select pruebas.anotar('acepta_carla_2', $$select api.aceptar_invitacion((select token from tokens where para = 'carla@eskemia.test'))$$);
select pruebas.anotar('carla_pide', $$select count(*) from api.mis_permisos((select id from org)) where permiso = 'compras.pedido.crear'$$);
select pruebas.anotar('carla_gestiona', $$select count(*) from api.mis_permisos((select id from org)) where permiso like 'nucleo.%'$$);
select pruebas.anotar('carla_invita', $$select api.invitar((select id from org), 'x@eskemia.test', null,
  (select id from api.roles where organizacion_id = (select id from org) and nombre = 'Comprador'))$$);
reset role;

update nucleo.invitaciones set vence_en = now() - interval '1 day' where email = 'dani@eskemia.test';
select pruebas.como('10000000-0000-4000-8000-000000000004');
select pruebas.anotar('acepta_dani_vencida', $$select api.aceptar_invitacion((select token from tokens where para = 'dani@eskemia.test'))$$);
reset role;

select matches((select valor from r where clave = 'acepta_otto'), '^ERROR: SIN_PERMISO', 'otra cuenta no canjea la invitación');
select is((select valor::jsonb ->> 'slug' from r where clave = 'acepta_carla'), 'fabrica-sur', 'la invitada canjea y entra');
select matches((select valor from r where clave = 'acepta_carla_2'), '^ERROR: NO_ENCONTRADO', 'el token es de un solo uso');
select is((select valor from r where clave = 'carla_pide'), '1', 'la invitada recibe los permisos de su rol');
select is((select valor from r where clave = 'carla_gestiona'), '0', 'y no los de administración');
select matches((select valor from r where clave = 'carla_invita'), '^ERROR: SIN_PERMISO', 'sin gestión de usuarios no se invita');
select matches((select valor from r where clave = 'acepta_dani_vencida'), '^ERROR: PRECONDICION: la invitación venció', 'invitación vencida rechazada');

-- Suspensión e invariantes del titular -------------------------------------------
create temp view membresia as
  select m.id, m.cuenta_id from nucleo.membresias m where m.organizacion_id = (select id from org);
grant select on membresia to authenticated;

select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('suspende_carla', $$select api.cambiar_estado_miembro(
  (select id from membresia where cuenta_id = '10000000-0000-4000-8000-000000000002'), 'SUSPENDIDA')$$);
select pruebas.anotar('suspende_titular', $$select api.cambiar_estado_miembro(
  (select id from membresia where cuenta_id = '10000000-0000-4000-8000-000000000001'), 'SUSPENDIDA')$$);
select pruebas.anotar('quita_admin_titular', $$select api.quitar_rol((
  select mr.id from nucleo.membresia_roles mr join nucleo.roles ro on ro.id = mr.rol_id
  where mr.membresia_id = (select id from membresia where cuenta_id = '10000000-0000-4000-8000-000000000001')
    and ro.nombre = 'Admin'))$$);
select pruebas.como('10000000-0000-4000-8000-000000000002');
select pruebas.anotar('carla_suspendida_orgs', $$select count(*) from api.mis_organizaciones$$);
select pruebas.anotar('carla_suspendida_sedes', $$select count(*) from api.sedes$$);
reset role;

select is((select valor from r where clave = 'suspende_carla'), 'OK', 'se suspende a un miembro');
select is((select valor from r where clave = 'carla_suspendida_orgs'), '0', 'la suspendida ya no ve la organización');
select is((select valor from r where clave = 'carla_suspendida_sedes'), '0', 'ni sus datos');
select matches((select valor from r where clave = 'suspende_titular'), '^ERROR: PRECONDICION', 'el titular no se suspende');
select matches((select valor from r where clave = 'quita_admin_titular'), '^ERROR: PRECONDICION', 'el titular no pierde Admin');

-- Transferencia de titularidad --------------------------------------------------
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('reactiva_carla', $$select api.cambiar_estado_miembro(
  (select id from membresia where cuenta_id = '10000000-0000-4000-8000-000000000002'), 'ACTIVA')$$);
select pruebas.como('10000000-0000-4000-8000-000000000002');
select pruebas.anotar('carla_transfiere', $$select api.transferir_titularidad((select id from org), '10000000-0000-4000-8000-000000000002')$$);
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('tita_transfiere', $$select api.transferir_titularidad((select id from org), '10000000-0000-4000-8000-000000000002')$$);
reset role;

select matches((select valor from r where clave = 'carla_transfiere'), '^ERROR: SIN_PERMISO', 'solo el titular transfiere');
select is((select valor from r where clave = 'tita_transfiere'), 'OK', 'el titular transfiere a un miembro activo');
select is((select titular_id from nucleo.organizaciones where id = (select id from org)),
  '10000000-0000-4000-8000-000000000002'::uuid, 'Carla es la nueva titular');
select ok(exists (
  select 1 from nucleo.membresia_roles mr join nucleo.roles ro on ro.id = mr.rol_id and ro.nombre = 'Admin'
  where mr.membresia_id = (select id from membresia where cuenta_id = '10000000-0000-4000-8000-000000000002')
    and mr.sede_id is null
), 'la nueva titular recibe Admin en todas las sedes');

-- Inicio personalizable ---------------------------------------------------------
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('inicio', $$select api.guardar_inicio((select id from org),
  '[{"codigo": "recepcion.hoy"}, {"codigo": "compras.pendientes", "visible": false}]')$$);
select pruebas.anotar('inicio_orden', $$select string_agg(tarjeta_codigo || ':' || visible, ',' order by orden) from api.mi_inicio$$);
select pruebas.anotar('inicio_repetido', $$select api.guardar_inicio((select id from org),
  '[{"codigo": "recepcion.hoy"}, {"codigo": "recepcion.hoy"}]')$$);
select pruebas.como('10000000-0000-4000-8000-000000000002');
select pruebas.anotar('inicio_ajeno', $$select count(*) from api.mi_inicio$$);
reset role;

select is((select valor from r where clave = 'inicio_orden'), 'recepcion.hoy:true,compras.pendientes:false', 'el Inicio guarda orden y visibilidad');
select matches((select valor from r where clave = 'inicio_repetido'), '^ERROR: PRECONDICION', 'tarjetas repetidas rechazadas');
select is((select valor from r where clave = 'inicio_ajeno'), '0', 'cada persona ve solo su Inicio');

-- Módulo deshabilitado ----------------------------------------------------------
delete from nucleo.modulos_habilitados where organizacion_id = (select id from org) and modulo_codigo = 'compras';
select pruebas.como('10000000-0000-4000-8000-000000000001');
select pruebas.anotar('rubro_sin_compras', $$select api.guardar_rubro((select id from org), gen_random_uuid(), 'Bebidas')$$);
select pruebas.anotar('recepcion_sin_compras', $$select api.abrir_recepcion((select id from org), gen_random_uuid(), gen_random_uuid(), 'R-1')$$);
select pruebas.anotar('permisos_modulos', $$select count(*) from api.mis_permisos((select id from org)) where permiso like 'compras.%' or permiso like 'recepcion.%'$$);
select pruebas.anotar('modulos_visibles', $$select string_agg(codigo, ',' order by codigo) from api.modulos_habilitados where organizacion_id = (select id from org)$$);
select pruebas.anotar('cadena', $$select api.verificar_cadena_eventos((select id from org)) ->> 'ok'$$);
reset role;

select matches((select valor from r where clave = 'rubro_sin_compras'), '^ERROR: MODULO_DESHABILITADO', 'Compras deshabilitado bloquea sus RPC');
select matches((select valor from r where clave = 'recepcion_sin_compras'), '^ERROR: MODULO_DESHABILITADO', 'Recepción requiere Compras');
select is((select valor from r where clave = 'permisos_modulos'), '0', 'mis_permisos omite los módulos deshabilitados');
select is((select valor from r where clave = 'modulos_visibles'), 'colab', 'solo queda Salas habilitado (Recepción depende de Compras)');
select is((select valor from r where clave = 'cadena'), 'true', 'la cadena de eventos verifica');

select throws_ok(
  $$update nucleo.eventos set accion = 'x' where organizacion_id = (select id from org)$$,
  '42501', null, 'eventos es append-only'
);

select * from finish();
