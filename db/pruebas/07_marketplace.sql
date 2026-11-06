-- Eskemia · Tests del catálogo de compras (marketplace) (pgTAP). Portado de
-- supabase/tests/marketplace.sql (legado).
--
-- Qué verifica: catalogo_compras con rubro, categoría, SKU y ofertas (sin inactivas, el
-- preferido primero), regla vigente por producto, restricción por sector, y la gestión de
-- SKU e ID de proveedor (únicos, solo con permiso).
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).

select pruebas.escenario();
select * from no_plan();

do $$
declare
  o uuid := pruebas.id('org');
  v_rubro uuid := 'e0000000-0000-4000-e000-0000000000a1';
  v_otro_rubro uuid := 'e0000000-0000-4000-e000-0000000000a2';
  v_cat uuid := gen_random_uuid();
  v_otra_cat uuid := gen_random_uuid();
  v_multi uuid := 'e0000000-0000-4000-e000-0000000000b1';
  v_otro uuid := 'e0000000-0000-4000-e000-0000000000b2';
  v_sin_oferta uuid := 'e0000000-0000-4000-e000-0000000000b3';
  v_prov_a uuid := gen_random_uuid();
  v_prov_b uuid := gen_random_uuid();
  v_prov_c uuid := gen_random_uuid();
  v_pre uuid;
begin
  insert into compras.rubros (id, organizacion_id, nombre) values (v_rubro, o, 'Comida test'), (v_otro_rubro, o, 'Limpieza test');
  insert into compras.categorias (id, organizacion_id, rubro_id, nombre) values (v_cat, o, v_rubro, 'Lácteos test'), (v_otra_cat, o, v_otro_rubro, 'Lavandinas test');
  insert into compras.productos (id, organizacion_id, categoria_id, nombre, sku, tipo_medida) values
    (v_multi, o, v_cat, 'Leche test', 'SKU-TEST-1', 'UNIDAD'),
    (v_otro, o, v_otra_cat, 'Lavandina test', 'SKU-TEST-2', 'UNIDAD'),
    (v_sin_oferta, o, v_cat, 'Sin proveedor test', null, 'UNIDAD');
  insert into compras.proveedores (id, organizacion_id, nombre, cuit, codigo) values
    (v_prov_a, o, 'Prov A test', '30999999991', 'P-TEST-1'),
    (v_prov_b, o, 'Prov B test', '30999999992', null),
    (v_prov_c, o, 'Prov C test', '30999999993', null);

  select id into v_pre from compras.presentaciones where producto_id = v_multi;
  insert into compras.producto_proveedor (organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual, preferido, activo) values
    (o, v_multi, v_prov_a, v_pre, 200, false, true),
    (o, v_multi, v_prov_b, v_pre, 300, true, true),
    (o, v_multi, v_prov_c, v_pre, 100, false, false);
  select id into v_pre from compras.presentaciones where producto_id = v_otro;
  insert into compras.producto_proveedor (organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  values (o, v_otro, v_prov_a, v_pre, 50);

  insert into compras.reglas_aprobacion (organizacion_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido)
  values (o, 'RUBRO', v_rubro, 'POR_MONTO', 1000, 1);
  insert into nucleo.sectores (id, organizacion_id, nombre) values ('e0000000-0000-4000-e000-0000000000c1', o, 'Cocina test');

  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Comprador');
end;
$$;

select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  s uuid := pruebas.id('sede');
  f record;
begin
  select * into f from api.catalogo_compras(s) c where c.producto_id = 'e0000000-0000-4000-e000-0000000000b1';
  perform pruebas.no('1: el producto aparece en el catálogo', f is null);
  perform pruebas.no('2: trae rubro, categoría y SKU', f.rubro <> 'Comida test' or f.categoria <> 'Lácteos test' or f.sku <> 'SKU-TEST-1');
  perform pruebas.no('3: sin ofertas inactivas y el preferido primero', jsonb_array_length(f.ofertas) <> 2
    or (f.ofertas -> 0 ->> 'proveedor') <> 'Prov B test' or not (f.ofertas -> 0 ->> 'preferido')::boolean
    or (f.ofertas -> 1 ->> 'proveedor_codigo') <> 'P-TEST-1');
  perform pruebas.no('4: trae la regla vigente', f.regla_modo <> 'POR_MONTO' or f.regla_monto_umbral <> 1000);
  perform pruebas.no('5: no muestra productos sin proveedor', exists (select 1 from api.catalogo_compras(s) c where c.nombre = 'Sin proveedor test'));
  perform pruebas.no('6: muestra el otro rubro', not exists (select 1 from api.catalogo_compras(s) c where c.nombre = 'Lavandina test'));
end;
$$;
reset role;

-- Sector restringido a un rubro.
update nucleo.membresia_roles mr set sector_id = 'e0000000-0000-4000-e000-0000000000c1'
from nucleo.membresias m where m.id = mr.membresia_id and m.cuenta_id = 'e0000000-0000-4000-8000-000000000003';
select pruebas.como('e0000000-0000-4000-8000-000000000003');
select pruebas.no('7: un sector sin rubros no restringe',
  not exists (select 1 from api.catalogo_compras(pruebas.id('sede')) c where c.nombre = 'Lavandina test'));
reset role;
insert into compras.sector_rubros (organizacion_id, sector_id, rubro_id)
values (pruebas.id('org'), 'e0000000-0000-4000-e000-0000000000c1', 'e0000000-0000-4000-e000-0000000000a1');
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  r jsonb;
begin
  perform pruebas.no('8: el sector no ve un rubro ajeno',
    exists (select 1 from api.catalogo_compras(pruebas.id('sede')) c where c.nombre = 'Lavandina test'));
  perform pruebas.no('9: el sector ve su rubro',
    not exists (select 1 from api.catalogo_compras(pruebas.id('sede')) c where c.nombre = 'Leche test'));
  perform pruebas.falla('10: el comprador no cambia un SKU', 'SIN_PERMISO',
    'select api.fijar_sku_producto(''e0000000-0000-4000-e000-0000000000b1'', ''X'')');

  r := api.evaluar_aprobacion(pruebas.id('sede'), jsonb_build_array(
    jsonb_build_object('producto_id', 'e0000000-0000-4000-e000-0000000000b1', 'subtotal', 1000.01)));
  perform pruebas.no('11: evaluar_aprobacion resuelve la regla del rubro',
    (r ->> 'estado') <> 'PENDIENTE_APROBACION' or (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO');
end;
$$;
reset role;

-- Admin: identificadores.
select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
begin
  perform api.fijar_sku_producto('e0000000-0000-4000-e000-0000000000b2', 'SKU-NUEVO');
  perform pruebas.falla('12: SKU repetido rechazado', 'PRECONDICION',
    'select api.fijar_sku_producto(''e0000000-0000-4000-e000-0000000000b2'', ''SKU-TEST-1'')');
  perform api.fijar_codigo_proveedor((select p.id from api.proveedores p where p.cuit = '30999999992'), 'P-TEST-2');
  perform pruebas.falla('13: ID de proveedor repetido rechazado', 'PRECONDICION',
    format('select api.fijar_codigo_proveedor(%L, %L)', (select p.id from api.proveedores p where p.cuit = '30999999993'), 'P-TEST-2'));
  perform pruebas.no('14: la cadena de eventos verifica', not (api.verificar_cadena_eventos(pruebas.id('org')) ->> 'ok')::boolean);
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
