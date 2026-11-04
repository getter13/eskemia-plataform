-- Eskemia · Tests de confirmar_pedido. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/pedidos.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  u constant uuid := '00000000-0000-4000-c000-000000000001';
  v_rubro uuid := '00000000-0000-4000-e000-0000000000a1';
  v_cat uuid := gen_random_uuid();
  v_a uuid := '00000000-0000-4000-e000-0000000000b1';
  v_b uuid := '00000000-0000-4000-e000-0000000000b2';
  v_prov1 uuid := '00000000-0000-4000-e000-0000000000d1';
  v_prov2 uuid := '00000000-0000-4000-e000-0000000000d2';
  v_pa uuid;
  v_pb uuid;
begin
  insert into public.rubros (id, tenant_id, nombre) values (v_rubro, t, 'Comida test');
  insert into public.categorias (id, tenant_id, rubro_id, nombre) values (v_cat, t, v_rubro, 'Lácteos test');
  insert into public.productos (id, tenant_id, categoria_id, nombre, sku, tipo_medida) values
    (v_a, t, v_cat, 'Leche test', 'SKU-T1', 'UNIDAD'),
    (v_b, t, null, 'Lavandina test', 'SKU-T2', 'UNIDAD');
  insert into public.proveedores (id, tenant_id, nombre, cuit, plazo_entrega_dias) values
    (v_prov1, t, 'Prov A test', '30999999991', 3),
    (v_prov2, t, 'Prov B test', '30999999992', null);

  insert into public.presentaciones (id, tenant_id, producto_id, nombre, factor)
  values ('00000000-0000-4000-e000-0000000000e1', t, v_a, 'Caja x 12', 12);
  select id into v_pb from public.presentaciones where producto_id = v_b;

  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('00000000-0000-4000-e000-0000000000f1', t, v_a, v_prov1, '00000000-0000-4000-e000-0000000000e1', 1200),
    ('00000000-0000-4000-e000-0000000000f2', t, v_a, v_prov2, '00000000-0000-4000-e000-0000000000e1', 1100),
    ('00000000-0000-4000-e000-0000000000f3', t, v_b, v_prov2, v_pb, 500);

  -- El rubro del producto A pasa por aprobación; el producto B, no.
  insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, nivel_requerido)
  values (t, 'RUBRO', v_rubro, 'SIEMPRE', 1);

  delete from public.usuario_roles where user_id = u;
  insert into public.usuario_roles (tenant_id, user_id, rol_id)
  select t, u, r.id from public.roles r where r.tenant_id = t and r.nombre = 'Comprador';
end;
$$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  v_req constant uuid := '00000000-0000-4000-e000-000000000101';
  r jsonb;
  r2 jsonb;
  oc record;
  it record;
  v_anio text := extract(year from now() at time zone 'America/Argentina/Buenos_Aires')::text;
begin
  -- Un pedido con dos proveedores da dos órdenes; cada una se evalúa por separado.
  r := public.confirmar_pedido(v_req, s, jsonb_build_array(
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 2),
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f3', 'cantidad', 3)
  ));
  if jsonb_array_length(r -> 'ordenes') <> 2 or (r ->> 'duplicada')::boolean then
    raise exception 'TEST 1: %', r;
  end if;

  select * into oc from public.ordenes_compra o join public.proveedores p on p.id = o.proveedor_id where p.nombre = 'Prov A test';
  if oc.estado <> 'PENDIENTE_APROBACION' or oc.tipo_aprobacion is not null or oc.aprobada_en is not null
     or oc.total_estimado <> 2400 or oc.nivel_requerido <> 1 or not oc.requiere_aprobacion then
    raise exception 'TEST 2: %', oc;
  end if;
  if oc.numero !~ ('^OC-[A-Z0-9]+-' || v_anio || '-[0-9]{6}$') then
    raise exception 'TEST 3: numero %', oc.numero;
  end if;
  if oc.fecha_entrega_estimada <> (now() at time zone 'America/Argentina/Buenos_Aires')::date + 3 then
    raise exception 'TEST 4: fecha %', oc.fecha_entrega_estimada;
  end if;
  if jsonb_array_length(oc.reglas_aplicadas -> 'reglas_aplicadas') <> 1 then
    raise exception 'TEST 5: snapshot de reglas %', oc.reglas_aplicadas;
  end if;

  select * into it from public.oc_items i where i.producto_nombre = 'Leche test';
  if it.cantidad <> 2 or it.factor <> 12 or it.cant_pedida <> 24 or it.precio_unitario <> 1200
     or it.subtotal <> 2400 or it.presentacion_nombre <> 'Caja x 12' or it.sku <> 'SKU-T1'
     or not it.disparo_aprobacion then
    raise exception 'TEST 6: %', it;
  end if;

  select * into oc from public.ordenes_compra o join public.proveedores p on p.id = o.proveedor_id where p.nombre = 'Prov B test';
  if oc.estado <> 'APROBADA' or oc.tipo_aprobacion <> 'AUTOMATICA' or oc.aprobada_en is null then
    raise exception 'TEST 7: %', oc;
  end if;
  if (select i.disparo_aprobacion from public.oc_items i where i.producto_nombre = 'Lavandina test') then
    raise exception 'TEST 8: marcó un ítem que no disparó';
  end if;

  -- Reintento: devuelve lo mismo y no crea nada.
  r2 := public.confirmar_pedido(v_req, s, jsonb_build_array(
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 99)
  ));
  if not (r2 ->> 'duplicada')::boolean or r2 -> 'ordenes' <> r -> 'ordenes' then
    raise exception 'TEST 9: %', r2;
  end if;
  if (select count(*) from public.ordenes_compra) <> 2 then
    raise exception 'TEST 10: el reintento duplicó órdenes';
  end if;

  -- La numeración avanza y no se repite.
  r2 := public.confirmar_pedido(gen_random_uuid(), s, jsonb_build_array(
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f2', 'cantidad', 1)
  ));
  if (select count(distinct o.numero) from public.ordenes_compra o) <> 3 then
    raise exception 'TEST 11: números repetidos';
  end if;

  -- Enviar: solo lo aprobado.
  if public.marcar_oc_enviada(oc.id, 'WHATSAPP') <> 'ENVIADA' then
    raise exception 'TEST 12: no quedó enviada';
  end if;
  if public.marcar_oc_enviada(oc.id, 'WHATSAPP') <> 'ENVIADA' then
    raise exception 'TEST 13: el reintento debería responder igual';
  end if;
  if (select o.enviada_en is null or o.canal_envio <> 'WHATSAPP' from public.ordenes_compra o where o.id = oc.id) then
    raise exception 'TEST 14: no guardó el envío';
  end if;
  begin
    perform public.marcar_oc_enviada((
      select o.id from public.ordenes_compra o where o.estado = 'PENDIENTE_APROBACION' limit 1
    ));
    raise exception 'TEST 15: envió una orden sin aprobar' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  -- Errores que no dejan rastro.
  begin
    perform public.confirmar_pedido(gen_random_uuid(), s, '[]');
    raise exception 'TEST 16: aceptó un pedido vacío' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.confirmar_pedido(gen_random_uuid(), s, jsonb_build_array(
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 0)));
    raise exception 'TEST 17: aceptó cantidad cero' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.confirmar_pedido(gen_random_uuid(), s, jsonb_build_array(
      jsonb_build_object('oferta_id', gen_random_uuid(), 'cantidad', 1)));
    raise exception 'TEST 18: aceptó una oferta inexistente' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  if (select count(*) from public.pedidos_compra) <> 2 then
    raise exception 'TEST 19: un pedido con error dejó rastro';
  end if;
end;
$$;

-- El precio cambia después: la orden conserva el snapshot.
reset role;
update public.producto_proveedor set precio_actual = 9999, activo = false
where id = '00000000-0000-4000-e000-0000000000f1';
set local role authenticated;

do $$
begin
  if (select i.precio_unitario from public.oc_items i where i.producto_nombre = 'Leche test' and i.factor = 12 and i.subtotal = 2400) <> 1200 then
    raise exception 'TEST 20: cambió el snapshot';
  end if;
  begin
    perform public.confirmar_pedido(gen_random_uuid(), '00000000-0000-4000-8000-000000000002', jsonb_build_array(
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 1)));
    raise exception 'TEST 21: aceptó una oferta inactiva' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
    if sqlerrm not like '%Leche test%' then raise exception 'TEST 22: mensaje %', sqlerrm; end if;
  end;
end;
$$;

-- Otro usuario sin permisos sobre órdenes no ve precios ni puede confirmar ni enviar.
reset role;
insert into public.usuario_roles (tenant_id, user_id, rol_id)
select r.tenant_id, '00000000-0000-4000-c000-000000000002', r.id from public.roles r where false;
delete from public.usuario_roles where user_id = '00000000-0000-4000-c000-000000000001';
insert into public.usuario_roles (tenant_id, user_id, rol_id)
select r.tenant_id, '00000000-0000-4000-c000-000000000001', r.id from public.roles r
where r.tenant_id = '00000000-0000-4000-8000-000000000001' and r.nombre = 'Operario de recepción';
update public.ordenes_compra set usuario_id = '00000000-0000-4000-c000-000000000002';
update public.pedidos_compra set usuario_id = '00000000-0000-4000-c000-000000000002';
set local role authenticated;

do $$
begin
  if exists (select 1 from public.ordenes_compra) or exists (select 1 from public.oc_items)
     or exists (select 1 from public.pedidos_compra) or exists (select 1 from public.pedido_items) then
    raise exception 'TEST 23: el operario vio órdenes ajenas con precios';
  end if;
  begin
    perform public.confirmar_pedido(gen_random_uuid(), '00000000-0000-4000-8000-000000000002', jsonb_build_array(
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f2', 'cantidad', 1)));
    raise exception 'TEST 24: el operario confirmó un pedido' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.marcar_oc_enviada((select null::uuid));
    raise exception 'TEST 25: marcó una orden inexistente' using errcode = 'ZZ001';
  exception when no_data_found then null;
  end;
end;
$$;

-- Admin: ve todas, y la cadena de eventos sigue entera.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if (select count(*) from public.ordenes_compra) <> 3 then
    raise exception 'TEST 26: el admin debería ver todas las órdenes';
  end if;
  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST 27: la cadena de eventos se rompió';
  end if;
  if not exists (select 1 from public.eventos e where e.entidad = 'orden_compra' and e.accion = 'creada')
     or not exists (select 1 from public.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:ENVIADA')
     or not exists (select 1 from public.eventos e where e.entidad = 'pedido' and e.accion = 'confirmado') then
    raise exception 'TEST 28: faltan eventos';
  end if;
end;
$$;

reset role;
select 'pedidos: todos los tests pasaron' as resultado;
rollback;
