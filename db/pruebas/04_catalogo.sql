-- Eskemia · Tests del catálogo (pgTAP). Portado de supabase/tests/catalogo.sql (legado).
--
-- Qué verifica: la cadena Rubro → Categoría → Producto → Presentación → Código →
-- Proveedor por RPC, con sus validaciones; historial de precios; un solo preferido; y que
-- el operario hace alta rápida pero no ve precios ni gestiona el catálogo.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).

select pruebas.escenario();
create temp table ids (clave text primary key, id uuid);
grant select, insert on ids to authenticated;
select * from no_plan();

-- Admin: carga la cadena completa ----------------------------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
declare
  o uuid := pruebas.id('org');
  v_rubro uuid := gen_random_uuid();
  v_otro_rubro uuid := gen_random_uuid();
  v_categoria uuid := gen_random_uuid();
  v_producto uuid := gen_random_uuid();
  v_otro_producto uuid := gen_random_uuid();
  v_caja uuid := gen_random_uuid();
  v_base uuid;
  v_proveedor uuid := gen_random_uuid();
  v_otro_proveedor uuid := gen_random_uuid();
  v_oferta uuid := gen_random_uuid();
  v_otra_oferta uuid := gen_random_uuid();
begin
  perform api.guardar_rubro(o, v_rubro, 'Rubro de test');
  perform api.guardar_rubro(o, v_rubro, 'Rubro de test');
  perform api.guardar_rubro(o, v_otro_rubro, 'Otro rubro de test');
  perform pruebas.falla('rubro repetido rechazado', 'PRECONDICION',
    format('select api.guardar_rubro(%L, gen_random_uuid(), %L)', o, 'Rubro de test'));
  perform pruebas.falla('categoría sin rubro rechazada', 'PRECONDICION',
    format('select api.guardar_categoria(%L, gen_random_uuid(), null, %L)', o, 'Sin rubro'));

  -- Un mismo nombre de categoría vale en rubros distintos.
  perform api.guardar_categoria(o, v_categoria, v_rubro, 'Otros');
  perform api.guardar_categoria(o, gen_random_uuid(), v_otro_rubro, 'Otros');

  perform pruebas.falla('producto sin categoría rechazado', 'PRECONDICION',
    format('select api.guardar_producto(%L, gen_random_uuid(), null, %L)', o, 'Sin categoría'));
  perform api.guardar_producto(o, v_producto, v_categoria, 'Producto de test', 'KG');
  perform api.guardar_producto(o, v_otro_producto, v_categoria, 'Otro producto de test');

  select pr.id into v_base from api.presentaciones pr
  where pr.producto_id = v_producto and pr.nombre = 'Kilo' and pr.factor = 1;
  perform pruebas.no('el producto nace con su presentación base', v_base is null);

  perform api.guardar_presentacion(o, v_caja, v_producto, 'Caja x 12', 12);
  perform pruebas.falla('factor cero rechazado', 'PRECONDICION',
    format('select api.guardar_presentacion(%L, gen_random_uuid(), %L, %L, 0)', o, v_producto, 'Sin factor'));

  -- El mismo GTIN escrito con 13 o 14 dígitos es uno solo.
  perform api.guardar_codigo(o, gen_random_uuid(), v_producto, v_caja, '7799000000211', 'EAN13');
  perform pruebas.falla('código repetido rechazado', 'PRECONDICION',
    format('select api.guardar_codigo(%L, gen_random_uuid(), %L, (select pr.id from api.presentaciones pr where pr.producto_id = %L), %L, %L)',
      o, v_otro_producto, v_otro_producto, '07799000000211', 'DUN14'));
  perform pruebas.falla('GTIN inválido rechazado', 'PRECONDICION',
    format('select api.guardar_codigo(%L, gen_random_uuid(), %L, %L, %L, %L)', o, v_producto, v_caja, '7799000000212', 'EAN13'));
  perform pruebas.falla('presentación de otro producto rechazada', 'NO_ENCONTRADO',
    format('select api.guardar_codigo(%L, gen_random_uuid(), %L, %L, %L, %L)', o, v_otro_producto, v_caja, 'INT-1', 'INTERNO'));
  perform api.guardar_codigo(o, gen_random_uuid(), v_producto, v_caja, 'INT-1', 'INTERNO');

  perform api.guardar_proveedor(o, v_proveedor, 'Proveedor de test', '30-99999999-1', p_dias_pedido => array[1, 4]);
  perform api.guardar_proveedor(o, v_otro_proveedor, 'Otro proveedor de test', '30999999992');
  perform pruebas.falla('día de pedido inválido rechazado', 'PRECONDICION',
    format('select api.guardar_proveedor(%L, gen_random_uuid(), %L, %L, p_dias_pedido => array[9])', o, 'Mal día', '30999999993'));

  -- Precio: cada cambio deja historial; repetir el mismo no (se verifica abajo).
  perform api.guardar_producto_proveedor(o, v_oferta, v_producto, v_proveedor, v_caja, 100, null, true);
  perform api.guardar_producto_proveedor(o, v_oferta, v_producto, v_proveedor, v_caja, 100, null, true);
  perform api.guardar_producto_proveedor(o, v_oferta, v_producto, v_proveedor, v_caja, 120, null, true);

  -- El preferido nuevo reemplaza al anterior.
  perform api.guardar_producto_proveedor(o, v_otra_oferta, v_producto, v_otro_proveedor, v_base, 50, null, true);
  perform pruebas.no('queda un solo proveedor preferido',
    (select count(*) from api.producto_proveedor pp where pp.producto_id = v_producto and pp.preferido) <> 1
    or not (select pp.preferido from api.producto_proveedor pp where pp.id = v_otra_oferta));

  perform pruebas.no('el rubro se deriva de la categoría', not exists (
    select 1 from api.productos p
    join api.categorias c on c.id = p.categoria_id
    where p.id = v_producto and c.rubro_id = v_rubro));
  perform pruebas.no('la cadena de eventos verifica', not (api.verificar_cadena_eventos(o) ->> 'ok')::boolean);
  insert into ids values ('oferta', v_oferta);
end;
$$;
reset role;

select is((select count(*)::int from compras.precios_historial h where h.producto_proveedor_id = (select id from ids where clave = 'oferta')),
  2, 'el historial de precios tiene una fila por cambio');

-- Operario: alta rápida sí; precios y gestión de catálogo no --------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  o uuid := pruebas.id('org');
  v_producto uuid := gen_random_uuid();
begin
  perform api.alta_rapida_producto(o, v_producto, 'Alta rápida de test', '7799000000228', 'PESO', false, false);
  perform pruebas.no('la alta rápida crea unidad, presentación y código', not exists (
    select 1 from api.productos p
    join api.presentaciones pr on pr.producto_id = p.id and pr.nombre = 'Kilo'
    join api.producto_codigos c on c.presentacion_id = pr.id and c.tipo = 'EAN13'
    where p.id = v_producto and p.pendiente_validacion and p.unidad_stock = 'KG'));
  perform pruebas.no('el operario no ve precios', exists (select 1 from api.producto_proveedor));
  perform pruebas.no('el operario ve los rubros', not exists (select 1 from api.rubros));
  perform pruebas.falla('el operario no gestiona el catálogo', 'SIN_PERMISO',
    format('select api.guardar_rubro(%L, gen_random_uuid(), %L)', o, 'Sin permiso'));
end;
$$;
reset role;

-- Datos que el legado verificaba sobre lo existente: ahora sobre lo cargado acá.
select is((select count(*)::int from compras.productos p
  where not exists (select 1 from compras.presentaciones pr where pr.producto_id = p.id and pr.factor = 1)),
  0, 'todo producto tiene presentación base');
select is((select count(*)::int from compras.productos p
  where p.unidad_stock <> case p.tipo_medida when 'PESO' then 'KG'::compras.unidad_stock else 'UN'::compras.unidad_stock end),
  0, 'unidad_stock coincide con tipo_medida');

select ok(ok, nombre) from chequeos order by n;
select * from finish();
