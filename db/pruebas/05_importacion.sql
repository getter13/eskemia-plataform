-- Eskemia · Tests de la importación CSV del catálogo (pgTAP). Portado de
-- supabase/tests/importacion.sql (legado).
--
-- Qué verifica: vista previa sin guardar, todo o nada con el número de fila del error,
-- reimportar actualiza, códigos de otro producto rechazados, dos proveedores por producto,
-- historial sin cambios de precio, y que el operario no importa.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).

select pruebas.escenario();
create temp table ids (clave text primary key, id uuid);
grant select, insert on ids to authenticated;
select * from no_plan();

select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
declare
  o uuid := pruebas.id('org');
  r jsonb;
  v_producto uuid;
begin
  -- Vista previa: informa pero no guarda.
  r := api.importar_catalogo(o, 'rubros', '[{"fila":2,"rubro":"Comida test"},{"fila":3,"rubro":"Limpieza test","orden":2}]', false);
  perform pruebas.no('la vista previa informa 2 rubros sin aplicar', (r ->> 'creados')::int <> 2 or (r ->> 'aplicado')::boolean);
  perform pruebas.no('la vista previa no guarda', exists (select 1 from api.rubros x where x.nombre = 'Comida test'));

  r := api.importar_catalogo(o, 'rubros', '[{"fila":2,"rubro":"Comida test"},{"fila":3,"rubro":"Limpieza test","orden":2}]', true);
  perform pruebas.no('aplica los rubros',
    not (r ->> 'aplicado')::boolean or (select count(*) from api.rubros x where x.nombre like '% test') <> 2);

  -- Todo o nada: una fila mala informa su número y no guarda ninguna.
  r := api.importar_catalogo(o, 'categorias',
    '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test"},{"fila":3,"rubro":"No existe","categoria":"Otra test"}]', true);
  perform pruebas.no('una fila mala informa su número y un mensaje legible',
    (r ->> 'aplicado')::boolean
    or (r -> 'errores' -> 0 ->> 'fila')::int <> 3
    or (r -> 'errores' -> 0 ->> 'mensaje') !~ 'No existe'
    or (r -> 'errores' -> 0 ->> 'mensaje') ~ '^NO_ENCONTRADO');
  perform pruebas.no('un archivo con errores no guarda nada', exists (select 1 from api.categorias x where x.nombre = 'Lácteos test'));

  r := api.importar_catalogo(o, 'categorias', '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test"}]', true);
  perform pruebas.no('aplica las categorías', not (r ->> 'aplicado')::boolean);

  r := api.importar_catalogo(o, 'productos',
    '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test","producto":"Leche test","unidad":"UN","requiere_vencimiento":true}]', true);
  perform pruebas.no('aplica los productos', not (r ->> 'aplicado')::boolean);
  select x.id into v_producto from api.productos x where x.nombre = 'Leche test';
  insert into ids values ('producto', v_producto);

  -- Presentaciones y código. El GTIN de otro producto se rechaza.
  r := api.importar_catalogo(o, 'presentaciones',
    '[{"fila":2,"producto":"Leche test","presentacion":"Caja x 12","factor":12,"codigo":"7799000000211","tipo_codigo":"EAN13"}]', true);
  perform pruebas.no('aplica las presentaciones', not (r ->> 'aplicado')::boolean);
  r := api.importar_catalogo(o, 'presentaciones',
    '[{"fila":2,"producto":"Leche test","presentacion":"Caja x 12","factor":12,"codigo":"7799000000211","tipo_codigo":"EAN13"}]', true);
  perform pruebas.no('reimportar actualiza', (r ->> 'actualizados')::int <> 1 or (r ->> 'aplicado')::boolean is not true);

  perform api.guardar_producto(o, gen_random_uuid(),
    (select c.id from api.categorias c where c.nombre = 'Lácteos test'), 'Yerba mate');
  r := api.importar_catalogo(o, 'presentaciones',
    '[{"fila":2,"producto":"Yerba mate","presentacion":"Caja test","factor":6,"codigo":"7799000000211","tipo_codigo":"EAN13"}]', false);
  perform pruebas.no('rechaza un código de otro producto', jsonb_array_length(r -> 'errores') <> 1);

  r := api.importar_catalogo(o, 'proveedores', '[
    {"fila":2,"proveedor":"Proveedor A test","cuit":"30-99999999-1","canal_envio":"WHATSAPP","dias_pedido":[1,4],"monto_minimo":1000.5},
    {"fila":3,"proveedor":"Proveedor B test","cuit":"30999999992"}]', true);
  perform pruebas.no('aplica los proveedores', not (r ->> 'aplicado')::boolean);
  perform pruebas.no('guarda los días de pedido',
    (select x.dias_pedido from api.proveedores x where x.cuit = '30999999991') is distinct from array[1, 4]);

  -- Un producto con dos proveedores: dos filas, ambos quedan para elegir.
  r := api.importar_catalogo(o, 'precios', '[
    {"fila":2,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999991","precio":1240.5,"preferido":true},
    {"fila":3,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999992","precio":1100}]', true);
  perform pruebas.no('aplica los precios', not (r ->> 'aplicado')::boolean);
  perform pruebas.no('el producto tiene 2 proveedores',
    (select count(*) from api.producto_proveedor x where x.producto_id = v_producto and x.activo) <> 2);

  -- Reimportar el mismo precio no agrega historial (se verifica abajo).
  r := api.importar_catalogo(o, 'precios', '[
    {"fila":2,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999991","precio":1240.5,"preferido":true}]', true);
  perform pruebas.no('reimportar un precio igual cuenta como actualizado', (r ->> 'actualizados')::int <> 1);

  perform pruebas.falla('tipo de importación desconocido rechazado', 'PRECONDICION',
    format('select api.importar_catalogo(%L, %L, %L, false)', o, 'otra_cosa', '[{"fila":2}]'));
  perform pruebas.no('la cadena de eventos verifica', not (api.verificar_cadena_eventos(o) ->> 'ok')::boolean);
end;
$$;
reset role;

select is((select count(*)::int from compras.precios_historial h
  join compras.producto_proveedor x on x.id = h.producto_proveedor_id
  where x.producto_id = (select id from ids where clave = 'producto')),
  2, 'el historial no crece sin cambio de precio');

select pruebas.como('e0000000-0000-4000-8000-000000000002');
select pruebas.falla('el operario no importa', 'SIN_PERMISO',
  format('select api.importar_catalogo(%L, %L, %L, true)', pruebas.id('org'), 'rubros', '[{"fila":2,"rubro":"Sin permiso"}]'));
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
