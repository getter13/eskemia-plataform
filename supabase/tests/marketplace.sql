-- Eskemia · Tests del catálogo del marketplace. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/marketplace.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  u constant uuid := '00000000-0000-4000-c000-000000000001';
  v_rubro uuid := '00000000-0000-4000-e000-0000000000a1';
  v_otro_rubro uuid := '00000000-0000-4000-e000-0000000000a2';
  v_cat uuid := gen_random_uuid();
  v_otra_cat uuid := gen_random_uuid();
  v_multi uuid := '00000000-0000-4000-e000-0000000000b1';
  v_otro uuid := '00000000-0000-4000-e000-0000000000b2';
  v_sin_oferta uuid := '00000000-0000-4000-e000-0000000000b3';
  v_prov_a uuid := gen_random_uuid();
  v_prov_b uuid := gen_random_uuid();
  v_prov_c uuid := gen_random_uuid();
  v_sector uuid := '00000000-0000-4000-e000-0000000000c1';
  v_pre uuid;
begin
  insert into public.rubros (id, tenant_id, nombre) values (v_rubro, t, 'Comida test'), (v_otro_rubro, t, 'Limpieza test');
  insert into public.categorias (id, tenant_id, rubro_id, nombre) values (v_cat, t, v_rubro, 'Lácteos test'), (v_otra_cat, t, v_otro_rubro, 'Lavandinas test');
  insert into public.productos (id, tenant_id, categoria_id, nombre, sku, tipo_medida) values
    (v_multi, t, v_cat, 'Leche test', 'SKU-TEST-1', 'UNIDAD'),
    (v_otro, t, v_otra_cat, 'Lavandina test', 'SKU-TEST-2', 'UNIDAD'),
    (v_sin_oferta, t, v_cat, 'Sin proveedor test', null, 'UNIDAD');
  insert into public.proveedores (id, tenant_id, nombre, cuit, codigo) values
    (v_prov_a, t, 'Prov A test', '30999999991', 'P-TEST-1'),
    (v_prov_b, t, 'Prov B test', '30999999992', null),
    (v_prov_c, t, 'Prov C test', '30999999993', null);

  select id into v_pre from public.presentaciones where producto_id = v_multi;
  insert into public.producto_proveedor (tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual, preferido, activo) values
    (t, v_multi, v_prov_a, v_pre, 200, false, true),
    (t, v_multi, v_prov_b, v_pre, 300, true, true),
    (t, v_multi, v_prov_c, v_pre, 100, false, false);
  select id into v_pre from public.presentaciones where producto_id = v_otro;
  insert into public.producto_proveedor (tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  values (t, v_otro, v_prov_a, v_pre, 50);

  insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido)
  values (t, 'RUBRO', v_rubro, 'POR_MONTO', 1000, 1);

  insert into public.sectores (id, tenant_id, nombre) values (v_sector, t, 'Cocina test');

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
  v_multi constant uuid := '00000000-0000-4000-e000-0000000000b1';
  f record;
begin
  select * into f from public.catalogo_compras(s) c where c.producto_id = v_multi;
  if not found then raise exception 'TEST 1: falta el producto'; end if;
  if f.rubro <> 'Comida test' or f.categoria <> 'Lácteos test' or f.sku <> 'SKU-TEST-1' then
    raise exception 'TEST 2: %', f;
  end if;
  -- La inactiva no aparece; la preferida va primera aunque sea más cara.
  if jsonb_array_length(f.ofertas) <> 2 or (f.ofertas -> 0 ->> 'proveedor') <> 'Prov B test'
     or not (f.ofertas -> 0 ->> 'preferido')::boolean or (f.ofertas -> 1 ->> 'proveedor_codigo') <> 'P-TEST-1' then
    raise exception 'TEST 3: %', f.ofertas;
  end if;
  if f.regla_modo <> 'POR_MONTO' or f.regla_monto_umbral <> 1000 then
    raise exception 'TEST 4: %', f;
  end if;
  if exists (select 1 from public.catalogo_compras(s) c where c.nombre = 'Sin proveedor test') then
    raise exception 'TEST 5: mostró un producto sin proveedor';
  end if;
  if not exists (select 1 from public.catalogo_compras(s) c where c.nombre = 'Lavandina test') then
    raise exception 'TEST 6: falta el otro rubro';
  end if;
end;
$$;

-- Sector restringido a un rubro.
reset role;
update public.usuario_roles set sector_id = '00000000-0000-4000-e000-0000000000c1'
where user_id = '00000000-0000-4000-c000-000000000001';
set local role authenticated;
do $$
begin
  -- Sin rubros asignados, el sector ve todo.
  if not exists (select 1 from public.catalogo_compras('00000000-0000-4000-8000-000000000002') c where c.nombre = 'Lavandina test') then
    raise exception 'TEST 7: un sector sin rubros no debería restringir';
  end if;
end;
$$;
reset role;
insert into public.sector_rubros (tenant_id, sector_id, rubro_id)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-e000-0000000000c1', '00000000-0000-4000-e000-0000000000a1');
set local role authenticated;
do $$
begin
  if exists (select 1 from public.catalogo_compras('00000000-0000-4000-8000-000000000002') c where c.nombre = 'Lavandina test') then
    raise exception 'TEST 8: el sector vio un rubro ajeno';
  end if;
  if not exists (select 1 from public.catalogo_compras('00000000-0000-4000-8000-000000000002') c where c.nombre = 'Leche test') then
    raise exception 'TEST 9: el sector no vio su rubro';
  end if;
  begin
    perform public.fijar_sku_producto('00000000-0000-4000-e000-0000000000b1', 'X');
    raise exception 'TEST 10: el comprador cambió un SKU' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- evaluar_aprobacion sigue resolviendo igual con regla_producto.
do $$
declare r jsonb;
begin
  r := public.evaluar_aprobacion('00000000-0000-4000-8000-000000000002', jsonb_build_array(
    jsonb_build_object('producto_id', '00000000-0000-4000-e000-0000000000b1', 'subtotal', 1000.01)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' or (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO' then
    raise exception 'TEST 11: %', r;
  end if;
end;
$$;

-- Admin: identificadores.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  perform public.fijar_sku_producto('00000000-0000-4000-e000-0000000000b2', 'SKU-NUEVO');
  begin
    perform public.fijar_sku_producto('00000000-0000-4000-e000-0000000000b2', 'SKU-TEST-1');
    raise exception 'TEST 12: aceptó un SKU repetido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  perform public.fijar_codigo_proveedor(
    (select p.id from public.proveedores p where p.cuit = '30999999992'), 'P-TEST-2');
  begin
    perform public.fijar_codigo_proveedor(
      (select p.id from public.proveedores p where p.cuit = '30999999993'), 'P-TEST-2');
    raise exception 'TEST 13: aceptó un ID de proveedor repetido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST 14: la cadena de eventos se rompió';
  end if;
end;
$$;

reset role;
select 'marketplace: todos los tests pasaron' as resultado;
rollback;
