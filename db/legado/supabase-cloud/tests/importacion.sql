-- Eskemia · Tests de la importación CSV. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/importacion.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

insert into public.categorias (tenant_id, nombre)
values ('00000000-0000-4000-8000-000000000001', 'Sin rubro test');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  r jsonb;
  v_producto uuid;
begin
  -- Vista previa: informa pero no guarda.
  r := public.importar_catalogo('rubros', '[{"fila":2,"rubro":"Comida test"},{"fila":3,"rubro":"Limpieza test","orden":2}]');
  if (r ->> 'creados')::int <> 2 or (r ->> 'aplicado')::boolean then
    raise exception 'TEST: vista previa inesperada: %', r;
  end if;
  if exists (select 1 from public.rubros x where x.nombre = 'Comida test') then
    raise exception 'TEST: la vista previa guardó datos';
  end if;

  r := public.importar_catalogo('rubros', '[{"fila":2,"rubro":"Comida test"},{"fila":3,"rubro":"Limpieza test","orden":2}]', true);
  if not (r ->> 'aplicado')::boolean or (select count(*) from public.rubros x where x.nombre like '% test') <> 2 then
    raise exception 'TEST: no aplicó los rubros: %', r;
  end if;

  -- Todo o nada: una fila mala informa su número y no guarda ninguna.
  r := public.importar_catalogo('categorias',
    '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test"},{"fila":3,"rubro":"No existe","categoria":"Otra test"}]', true);
  if (r ->> 'aplicado')::boolean
     or (r -> 'errores' -> 0 ->> 'fila')::int <> 3
     or (r -> 'errores' -> 0 ->> 'mensaje') !~ 'No existe'
     or (r -> 'errores' -> 0 ->> 'mensaje') ~ '^NO_ENCONTRADO' then
    raise exception 'TEST: error de fila inesperado: %', r;
  end if;
  if exists (select 1 from public.categorias x where x.nombre = 'Lácteos test') then
    raise exception 'TEST: guardó filas de un archivo con errores';
  end if;

  r := public.importar_catalogo('categorias', '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test"}]', true);
  if not (r ->> 'aplicado')::boolean then raise exception 'TEST: categorías: %', r; end if;

  -- Adopta la categoría sin rubro en lugar de duplicarla.
  r := public.importar_catalogo('categorias', '[{"fila":2,"rubro":"Comida test","categoria":"Sin rubro test"}]', true);
  if (r ->> 'actualizados')::int <> 1 or exists (
    select 1 from public.categorias x where x.nombre = 'Sin rubro test' and x.rubro_id is null
  ) then
    raise exception 'TEST: no adoptó la categoría sin rubro: %', r;
  end if;

  r := public.importar_catalogo('productos',
    '[{"fila":2,"rubro":"Comida test","categoria":"Lácteos test","producto":"Leche test","unidad":"UN","requiere_vencimiento":true}]', true);
  if not (r ->> 'aplicado')::boolean then raise exception 'TEST: productos: %', r; end if;
  select x.id into v_producto from public.productos x where x.nombre = 'Leche test';

  -- Presentaciones y código. El GTIN de otro producto se rechaza.
  r := public.importar_catalogo('presentaciones',
    '[{"fila":2,"producto":"Leche test","presentacion":"Caja x 12","factor":12,"codigo":"7799000000211","tipo_codigo":"EAN13"}]', true);
  if not (r ->> 'aplicado')::boolean then raise exception 'TEST: presentaciones: %', r; end if;
  r := public.importar_catalogo('presentaciones',
    '[{"fila":2,"producto":"Leche test","presentacion":"Caja x 12","factor":12,"codigo":"7799000000211","tipo_codigo":"EAN13"}]', true);
  if (r ->> 'actualizados')::int <> 1 or (r ->> 'aplicado')::boolean is not true then
    raise exception 'TEST: reimportar debería actualizar: %', r;
  end if;
  r := public.importar_catalogo('presentaciones',
    '[{"fila":2,"producto":"Yerba mate","presentacion":"Caja test","factor":6,"codigo":"7799000000211","tipo_codigo":"EAN13"}]');
  if jsonb_array_length(r -> 'errores') <> 1 then
    raise exception 'TEST: aceptó un código de otro producto: %', r;
  end if;

  r := public.importar_catalogo('proveedores', '[
    {"fila":2,"proveedor":"Proveedor A test","cuit":"30-99999999-1","canal_envio":"WHATSAPP","dias_pedido":[1,4],"monto_minimo":1000.5},
    {"fila":3,"proveedor":"Proveedor B test","cuit":"30999999992"}]', true);
  if not (r ->> 'aplicado')::boolean then raise exception 'TEST: proveedores: %', r; end if;
  if (select x.dias_pedido from public.proveedores x where x.cuit = '30999999991') <> array[1, 4] then
    raise exception 'TEST: no guardó los días de pedido';
  end if;

  -- Un producto con dos proveedores: dos filas, ambos quedan disponibles para elegir.
  r := public.importar_catalogo('precios', '[
    {"fila":2,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999991","precio":1240.5,"preferido":true},
    {"fila":3,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999992","precio":1100}]', true);
  if not (r ->> 'aplicado')::boolean then raise exception 'TEST: precios: %', r; end if;
  if (select count(*) from public.producto_proveedor x where x.producto_id = v_producto and x.activo) <> 2 then
    raise exception 'TEST: el producto debería tener 2 proveedores';
  end if;

  -- Reimportar el mismo precio no agrega historial.
  r := public.importar_catalogo('precios', '[
    {"fila":2,"producto":"Leche test","presentacion":"Caja x 12","cuit":"30999999991","precio":1240.5,"preferido":true}]', true);
  if (r ->> 'actualizados')::int <> 1
     or (select count(*) from public.precios_historial h
         join public.producto_proveedor x on x.id = h.producto_proveedor_id
         where x.producto_id = v_producto) <> 2 then
    raise exception 'TEST: el historial creció sin cambio de precio: %', r;
  end if;

  begin
    perform public.importar_catalogo('otra_cosa', '[{"fila":2}]');
    raise exception 'TEST: aceptó un tipo desconocido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST: la cadena de eventos se rompió';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  perform public.importar_catalogo('rubros', '[{"fila":2,"rubro":"Sin permiso"}]', true);
  raise exception 'TEST: el operario importó' using errcode = 'ZZ001';
exception when insufficient_privilege then null;
end;
$$;

reset role;
select 'importacion: todos los tests pasaron' as resultado;
rollback;
