-- Eskemia · Flujo completo Compras → Recepción (pgTAP). Portado de
-- supabase/tests/recepcion_oc.sql (legado).
--
-- Qué verifica (criterio de salida del MVP): pedido a 3 proveedores, una orden en
-- aprobación por regla de rubro y dos aprobadas solas; el operario ve solo lo aprobado y
-- sin precios; recibe una completa escaneando cajas y otra parcial; saldos y estados se
-- actualizan; rechazar una recepción devuelve el saldo; todo queda en eventos.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- Compra: la cuenta "persona". Recibe: el operario del escenario (sede principal).

select pruebas.escenario();
create temp table ids (clave text primary key, id uuid);
grant select, insert on ids to authenticated;
select * from no_plan();

-- Lo que el kiosco sube a Storage al abrir: acá se registra con un trigger, sin archivos.
create function pg_temp.foto_al_abrir()
returns trigger language plpgsql security definer as $$
begin
  insert into recepcion.adjuntos (organizacion_id, sede_id, recepcion_id, tipo, storage_path, client_uuid, usuario_id)
  select new.organizacion_id, new.sede_id, new.id, t.tipo::recepcion.tipo_adjunto, 'test/' || gen_random_uuid(), gen_random_uuid(), new.usuario_id
  from (values ('REMITO'), ('FIRMA_RECEPTOR'), ('FIRMA_TRANSPORTISTA')) as t (tipo);
  return null;
end;
$$;
create trigger foto_al_abrir after insert on recepcion.recepciones
  for each row execute function pg_temp.foto_al_abrir();

do $$
declare
  o uuid := pruebas.id('org');
  v_comida uuid := gen_random_uuid();
  v_cat uuid := gen_random_uuid();
  v_limpieza uuid := gen_random_uuid();
  v_cat2 uuid := gen_random_uuid();
  v_pre uuid;
begin
  insert into compras.rubros (id, organizacion_id, nombre) values (v_comida, o, 'Comida test'), (v_limpieza, o, 'Limpieza test');
  insert into compras.categorias (id, organizacion_id, rubro_id, nombre) values (v_cat, o, v_comida, 'Carnes test'), (v_cat2, o, v_limpieza, 'Hogar test');
  insert into compras.productos (id, organizacion_id, categoria_id, nombre, tipo_medida) values
    ('e0000000-0000-4000-e000-0000000000b1', o, v_cat, 'Carne test', 'UNIDAD'),
    ('e0000000-0000-4000-e000-0000000000b2', o, v_cat2, 'Lavandina test', 'UNIDAD'),
    ('e0000000-0000-4000-e000-0000000000b3', o, v_cat2, 'Detergente test', 'UNIDAD'),
    ('e0000000-0000-4000-e000-0000000000b4', o, v_cat2, 'No pedido test', 'UNIDAD');
  insert into compras.proveedores (id, organizacion_id, nombre, cuit) values
    ('e0000000-0000-4000-e000-0000000000d1', o, 'Prov Carne test', '30999999991'),
    ('e0000000-0000-4000-e000-0000000000d2', o, 'Prov Lavandina test', '30999999992'),
    ('e0000000-0000-4000-e000-0000000000d3', o, 'Prov Detergente test', '30999999993');
  -- Caja x 12: escanear una caja suma 12 unidades contra la orden.
  insert into compras.presentaciones (id, organizacion_id, producto_id, nombre, factor) values
    ('e0000000-0000-4000-e000-0000000000e2', o, 'e0000000-0000-4000-e000-0000000000b2', 'Caja x 12', 12);
  select id into v_pre from compras.presentaciones where producto_id = 'e0000000-0000-4000-e000-0000000000b1';
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('e0000000-0000-4000-e000-0000000000f1', o, 'e0000000-0000-4000-e000-0000000000b1', 'e0000000-0000-4000-e000-0000000000d1', v_pre, 1000),
    ('e0000000-0000-4000-e000-0000000000f2', o, 'e0000000-0000-4000-e000-0000000000b2', 'e0000000-0000-4000-e000-0000000000d2', 'e0000000-0000-4000-e000-0000000000e2', 500);
  select id into v_pre from compras.presentaciones where producto_id = 'e0000000-0000-4000-e000-0000000000b3' and factor = 1;
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('e0000000-0000-4000-e000-0000000000f3', o, 'e0000000-0000-4000-e000-0000000000b3', 'e0000000-0000-4000-e000-0000000000d3', v_pre, 10);
  insert into compras.reglas_aprobacion (organizacion_id, alcance, alcance_id, modo, nivel_requerido)
  values (o, 'RUBRO', v_comida, 'SIEMPRE', 1);
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Comprador', pruebas.id('sede'));
end;
$$;

-- 1. El comprador pide a 3 proveedores.
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare r jsonb;
begin
  r := api.confirmar_pedido(gen_random_uuid(), pruebas.id('sede'), jsonb_build_array(
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 5),
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f2', 'cantidad', 2),
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f3', 'cantidad', 10)));
  perform pruebas.no('1: tres proveedores dan tres órdenes', jsonb_array_length(r -> 'ordenes') <> 3);
  perform pruebas.no('2: una en aprobación y dos aprobadas',
    (select count(*) from api.ordenes_compra where estado = 'PENDIENTE_APROBACION') <> 1
    or (select count(*) from api.ordenes_compra where estado = 'APROBADA') <> 2);
end;
$$;
reset role;

-- 2. El operario ve solo lo aprobado, sin precios.
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  s uuid := pruebas.id('sede');
  f record;
begin
  perform pruebas.no('3: el operario ve 2 pendientes', (select count(*) from api.pendientes_recepcion(s)) <> 2);
  perform pruebas.no('4: no ve la orden en aprobación', exists (select 1 from api.pendientes_recepcion(s) p where p.proveedor = 'Prov Carne test'));
  select * into f from api.pendientes_recepcion(s) p where p.proveedor = 'Prov Lavandina test';
  perform pruebas.no('5: no ve precios', f.total_estimado is not null or (f.items -> 0) ? 'precio_unitario' or (f.items -> 0) ? 'subtotal');
  perform pruebas.no('6: no enviada, no atrasada y recibible', not f.no_enviada or f.atrasada or not f.se_puede_recibir);
  perform pruebas.no('7: 2 cajas x 12 se esperan como 24 unidades',
    (f.items -> 0 ->> 'cant_pedida')::numeric <> 24 or (f.items -> 0 ->> 'saldo')::numeric <> 24);
  perform pruebas.no('8: no lee las órdenes con precios', exists (select 1 from api.ordenes_compra));
end;
$$;
reset role;

-- 3. Una vez aprobada por el encargado, aparece.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Encargado de compras', pruebas.id('sede'));
select pruebas.como('e0000000-0000-4000-8000-000000000003');
select api.aprobar_oc((select b.id from api.bandeja_aprobacion(pruebas.id('org')) b where b.proveedor = 'Prov Carne test'));
reset role;

-- 4. Recepción completa escaneando cajas: coincide todo, sin diferencias.
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  o uuid := pruebas.id('org');
  s uuid := pruebas.id('sede');
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
  prod constant uuid := 'e0000000-0000-4000-e000-0000000000b2';
begin
  perform pruebas.no('9: la orden aprobada aparece como pendiente', (select count(*) from api.pendientes_recepcion(s)) <> 3);
  select p.id into v_oc from api.pendientes_recepcion(s) p where p.proveedor = 'Prov Lavandina test';
  insert into ids values ('oc_completa', v_oc), ('rec_completa', v_rec);

  perform pruebas.falla('10: no abre una orden con otro proveedor', 'PRECONDICION',
    format('select api.abrir_recepcion(%L, gen_random_uuid(), %L, %L, %L, null, null, %L)', o, 'e0000000-0000-4000-e000-0000000000d3', 'R-X', s, v_oc));
  perform api.abrir_recepcion(o, v_rec, 'e0000000-0000-4000-e000-0000000000d2', 'R-1', s, null, null, v_oc);
  perform api.abrir_recepcion(o, v_rec, 'e0000000-0000-4000-e000-0000000000d2', 'R-1', s, null, null, v_oc);
  perform pruebas.no('11: precarga lo pedido una sola vez',
    (select count(*) from api.recepcion_items i where i.recepcion_id = v_rec) <> 1
    or (select i.cant_pedida from api.recepcion_items i where i.recepcion_id = v_rec) <> 24);
  perform pruebas.no('12: guarda el número de orden', (select r.oc_numero from api.recepciones r where r.id = v_rec) is null);

  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 12, 'CAJA');
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 12, 'CAJA');
  perform api.iniciar_control(v_rec);
  perform api.fijar_control_item(v_rec, prod, 24);
  perform pruebas.no('13: una recepción exacta cierra OK', api.cerrar_recepcion(v_rec) <> 'CERRADA_OK');
  perform pruebas.no('14: la orden completa deja de estar pendiente', exists (select 1 from api.pendientes_recepcion(s) p where p.id = v_oc));
end;
$$;

-- 5. Recepción parcial con diferencias: se detectan sin comparar a mano.
do $$
declare
  o uuid := pruebas.id('org');
  s uuid := pruebas.id('sede');
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
  v_seg uuid := gen_random_uuid();
  prod constant uuid := 'e0000000-0000-4000-e000-0000000000b3';
  no_pedido constant uuid := 'e0000000-0000-4000-e000-0000000000b4';
  c jsonb;
  f record;
begin
  select p.id into v_oc from api.pendientes_recepcion(s) p where p.proveedor = 'Prov Detergente test';
  insert into ids values ('oc_parcial', v_oc), ('rec_parcial', v_rec);
  perform api.abrir_recepcion(o, v_rec, 'e0000000-0000-4000-e000-0000000000d3', 'R-2', s, null, null, v_oc);
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 6, 'X');
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', no_pedido, 3, 'Y');
  perform api.iniciar_control(v_rec);

  perform api.fijar_control_item(v_rec, prod, 6);
  perform api.fijar_control_item(v_rec, no_pedido, 3);
  c := api.checklist_recepcion(v_rec);
  perform pruebas.no('15: detecta lo pedido contra lo recibido aunque el remito coincida', (c ->> 'motivos_diferencias')::boolean);
  perform api.fijar_control_item(v_rec, prod, 6, 'FALTANTE', 'Vino menos de lo pedido');
  c := api.checklist_recepcion(v_rec);
  perform pruebas.no('16: detecta el producto no pedido', (c ->> 'motivos_diferencias')::boolean);
  perform api.fijar_control_item(v_rec, no_pedido, 3, 'NO_PEDIDO', 'Enviaron sin pedirlo');
  c := api.checklist_recepcion(v_rec);
  perform pruebas.no('17: con motivos queda completo', not (c ->> 'motivos_diferencias')::boolean);

  perform pruebas.no('18: cierra con diferencias', api.cerrar_recepcion(v_rec) <> 'CERRADA_CON_DIFERENCIAS');
  select * into f from api.pendientes_recepcion(s) p where p.id = v_oc;
  perform pruebas.no('19: queda recibida en parte con saldo 4', f.id is null or f.estado <> 'RECIBIDA_PARCIAL' or (f.items -> 0 ->> 'saldo')::numeric <> 4);

  perform api.abrir_recepcion(o, v_seg, 'e0000000-0000-4000-e000-0000000000d3', 'R-3', s, null, null, v_oc);
  perform pruebas.no('20: la segunda entrega precarga solo el saldo',
    (select i.cant_pedida from api.recepcion_items i where i.recepcion_id = v_seg) <> 4);
  perform api.registrar_lectura(gen_random_uuid(), v_seg, 'ESCANEO', prod, 4, 'X');
  perform api.iniciar_control(v_seg);
  perform api.fijar_control_item(v_seg, prod, 4);
  perform pruebas.no('21: la segunda entrega cubre el saldo', api.cerrar_recepcion(v_seg) <> 'CERRADA_OK');
  perform pruebas.no('22: con el saldo cubierto deja de estar pendiente', exists (select 1 from api.pendientes_recepcion(s) p where p.id = v_oc));
end;
$$;
reset role;

-- 6. Una recepción rechazada deja de contar: la orden vuelve a pendiente.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Supervisor de recepción', pruebas.id('sede'));
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  s uuid := pruebas.id('sede');
  v_oc uuid := (select id from ids where clave = 'oc_completa');
  v_parcial uuid := (select id from ids where clave = 'rec_parcial');
  f record;
begin
  perform api.rechazar_recepcion((select id from ids where clave = 'rec_completa'), 'Mal contado');
  select * into f from api.pendientes_recepcion(s) p where p.id = v_oc;
  perform pruebas.no('23: rechazar devuelve el saldo', f.id is null or f.estado <> 'APROBADA' or (f.items -> 0 ->> 'saldo')::numeric <> 24);
  perform pruebas.no('24: el semáforo de la bandeja ve lo pedido',
    (select b.items_con_diferencia from api.recepciones_bandeja b where b.id = v_parcial) <> 2
    or (select b.semaforo from api.recepciones_bandeja b where b.id = v_parcial) <> 'CON_DIFERENCIAS'
    or (select b.oc_numero from api.recepciones_bandeja b where b.id = v_parcial) is null);
  perform pruebas.no('25: no quedan órdenes en aprobación', exists (select 1 from api.pendientes_recepcion(s) p where not p.se_puede_recibir));
end;
$$;
reset role;

-- 7. Una orden en aprobación no se recibe; sin orden todo sigue igual que antes.
update compras.ordenes_compra set estado = 'PENDIENTE_APROBACION' where id = (select id from ids where clave = 'oc_completa');
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  o uuid := pruebas.id('org');
  s uuid := pruebas.id('sede');
  f record;
  v_sin uuid := gen_random_uuid();
begin
  select * into f from api.pendientes_recepcion(s) p where p.id = (select id from ids where clave = 'oc_completa');
  perform pruebas.no('26: se ve, pero no se puede recibir', f.id is null or f.se_puede_recibir);
  perform pruebas.falla('27: no recibe una orden en aprobación', 'PRECONDICION',
    format('select api.abrir_recepcion(%L, gen_random_uuid(), %L, %L, %L, null, null, %L)', o, f.proveedor_id, 'R-4', s, f.id));
  perform api.abrir_recepcion(o, v_sin, f.proveedor_id, 'R-5', s);
  perform pruebas.no('28: sin orden no se precarga nada', exists (select 1 from api.recepcion_items i where i.recepcion_id = v_sin)
    or (select r.oc_id from api.recepciones r where r.id = v_sin) is not null);
end;
$$;
reset role;

-- 8. Sin permiso de pendientes no hay lista, y la cadena de eventos sigue entera.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000002', null);
select pruebas.como('e0000000-0000-4000-8000-000000000002');
select pruebas.falla('29: sin permiso no ve pendientes', 'SIN_PERMISO',
  format('select count(*) from api.pendientes_recepcion(%L)', pruebas.id('sede')));
reset role;

select pruebas.como('e0000000-0000-4000-8000-000000000001');
select pruebas.no('30: la cadena de eventos verifica', not (api.verificar_cadena_eventos(pruebas.id('org')) ->> 'ok')::boolean);
reset role;
select pruebas.no('31: quedan los eventos del estado de la orden',
  not exists (select 1 from nucleo.eventos where entidad = 'orden_compra' and accion = 'estado:RECIBIDA_PARCIAL')
  or not exists (select 1 from nucleo.eventos where entidad = 'orden_compra' and accion = 'estado:RECIBIDA'));

select ok(ok, nombre) from chequeos order by n;
select * from finish();
