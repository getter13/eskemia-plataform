-- Eskemia · Tests de la bandeja de aprobación (pgTAP). Portado de
-- supabase/tests/bandeja.sql (legado).
--
-- Qué verifica: quién ve la bandeja según su nivel, aprobar y rechazar (idempotente, con
-- motivo), que una rechazada no se envía, y que sin autoaprobación nadie decide sobre
-- lo propio.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- Comprador: el operario del escenario. Aprobador: la cuenta "persona", con rol variable.

select pruebas.escenario();
select * from no_plan();

do $$
declare
  o uuid := pruebas.id('org');
  v_rubro uuid := gen_random_uuid();
  v_cat uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_prov uuid := gen_random_uuid();
begin
  insert into compras.rubros (id, organizacion_id, nombre) values (v_rubro, o, 'Comida test');
  insert into compras.categorias (id, organizacion_id, rubro_id, nombre) values (v_cat, o, v_rubro, 'Lácteos test');
  insert into compras.productos (id, organizacion_id, categoria_id, nombre, tipo_medida) values
    (v_a, o, v_cat, 'Leche test', 'UNIDAD'), (v_b, o, null, 'Lavandina test', 'UNIDAD');
  insert into compras.proveedores (id, organizacion_id, nombre, cuit) values (v_prov, o, 'Prov test', '30999999991');
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select 'e0000000-0000-4000-e000-0000000000f1', o, v_a, v_prov, id, 100 from compras.presentaciones where producto_id = v_a;
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select 'e0000000-0000-4000-e000-0000000000f2', o, v_b, v_prov, id, 50 from compras.presentaciones where producto_id = v_b;
  -- Nivel 2 para Comida.
  insert into compras.reglas_aprobacion (organizacion_id, alcance, alcance_id, modo, nivel_requerido)
  values (o, 'RUBRO', v_rubro, 'SIEMPRE', 2);
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000002', 'Comprador');
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Encargado de compras');
end;
$$;

-- El comprador genera tres órdenes pendientes de nivel 2.
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare i int;
begin
  for i in 1 .. 3 loop
    perform api.confirmar_pedido(gen_random_uuid(), pruebas.id('sede'), jsonb_build_array(
      jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', i),
      jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f2', 'cantidad', 1)));
  end loop;
  perform pruebas.falla('1: el comprador no abre la bandeja', 'SIN_PERMISO',
    format('select count(*) from api.bandeja_aprobacion(%L)', pruebas.id('org')));
  perform pruebas.falla('2: el comprador no aprueba', 'SIN_PERMISO',
    format('select api.aprobar_oc(%L)', (select o.id from api.ordenes_compra o limit 1)));
end;
$$;
reset role;

-- Encargado (nivel 1): no alcanza para nivel 2.
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
begin
  perform pruebas.no('3: el nivel 1 no ve órdenes de nivel 2', exists (select 1 from api.bandeja_aprobacion(pruebas.id('org'))));
  perform pruebas.falla('4: el nivel 1 no aprueba una de nivel 2', 'SIN_PERMISO',
    format('select api.aprobar_oc(%L)', (select o.id from api.ordenes_compra o limit 1)));
end;
$$;
reset role;

-- Gerente (nivel 2): ve, aprueba y rechaza.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Gerente');
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  o uuid := pruebas.id('org');
  f record;
  v_oc uuid;
  v_otra uuid;
begin
  perform pruebas.no('5: el gerente ve las 3 órdenes', (select count(*) from api.bandeja_aprobacion(o)) <> 3);
  select * into f from api.bandeja_aprobacion(o) limit 1;
  v_oc := f.id;
  perform pruebas.no('6: la bandeja trae emisor, proveedor y nivel', f.emisor is null or f.proveedor <> 'Prov test' or f.nivel_requerido <> 2);
  perform pruebas.no('7: el ítem que disparó va primero',
    not (f.items -> 0 ->> 'disparo_aprobacion')::boolean or (f.items -> 1 ->> 'disparo_aprobacion')::boolean);
  perform pruebas.no('8: trae las reglas aplicadas', (f.reglas_aplicadas -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO');

  perform pruebas.no('9: aprueba', api.aprobar_oc(v_oc) <> 'APROBADA');
  perform pruebas.no('10: el reintento responde igual', api.aprobar_oc(v_oc) <> 'APROBADA');
  perform pruebas.no('11: guarda quién aprobó',
    (select o2.tipo_aprobacion <> 'MANUAL' or o2.aprobada_por is null or o2.aprobada_en is null from api.ordenes_compra o2 where o2.id = v_oc));
  perform pruebas.no('12: la aprobada sale de la bandeja', (select count(*) from api.bandeja_aprobacion(o)) <> 2);
  perform pruebas.falla('13: no rechaza una ya aprobada', 'PRECONDICION', format('select api.rechazar_oc(%L, %L)', v_oc, 'Tarde'));

  select b.id into v_otra from api.bandeja_aprobacion(o) b limit 1;
  perform pruebas.falla('14: no rechaza sin motivo', 'PRECONDICION', format('select api.rechazar_oc(%L, %L)', v_otra, '   '));
  perform pruebas.no('15: rechaza', api.rechazar_oc(v_otra, 'Hay stock') <> 'RECHAZADA');
  perform pruebas.no('16: guarda el motivo', (select o2.motivo_rechazo <> 'Hay stock' from api.ordenes_compra o2 where o2.id = v_otra));
  perform pruebas.falla('17: no envía una rechazada', 'PRECONDICION', format('select api.marcar_oc_enviada(%L, null)', v_otra));
end;
$$;
reset role;

select ok(exists (select 1 from nucleo.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:APROBADA')
  and exists (select 1 from nucleo.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:RECHAZADA'),
  '18: quedan los eventos de aprobar y rechazar');

-- Con la autoaprobación apagada, nadie decide sobre lo propio.
insert into compras.configuracion (organizacion_id, permitir_autoaprobacion) values (pruebas.id('org'), false)
on conflict (organizacion_id) do update set permitir_autoaprobacion = false;
update compras.ordenes_compra set usuario_id = 'e0000000-0000-4000-8000-000000000003' where estado = 'PENDIENTE_APROBACION';
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
begin
  perform pruebas.no('19: no muestra una orden propia', exists (select 1 from api.bandeja_aprobacion(pruebas.id('org'))));
  perform pruebas.falla('20: no aprueba una orden propia', 'SIN_PERMISO',
    format('select api.aprobar_oc(%L)', (select o.id from api.ordenes_compra o where o.estado = 'PENDIENTE_APROBACION' limit 1)));
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
