-- Eskemia · Tests de confirmar_pedido y el envío de órdenes (pgTAP). Portado de
-- supabase/tests/pedidos.sql (legado).
--
-- Qué verifica: un pedido se parte en una orden por proveedor, cada una evaluada por
-- separado; numeración, fecha estimada y snapshot de precios y reglas; idempotencia por
-- request_uuid; validaciones sin rastro; envío solo de lo aprobado; visibilidad de precios.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- Emite la cuenta "persona" del escenario con rol Comprador.

select pruebas.escenario();
select * from no_plan();

do $$
declare
  o uuid := pruebas.id('org');
  v_rubro uuid := gen_random_uuid();
  v_cat uuid := gen_random_uuid();
  v_a uuid := 'e0000000-0000-4000-e000-0000000000b1';
  v_b uuid := 'e0000000-0000-4000-e000-0000000000b2';
  v_prov1 uuid := 'e0000000-0000-4000-e000-0000000000d1';
  v_prov2 uuid := 'e0000000-0000-4000-e000-0000000000d2';
  v_pb uuid;
begin
  insert into compras.rubros (id, organizacion_id, nombre) values (v_rubro, o, 'Comida test');
  insert into compras.categorias (id, organizacion_id, rubro_id, nombre) values (v_cat, o, v_rubro, 'Lácteos test');
  insert into compras.productos (id, organizacion_id, categoria_id, nombre, sku, tipo_medida) values
    (v_a, o, v_cat, 'Leche test', 'SKU-T1', 'UNIDAD'), (v_b, o, null, 'Lavandina test', 'SKU-T2', 'UNIDAD');
  insert into compras.proveedores (id, organizacion_id, nombre, cuit, plazo_entrega_dias) values
    (v_prov1, o, 'Prov A test', '30999999991', 3), (v_prov2, o, 'Prov B test', '30999999992', null);
  insert into compras.presentaciones (id, organizacion_id, producto_id, nombre, factor)
  values ('e0000000-0000-4000-e000-0000000000e1', o, v_a, 'Caja x 12', 12);
  select id into v_pb from compras.presentaciones where producto_id = v_b;
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('e0000000-0000-4000-e000-0000000000f1', o, v_a, v_prov1, 'e0000000-0000-4000-e000-0000000000e1', 1200),
    ('e0000000-0000-4000-e000-0000000000f2', o, v_a, v_prov2, 'e0000000-0000-4000-e000-0000000000e1', 1100),
    ('e0000000-0000-4000-e000-0000000000f3', o, v_b, v_prov2, v_pb, 500);
  -- El rubro del producto A pasa por aprobación; el producto B, no.
  insert into compras.reglas_aprobacion (organizacion_id, alcance, alcance_id, modo, nivel_requerido)
  values (o, 'RUBRO', v_rubro, 'SIEMPRE', 1);
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Comprador');
end;
$$;

select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  s uuid := pruebas.id('sede');
  v_req constant uuid := 'e0000000-0000-4000-e000-000000000101';
  r jsonb;
  r2 jsonb;
  oc record;
  it record;
  v_anio text := extract(year from now() at time zone 'America/Argentina/Buenos_Aires')::text;
begin
  r := api.confirmar_pedido(v_req, s, jsonb_build_array(
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 2),
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f3', 'cantidad', 3)));
  perform pruebas.no('1: dos proveedores dan dos órdenes', jsonb_array_length(r -> 'ordenes') <> 2 or (r ->> 'duplicada')::boolean);

  select o.* into oc from api.ordenes_compra o join api.proveedores p on p.id = o.proveedor_id where p.nombre = 'Prov A test';
  perform pruebas.no('2: la orden del rubro con regla queda en aprobación', oc.estado <> 'PENDIENTE_APROBACION'
    or oc.tipo_aprobacion is not null or oc.aprobada_en is not null or oc.total_estimado <> 2400
    or oc.nivel_requerido <> 1 or not oc.requiere_aprobacion);
  perform pruebas.no('3: número OC-<sede>-<año>-NNNNNN', oc.numero !~ ('^OC-[A-Z0-9]+-' || v_anio || '-[0-9]{6}$'));
  perform pruebas.no('4: fecha estimada por plazo del proveedor',
    oc.fecha_entrega_estimada <> (now() at time zone 'America/Argentina/Buenos_Aires')::date + 3);
  perform pruebas.no('5: snapshot de reglas', jsonb_array_length(oc.reglas_aplicadas -> 'reglas_aplicadas') <> 1);

  select * into it from api.oc_items i where i.producto_nombre = 'Leche test';
  perform pruebas.no('6: snapshot del ítem en unidades de stock', it.cantidad <> 2 or it.factor <> 12 or it.cant_pedida <> 24
    or it.precio_unitario <> 1200 or it.subtotal <> 2400 or it.presentacion_nombre <> 'Caja x 12'
    or it.sku <> 'SKU-T1' or not it.disparo_aprobacion);

  select o.* into oc from api.ordenes_compra o join api.proveedores p on p.id = o.proveedor_id where p.nombre = 'Prov B test';
  perform pruebas.no('7: la otra orden se aprueba sola', oc.estado <> 'APROBADA' or oc.tipo_aprobacion <> 'AUTOMATICA' or oc.aprobada_en is null);
  perform pruebas.no('8: no marca un ítem que no disparó',
    (select i.disparo_aprobacion from api.oc_items i where i.producto_nombre = 'Lavandina test'));

  r2 := api.confirmar_pedido(v_req, s, jsonb_build_array(
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 99)));
  perform pruebas.no('9: el reintento devuelve lo mismo', not (r2 ->> 'duplicada')::boolean or r2 -> 'ordenes' <> r -> 'ordenes');
  perform pruebas.no('10: el reintento no duplica órdenes', (select count(*) from api.ordenes_compra) <> 2);

  perform api.confirmar_pedido(gen_random_uuid(), s, jsonb_build_array(
    jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f2', 'cantidad', 1)));
  perform pruebas.no('11: la numeración no se repite', (select count(distinct o.numero) from api.ordenes_compra o) <> 3);

  perform pruebas.no('12: se envía lo aprobado', api.marcar_oc_enviada(oc.id, 'WHATSAPP') <> 'ENVIADA');
  perform pruebas.no('13: el reintento responde igual', api.marcar_oc_enviada(oc.id, 'WHATSAPP') <> 'ENVIADA');
  perform pruebas.no('14: guarda el envío',
    (select o.enviada_en is null or o.canal_envio <> 'WHATSAPP' from api.ordenes_compra o where o.id = oc.id));
  perform pruebas.falla('15: no envía una orden sin aprobar', 'PRECONDICION', format('select api.marcar_oc_enviada(%L, %L)',
    (select o.id from api.ordenes_compra o where o.estado = 'PENDIENTE_APROBACION' limit 1), 'WHATSAPP'));

  perform pruebas.falla('16: pedido vacío rechazado', 'PRECONDICION',
    format('select api.confirmar_pedido(gen_random_uuid(), %L, %L)', s, '[]'));
  perform pruebas.falla('17: cantidad cero rechazada', 'PRECONDICION',
    format('select api.confirmar_pedido(gen_random_uuid(), %L, %L)', s,
      jsonb_build_array(jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 0))));
  perform pruebas.falla('18: oferta inexistente rechazada', 'PRECONDICION',
    format('select api.confirmar_pedido(gen_random_uuid(), %L, %L)', s,
      jsonb_build_array(jsonb_build_object('oferta_id', gen_random_uuid(), 'cantidad', 1))));
  perform pruebas.no('19: un pedido con error no deja rastro', (select count(*) from api.pedidos_compra) <> 2);
end;
$$;
reset role;

-- El precio cambia después: la orden conserva el snapshot.
update compras.producto_proveedor set precio_actual = 9999, activo = false where id = 'e0000000-0000-4000-e000-0000000000f1';
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
begin
  perform pruebas.no('20: la orden conserva el precio',
    (select i.precio_unitario from api.oc_items i where i.producto_nombre = 'Leche test' and i.factor = 12 and i.subtotal = 2400) <> 1200);
  perform pruebas.falla('21: oferta inactiva rechazada con el nombre del producto', 'PRECONDICION: %Leche test',
    format('select api.confirmar_pedido(gen_random_uuid(), %L, %L)', pruebas.id('sede'),
      jsonb_build_array(jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 1))));
end;
$$;
reset role;

-- Sin permisos sobre órdenes: no ve órdenes ajenas ni puede confirmar.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Operario de recepción', pruebas.id('sede'));
update compras.ordenes_compra set usuario_id = 'e0000000-0000-4000-8000-000000000001';
update compras.pedidos_compra set usuario_id = 'e0000000-0000-4000-8000-000000000001';
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
begin
  perform pruebas.no('23: el operario no ve órdenes ajenas con precios', exists (select 1 from api.ordenes_compra)
    or exists (select 1 from api.oc_items) or exists (select 1 from api.pedidos_compra) or exists (select 1 from api.pedido_items));
  perform pruebas.falla('24: el operario no confirma pedidos', 'SIN_PERMISO',
    format('select api.confirmar_pedido(gen_random_uuid(), %L, %L)', pruebas.id('sede'),
      jsonb_build_array(jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f2', 'cantidad', 1))));
  perform pruebas.falla('25: orden inexistente', 'NO_ENCONTRADO', 'select api.marcar_oc_enviada(null, null)');
end;
$$;
reset role;

-- Admin: ve todas, y la cadena de eventos sigue entera.
select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
begin
  perform pruebas.no('26: el admin ve todas las órdenes', (select count(*) from api.ordenes_compra) <> 3);
  perform pruebas.no('27: la cadena de eventos verifica', not (api.verificar_cadena_eventos(pruebas.id('org')) ->> 'ok')::boolean);
  perform pruebas.no('28: quedan los eventos del flujo',
    not exists (select 1 from api.eventos e where e.entidad = 'orden_compra' and e.accion = 'creada')
    or not exists (select 1 from api.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:ENVIADA')
    or not exists (select 1 from api.eventos e where e.entidad = 'pedido' and e.accion = 'confirmado'));
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
