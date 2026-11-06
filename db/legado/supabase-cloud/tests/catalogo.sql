-- Eskemia · Tests del catálogo. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/catalogo.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

-- ---------------------------------------------------------------------------
-- Datos existentes
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from public.productos p
    where not exists (select 1 from public.presentaciones pr where pr.producto_id = p.id and pr.factor = 1)
  ) then
    raise exception 'TEST: hay productos sin presentación base';
  end if;
  if exists (
    select 1 from public.productos p
    where p.gtin is not null
      and not exists (
        select 1 from public.producto_codigos c
        where c.producto_id = p.id and c.codigo_busqueda = lpad(p.gtin, 14, '0')
      )
  ) then
    raise exception 'TEST: hay GTIN sin migrar a producto_codigos';
  end if;
  if exists (
    select 1 from public.productos p
    where p.unidad_stock <> case p.tipo_medida when 'PESO' then 'KG'::public.unidad_stock else 'UN'::public.unidad_stock end
  ) then
    raise exception 'TEST: unidad_stock no coincide con tipo_medida';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin: carga la cadena Rubro -> Categoría -> Producto -> Proveedor
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
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
  perform public.guardar_rubro(v_rubro, 'Rubro de test');
  perform public.guardar_rubro(v_rubro, 'Rubro de test');
  perform public.guardar_rubro(v_otro_rubro, 'Otro rubro de test');

  begin
    perform public.guardar_rubro(gen_random_uuid(), 'Rubro de test');
    raise exception 'TEST: aceptó un rubro repetido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  begin
    perform public.guardar_categoria(gen_random_uuid(), null, 'Sin rubro');
    raise exception 'TEST: aceptó una categoría sin rubro' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  -- Un mismo nombre de categoría vale en rubros distintos.
  perform public.guardar_categoria(v_categoria, v_rubro, 'Otros');
  perform public.guardar_categoria(gen_random_uuid(), v_otro_rubro, 'Otros');

  begin
    perform public.guardar_producto(gen_random_uuid(), null, 'Sin categoría');
    raise exception 'TEST: aceptó un producto sin categoría' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  perform public.guardar_producto(v_producto, v_categoria, 'Producto de test', 'KG');
  perform public.guardar_producto(v_otro_producto, v_categoria, 'Otro producto de test');

  select pr.id into v_base from public.presentaciones pr
  where pr.producto_id = v_producto and pr.nombre = 'Kilo' and pr.factor = 1;
  if not found then
    raise exception 'TEST: el producto no nació con su presentación base';
  end if;

  perform public.guardar_presentacion(v_caja, v_producto, 'Caja x 12', 12);
  begin
    perform public.guardar_presentacion(gen_random_uuid(), v_producto, 'Sin factor', 0);
    raise exception 'TEST: aceptó un factor cero' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  -- Código -> presentación: el mismo GTIN escrito con 13 o 14 dígitos es uno solo.
  perform public.guardar_codigo(gen_random_uuid(), v_producto, v_caja, '7799000000211', 'EAN13');
  begin
    perform public.guardar_codigo(gen_random_uuid(), v_otro_producto, (
      select pr.id from public.presentaciones pr where pr.producto_id = v_otro_producto
    ), '07799000000211', 'DUN14');
    raise exception 'TEST: aceptó un código repetido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.guardar_codigo(gen_random_uuid(), v_producto, v_caja, '7799000000212', 'EAN13');
    raise exception 'TEST: aceptó un GTIN inválido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.guardar_codigo(gen_random_uuid(), v_otro_producto, v_caja, 'INT-1', 'INTERNO');
    raise exception 'TEST: aceptó una presentación de otro producto' using errcode = 'P0003';
  exception when no_data_found then null;
  end;
  perform public.guardar_codigo(gen_random_uuid(), v_producto, v_caja, 'INT-1', 'INTERNO');

  perform public.guardar_proveedor(v_proveedor, 'Proveedor de test', '30-99999999-1', p_dias_pedido => array[1, 4]);
  perform public.guardar_proveedor(v_otro_proveedor, 'Otro proveedor de test', '30999999992');
  begin
    perform public.guardar_proveedor(gen_random_uuid(), 'Mal día', '30999999993', p_dias_pedido => array[9]);
    raise exception 'TEST: aceptó un día de pedido inválido' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  -- Precio: cada cambio deja historial; repetir el mismo no.
  perform public.guardar_producto_proveedor(v_oferta, v_producto, v_proveedor, v_caja, 100, null, true);
  perform public.guardar_producto_proveedor(v_oferta, v_producto, v_proveedor, v_caja, 100, null, true);
  perform public.guardar_producto_proveedor(v_oferta, v_producto, v_proveedor, v_caja, 120, null, true);
  if (select count(*) from public.precios_historial h where h.producto_proveedor_id = v_oferta) <> 2 then
    raise exception 'TEST: el historial de precios debería tener 2 filas';
  end if;

  -- El preferido nuevo reemplaza al anterior.
  perform public.guardar_producto_proveedor(v_otra_oferta, v_producto, v_otro_proveedor, v_base, 50, null, true);
  if (select count(*) from public.producto_proveedor pp where pp.producto_id = v_producto and pp.preferido) <> 1
     or not (select pp.preferido from public.producto_proveedor pp where pp.id = v_otra_oferta) then
    raise exception 'TEST: debería quedar un solo proveedor preferido';
  end if;

  -- Reintento de la cadena completa: el evento queda y el rubro se deriva de la categoría.
  if not exists (
    select 1 from public.productos p
    join public.categorias c on c.id = p.categoria_id
    join public.rubros r on r.id = c.rubro_id
    where p.id = v_producto and r.id = v_rubro
  ) then
    raise exception 'TEST: no se puede derivar el rubro del producto';
  end if;
  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST: la cadena de eventos se rompió';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Operario: alta rápida sigue andando; ni precios ni gestión de catálogo
-- ---------------------------------------------------------------------------
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_producto uuid := gen_random_uuid();
begin
  perform public.alta_rapida_producto(v_producto, 'Alta rápida de test', '7799000000228', 'PESO');
  if not exists (
    select 1 from public.productos p
    join public.presentaciones pr on pr.producto_id = p.id and pr.nombre = 'Kilo'
    join public.producto_codigos c on c.presentacion_id = pr.id and c.tipo = 'EAN13'
    where p.id = v_producto and p.pendiente_validacion and p.unidad_stock = 'KG'
  ) then
    raise exception 'TEST: la alta rápida no creó unidad, presentación y código';
  end if;

  if exists (select 1 from public.producto_proveedor) or exists (select 1 from public.precios_historial) then
    raise exception 'TEST: el operario no debería ver precios';
  end if;
  if not exists (select 1 from public.rubros) then
    raise exception 'TEST: el operario debería ver los rubros';
  end if;

  begin
    perform public.guardar_rubro(gen_random_uuid(), 'Sin permiso');
    raise exception 'TEST: el operario gestionó el catálogo' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select 'catalogo: todos los tests pasaron' as resultado;
rollback;
