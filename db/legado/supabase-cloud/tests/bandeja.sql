-- Eskemia · Tests de la bandeja de aprobación. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/bandeja.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.
--
-- Comprador: el operario de prueba. Aprobador: el admin de prueba, con un rol que se cambia acá.

begin;

-- Las órdenes demo no cuentan: esto también se deshace con el ROLLBACK.
update public.recepciones set oc_id = null where oc_id is not null;
delete from public.oc_items;
delete from public.ordenes_compra;
delete from public.pedido_items;
delete from public.pedidos_compra;

create function pg_temp.rol_de(p_user uuid, p_rol text)
returns void language plpgsql as $$
begin
  delete from public.usuario_roles where user_id = p_user;
  insert into public.usuario_roles (tenant_id, user_id, rol_id)
  select r.tenant_id, p_user, r.id from public.roles r
  where r.tenant_id = '00000000-0000-4000-8000-000000000001' and r.nombre = p_rol;
end;
$$;

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  v_rubro uuid := gen_random_uuid();
  v_cat uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_prov uuid := gen_random_uuid();
begin
  insert into public.rubros (id, tenant_id, nombre) values (v_rubro, t, 'Comida test');
  insert into public.categorias (id, tenant_id, rubro_id, nombre) values (v_cat, t, v_rubro, 'Lácteos test');
  insert into public.productos (id, tenant_id, categoria_id, nombre, tipo_medida) values
    (v_a, t, v_cat, 'Leche test', 'UNIDAD'), (v_b, t, null, 'Lavandina test', 'UNIDAD');
  insert into public.proveedores (id, tenant_id, nombre, cuit) values (v_prov, t, 'Prov test', '30999999991');
  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select '00000000-0000-4000-e000-0000000000f1', t, v_a, v_prov, id, 100 from public.presentaciones where producto_id = v_a;
  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select '00000000-0000-4000-e000-0000000000f2', t, v_b, v_prov, id, 50 from public.presentaciones where producto_id = v_b;
  -- Nivel 2 para Comida.
  insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, nivel_requerido)
  values (t, 'RUBRO', v_rubro, 'SIEMPRE', 2);
  perform pg_temp.rol_de('00000000-0000-4000-c000-000000000001', 'Comprador');
  perform pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Encargado de compras');
end;
$$;

-- El comprador genera tres órdenes pendientes de nivel 2.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$
declare i int;
begin
  for i in 1 .. 3 loop
    perform public.confirmar_pedido(gen_random_uuid(), '00000000-0000-4000-8000-000000000002', jsonb_build_array(
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', i),
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f2', 'cantidad', 1)
    ));
  end loop;
  begin
    perform * from public.bandeja_aprobacion();
    raise exception 'TEST 1: el comprador abrió la bandeja' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.aprobar_oc((select o.id from public.ordenes_compra o limit 1));
    raise exception 'TEST 2: el comprador aprobó' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Encargado (nivel 1): no alcanza para nivel 2.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_oc uuid;
begin
  if exists (select 1 from public.bandeja_aprobacion()) then
    raise exception 'TEST 3: el nivel 1 no debería ver órdenes de nivel 2';
  end if;
  select o.id into v_oc from public.ordenes_compra o limit 1;
  begin
    perform public.aprobar_oc(v_oc);
    raise exception 'TEST 4: el nivel 1 aprobó una de nivel 2' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Gerente (nivel 2): ve, aprueba y rechaza.
reset role;
select pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Gerente');
set local role authenticated;
do $$
declare
  f record;
  v_oc uuid;
  v_otra uuid;
begin
  if (select count(*) from public.bandeja_aprobacion()) <> 3 then
    raise exception 'TEST 5: el gerente debería ver 3 órdenes';
  end if;
  select * into f from public.bandeja_aprobacion() limit 1;
  v_oc := f.id;
  if f.emisor is null or f.proveedor <> 'Prov test' or f.nivel_requerido <> 2 then
    raise exception 'TEST 6: %', f;
  end if;
  -- El ítem que disparó la regla va primero.
  if not (f.items -> 0 ->> 'disparo_aprobacion')::boolean or (f.items -> 1 ->> 'disparo_aprobacion')::boolean then
    raise exception 'TEST 7: %', f.items;
  end if;
  if (f.reglas_aplicadas -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO' then
    raise exception 'TEST 8: %', f.reglas_aplicadas;
  end if;

  if public.aprobar_oc(v_oc) <> 'APROBADA' then raise exception 'TEST 9: no aprobó'; end if;
  if public.aprobar_oc(v_oc) <> 'APROBADA' then raise exception 'TEST 10: el reintento debería responder igual'; end if;
  if (select o.tipo_aprobacion <> 'MANUAL' or o.aprobada_por is null or o.aprobada_en is null from public.ordenes_compra o where o.id = v_oc) then
    raise exception 'TEST 11: no guardó quién aprobó';
  end if;
  if (select count(*) from public.bandeja_aprobacion()) <> 2 then
    raise exception 'TEST 12: la aprobada sigue en la bandeja';
  end if;
  begin
    perform public.rechazar_oc(v_oc, 'Tarde');
    raise exception 'TEST 13: rechazó una ya aprobada' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  select b.id into v_otra from public.bandeja_aprobacion() b limit 1;
  begin
    perform public.rechazar_oc(v_otra, '   ');
    raise exception 'TEST 14: rechazó sin motivo' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  if public.rechazar_oc(v_otra, 'Hay stock') <> 'RECHAZADA' then raise exception 'TEST 15: no rechazó'; end if;
  if (select o.motivo_rechazo <> 'Hay stock' from public.ordenes_compra o where o.id = v_otra) then
    raise exception 'TEST 16: no guardó el motivo';
  end if;
  begin
    perform public.marcar_oc_enviada(v_otra);
    raise exception 'TEST 17: envió una rechazada' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
end;
$$;

-- Con la autoaprobación apagada, nadie decide sobre lo propio.
reset role;
do $$
begin
  if not exists (select 1 from public.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:APROBADA')
     or not exists (select 1 from public.eventos e where e.entidad = 'orden_compra' and e.accion = 'estado:RECHAZADA') then
    raise exception 'TEST 18: faltan eventos';
  end if;
end;
$$;
update public.configuracion_empresa set permitir_autoaprobacion = false;
update public.ordenes_compra set usuario_id = '00000000-0000-4000-c000-000000000002' where estado = 'PENDIENTE_APROBACION';
set local role authenticated;
do $$
declare v_oc uuid;
begin
  if exists (select 1 from public.bandeja_aprobacion()) then
    raise exception 'TEST 19: mostró una orden propia';
  end if;
  select o.id into v_oc from public.ordenes_compra o where o.estado = 'PENDIENTE_APROBACION' limit 1;
  begin
    perform public.aprobar_oc(v_oc);
    raise exception 'TEST 20: aprobó una orden propia' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select 'bandeja: todos los tests pasaron' as resultado;
rollback;
