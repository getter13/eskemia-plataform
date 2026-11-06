-- Eskemia · Línea base v1 · 09: RPC de Compras (esquema api).
--
-- Qué hace: catálogo (ABM e importación), pedidos, órdenes de compra y su aprobación.
-- Dónde encaja: port de public.* del legado, con las mismas reglas. Cambio de forma: la
-- organización llega explícita (p_organizacion_id) cuando no se deduce de una sede
-- obligatoria o de la entidad que se opera.
-- Cada RPC: qué hace · precondiciones · permisos · eventos. Todas exigen el módulo
-- compras habilitado (vía nucleo.exigir_permiso / tiene_permiso).

-- ---------------------------------------------------------------------------
-- Catálogo
-- ---------------------------------------------------------------------------

/** api.guardar_rubro — Alta o edición de un rubro (upsert por id).
 *  Precondiciones: nombre no vacío y único. Permisos: compras.catalogo.gestionar.
 *  Eventos: rubro/guardado. */
create function api.guardar_rubro(p_organizacion_id uuid, p_id uuid, p_nombre text, p_orden int default 0, p_activo boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
begin
  insert into compras.rubros (id, organizacion_id, nombre, orden, activo)
  values (p_id, v_m.organizacion_id, btrim(p_nombre), p_orden, p_activo)
  on conflict (id) do update
    set nombre = excluded.nombre, orden = excluded.orden, activo = excluded.activo
    where compras.rubros.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: rubro inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'rubro', p_id, 'guardado',
    jsonb_build_object('nombre', btrim(p_nombre), 'orden', p_orden, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ya existe un rubro con ese nombre' using errcode = 'P0001';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre del rubro' using errcode = 'P0001';
end;
$$;

/** api.guardar_categoria — Alta o edición de una categoría dentro de un rubro.
 *  Precondiciones: rubro obligatorio; nombre único en el rubro.
 *  Permisos: compras.catalogo.gestionar. Eventos: categoria/guardada. */
create function api.guardar_categoria(p_organizacion_id uuid, p_id uuid, p_rubro_id uuid, p_nombre text, p_orden int default 0, p_activo boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
begin
  if p_rubro_id is null then
    raise exception 'PRECONDICION: la categoría necesita un rubro' using errcode = 'P0001';
  end if;

  insert into compras.categorias (id, organizacion_id, rubro_id, nombre, orden, activo)
  values (p_id, v_m.organizacion_id, p_rubro_id, btrim(p_nombre), p_orden, p_activo)
  on conflict (id) do update
    set rubro_id = excluded.rubro_id, nombre = excluded.nombre,
        orden = excluded.orden, activo = excluded.activo
    where compras.categorias.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: categoría inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'categoria', p_id, 'guardada',
    jsonb_build_object('rubro_id', p_rubro_id, 'nombre', btrim(p_nombre), 'orden', p_orden, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese rubro ya tiene una categoría con ese nombre' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: rubro inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre de la categoría' using errcode = 'P0001';
end;
$$;

/** api.guardar_producto — Alta o edición de un producto del catálogo. Al editar, deja
 *  de estar pendiente de validación.
 *  Precondiciones: categoría obligatoria; nombre no vacío.
 *  Permisos: compras.catalogo.gestionar. Eventos: producto/guardado. */
create function api.guardar_producto(
  p_organizacion_id uuid,
  p_id uuid,
  p_categoria_id uuid,
  p_nombre text,
  p_unidad_stock compras.unidad_stock default 'UN',
  p_requiere_lote boolean default false,
  p_requiere_vencimiento boolean default false,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
  v_medida compras.tipo_medida :=
    case when p_unidad_stock = 'UN' then 'UNIDAD'::compras.tipo_medida else 'PESO'::compras.tipo_medida end;
begin
  if p_categoria_id is null then
    raise exception 'PRECONDICION: el producto necesita una categoría' using errcode = 'P0001';
  end if;

  insert into compras.productos
    (id, organizacion_id, categoria_id, nombre, unidad_stock, tipo_medida,
     requiere_lote, requiere_vencimiento, activo)
  values
    (p_id, v_m.organizacion_id, p_categoria_id, btrim(p_nombre), p_unidad_stock, v_medida,
     p_requiere_lote, p_requiere_vencimiento, p_activo)
  on conflict (id) do update
    set categoria_id = excluded.categoria_id,
        nombre = excluded.nombre,
        unidad_stock = excluded.unidad_stock,
        tipo_medida = excluded.tipo_medida,
        requiere_lote = excluded.requiere_lote,
        requiere_vencimiento = excluded.requiere_vencimiento,
        activo = excluded.activo,
        pendiente_validacion = false
    where compras.productos.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'producto', p_id, 'guardado',
    jsonb_build_object(
      'categoria_id', p_categoria_id, 'nombre', btrim(p_nombre), 'unidad_stock', p_unidad_stock,
      'activo', p_activo
    )
  );
  return p_id;
exception
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: categoría inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre del producto' using errcode = 'P0001';
end;
$$;

/** api.guardar_presentacion — Alta o edición de una presentación de un producto.
 *  Precondiciones: nombre no vacío y único en el producto; factor > 0.
 *  Permisos: compras.catalogo.gestionar. Eventos: presentacion/guardada. */
create function api.guardar_presentacion(p_organizacion_id uuid, p_id uuid, p_producto_id uuid, p_nombre text, p_factor numeric, p_activa boolean default true)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
begin
  insert into compras.presentaciones (id, organizacion_id, producto_id, nombre, factor, activa)
  values (p_id, v_m.organizacion_id, p_producto_id, btrim(p_nombre), p_factor, p_activa)
  on conflict (id) do update
    set nombre = excluded.nombre, factor = excluded.factor, activa = excluded.activa
    where compras.presentaciones.organizacion_id = excluded.organizacion_id
      and compras.presentaciones.producto_id = excluded.producto_id;
  if not found then
    raise exception 'NO_ENCONTRADO: presentación inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'presentacion', p_id, 'guardada',
    jsonb_build_object('producto_id', p_producto_id, 'nombre', btrim(p_nombre), 'factor', p_factor, 'activa', p_activa)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: el producto ya tiene una presentación con ese nombre' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: la presentación necesita nombre y un factor mayor a cero' using errcode = 'P0001';
end;
$$;

/** api.guardar_codigo — Alta o edición de un código de barras de una presentación.
 *  Precondiciones: código válido para su tipo y no repetido en la organización.
 *  Permisos: compras.catalogo.gestionar. Eventos: producto_codigo/guardado. */
create function api.guardar_codigo(p_organizacion_id uuid, p_id uuid, p_producto_id uuid, p_presentacion_id uuid, p_codigo text, p_tipo compras.tipo_codigo)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
begin
  insert into compras.producto_codigos (id, organizacion_id, producto_id, presentacion_id, codigo, tipo)
  values (p_id, v_m.organizacion_id, p_producto_id, p_presentacion_id, btrim(p_codigo), p_tipo)
  on conflict (id) do update
    set producto_id = excluded.producto_id,
        presentacion_id = excluded.presentacion_id,
        codigo = excluded.codigo,
        tipo = excluded.tipo
    where compras.producto_codigos.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: código inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'producto_codigo', p_id, 'guardado',
    jsonb_build_object(
      'producto_id', p_producto_id, 'presentacion_id', p_presentacion_id,
      'codigo', btrim(p_codigo), 'tipo', p_tipo
    )
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese código ya está asignado a un producto' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: la presentación no corresponde al producto' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: el código no es válido para ese tipo' using errcode = 'P0001';
end;
$$;

/** api.guardar_proveedor — Alta o edición de un proveedor.
 *  Precondiciones: CUIT de 11 dígitos, único en la organización.
 *  Permisos: compras.catalogo.gestionar. Eventos: proveedor/guardado. */
create function api.guardar_proveedor(
  p_organizacion_id uuid,
  p_id uuid,
  p_nombre text,
  p_cuit text,
  p_contacto text default null,
  p_telefono_whatsapp text default null,
  p_email text default null,
  p_canal_envio compras.canal_envio default 'MANUAL',
  p_plazo_entrega_dias int default null,
  p_dias_pedido int[] default null,
  p_monto_minimo numeric default null,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
  v_cuit text := regexp_replace(coalesce(p_cuit, ''), '[^0-9]', '', 'g');
begin
  if v_cuit !~ '^[0-9]{11}$' then
    raise exception 'PRECONDICION: el CUIT debe tener 11 dígitos' using errcode = 'P0001';
  end if;

  insert into compras.proveedores
    (id, organizacion_id, nombre, cuit, contacto, telefono_whatsapp, email, canal_envio,
     plazo_entrega_dias, dias_pedido, monto_minimo, activo)
  values
    (p_id, v_m.organizacion_id, btrim(p_nombre), v_cuit, p_contacto, p_telefono_whatsapp, p_email,
     p_canal_envio, p_plazo_entrega_dias, p_dias_pedido, p_monto_minimo, p_activo)
  on conflict (id) do update
    set nombre = excluded.nombre,
        cuit = excluded.cuit,
        contacto = excluded.contacto,
        telefono_whatsapp = excluded.telefono_whatsapp,
        email = excluded.email,
        canal_envio = excluded.canal_envio,
        plazo_entrega_dias = excluded.plazo_entrega_dias,
        dias_pedido = excluded.dias_pedido,
        monto_minimo = excluded.monto_minimo,
        activo = excluded.activo
    where compras.proveedores.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: proveedor inexistente' using errcode = 'P0002';
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'proveedor', p_id, 'guardado',
    jsonb_build_object('nombre', btrim(p_nombre), 'cuit', v_cuit, 'canal_envio', p_canal_envio, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ya existe un proveedor con ese CUIT' using errcode = 'P0001';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: revisá el nombre, el plazo, los días de pedido y el monto mínimo'
      using errcode = 'P0001';
end;
$$;

/** api.guardar_producto_proveedor — Alta o edición de la oferta de un proveedor para
 *  una presentación. Marcar preferido desmarca a los demás del producto. Si cambia el
 *  precio, lo registra en el historial.
 *  Permisos: compras.catalogo.gestionar. Eventos: producto_proveedor/guardado. */
create function api.guardar_producto_proveedor(
  p_organizacion_id uuid,
  p_id uuid,
  p_producto_id uuid,
  p_proveedor_id uuid,
  p_presentacion_id uuid,
  p_precio numeric default null,
  p_codigo_proveedor text default null,
  p_preferido boolean default false,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
  v_previo numeric;
begin
  select pp.precio_actual into v_previo from compras.producto_proveedor pp
  where pp.id = p_id and pp.organizacion_id = v_m.organizacion_id;

  if p_preferido and p_activo then
    update compras.producto_proveedor pp set preferido = false
    where pp.producto_id = p_producto_id and pp.id <> p_id and pp.preferido
      and pp.organizacion_id = v_m.organizacion_id;
  end if;

  insert into compras.producto_proveedor
    (id, organizacion_id, producto_id, proveedor_id, presentacion_id, codigo_proveedor,
     precio_actual, preferido, activo)
  values
    (p_id, v_m.organizacion_id, p_producto_id, p_proveedor_id, p_presentacion_id, p_codigo_proveedor,
     p_precio, p_preferido, p_activo)
  on conflict (id) do update
    set producto_id = excluded.producto_id,
        proveedor_id = excluded.proveedor_id,
        presentacion_id = excluded.presentacion_id,
        codigo_proveedor = excluded.codigo_proveedor,
        precio_actual = excluded.precio_actual,
        preferido = excluded.preferido,
        activo = excluded.activo
    where compras.producto_proveedor.organizacion_id = excluded.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: relación inexistente' using errcode = 'P0002';
  end if;

  if p_precio is not null and p_precio is distinct from v_previo then
    insert into compras.precios_historial (organizacion_id, producto_proveedor_id, precio, usuario_id)
    values (v_m.organizacion_id, p_id, p_precio, auth.uid());
  end if;

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'producto_proveedor', p_id, 'guardado',
    jsonb_build_object(
      'producto_id', p_producto_id, 'proveedor_id', p_proveedor_id,
      'presentacion_id', p_presentacion_id, 'precio', p_precio,
      'precio_anterior', v_previo, 'preferido', p_preferido, 'activo', p_activo
    )
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese proveedor ya tiene cargada esa presentación' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: producto, proveedor o presentación inexistente' using errcode = 'P0002';
  when check_violation then
    raise exception 'PRECONDICION: el precio no es válido' using errcode = 'P0001';
end;
$$;

/** api.fijar_sku_producto — Fija (o borra, con nulo) el SKU interno de un producto.
 *  Precondiciones: SKU único en la organización.
 *  Permisos: compras.catalogo.gestionar. Eventos: producto/sku. */
create function api.fijar_sku_producto(p_producto_id uuid, p_sku text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select p.organizacion_id from compras.productos p where p.id = p_producto_id), 'producto');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.catalogo.gestionar');
  v_sku text := nullif(btrim(p_sku), '');
begin
  update compras.productos p set sku = v_sku
  where p.id = p_producto_id and p.organizacion_id = v_m.organizacion_id;

  perform nucleo.registrar_evento(
    v_org, null, 'producto', p_producto_id, 'sku', jsonb_build_object('sku', v_sku)
  );
exception when unique_violation then
  raise exception 'PRECONDICION: ese SKU ya está asignado a otro producto' using errcode = 'P0001';
end;
$$;

/** api.fijar_codigo_proveedor — Fija (o borra) el ID interno de un proveedor.
 *  Precondiciones: único en la organización.
 *  Permisos: compras.catalogo.gestionar. Eventos: proveedor/codigo. */
create function api.fijar_codigo_proveedor(p_proveedor_id uuid, p_codigo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select p.organizacion_id from compras.proveedores p where p.id = p_proveedor_id), 'proveedor');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.catalogo.gestionar');
  v_codigo text := nullif(btrim(p_codigo), '');
begin
  update compras.proveedores p set codigo = v_codigo
  where p.id = p_proveedor_id and p.organizacion_id = v_m.organizacion_id;

  perform nucleo.registrar_evento(
    v_org, null, 'proveedor', p_proveedor_id, 'codigo', jsonb_build_object('codigo', v_codigo)
  );
exception when unique_violation then
  raise exception 'PRECONDICION: ese ID ya está asignado a otro proveedor' using errcode = 'P0001';
end;
$$;

/** Interna: importa una fila de catálogo llamando a las RPC de alta/edición (que
 *  exigen el permiso y escriben sus eventos). Devuelve true si creó, false si actualizó. */
create function compras.importar_fila(p_organizacion_id uuid, p_tipo text, f jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_rubro uuid;
  v_categoria uuid;
  v_producto uuid;
  v_presentacion uuid;
  v_proveedor uuid;
  v_codigo uuid;
  v_tipo compras.tipo_codigo;
  v_cuit text;
begin
  if p_tipo = 'rubros' then
    select r.id into v_id from compras.rubros r
    where r.organizacion_id = p_organizacion_id and lower(r.nombre) = lower(btrim(f ->> 'rubro'));

    perform api.guardar_rubro(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), f ->> 'rubro', coalesce((f ->> 'orden')::int, 0)
    );

  elsif p_tipo = 'categorias' then
    v_rubro := compras.importar_rubro_existente(p_organizacion_id, f ->> 'rubro');

    -- Una categoría anterior a los rubros se adopta en lugar de duplicarse.
    select c.id into v_id from compras.categorias c
    where c.organizacion_id = p_organizacion_id
      and (c.rubro_id = v_rubro or c.rubro_id is null)
      and lower(c.nombre) = lower(btrim(f ->> 'categoria'))
    order by c.rubro_id nulls last
    limit 1;

    perform api.guardar_categoria(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), v_rubro, f ->> 'categoria',
      coalesce((f ->> 'orden')::int, 0)
    );

  elsif p_tipo = 'productos' then
    v_rubro := compras.importar_rubro_existente(p_organizacion_id, f ->> 'rubro');

    select c.id into v_categoria from compras.categorias c
    where c.organizacion_id = p_organizacion_id and c.rubro_id = v_rubro
      and lower(c.nombre) = lower(btrim(f ->> 'categoria'));
    if not found then
      raise exception 'NO_ENCONTRADO: el rubro "%" no tiene la categoría "%". Importá primero las categorías',
        btrim(f ->> 'rubro'), btrim(f ->> 'categoria') using errcode = 'P0002';
    end if;

    v_id := compras.importar_producto(p_organizacion_id, f ->> 'producto');
    perform api.guardar_producto(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), v_categoria, f ->> 'producto',
      (f ->> 'unidad')::compras.unidad_stock,
      coalesce((f ->> 'requiere_lote')::boolean, false),
      coalesce((f ->> 'requiere_vencimiento')::boolean, false)
    );

  elsif p_tipo = 'presentaciones' then
    v_producto := compras.importar_producto_existente(p_organizacion_id, f ->> 'producto');

    select pr.id into v_id from compras.presentaciones pr
    where pr.producto_id = v_producto and lower(pr.nombre) = lower(btrim(f ->> 'presentacion'));

    v_presentacion := api.guardar_presentacion(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), v_producto, f ->> 'presentacion',
      (f ->> 'factor')::numeric
    );

    if nullif(btrim(f ->> 'codigo'), '') is not null then
      v_tipo := (f ->> 'tipo_codigo')::compras.tipo_codigo;
      -- Un código ajeno no se reasigna: guardar_codigo lo rechaza por repetido.
      select c.id into v_codigo from compras.producto_codigos c
      where c.organizacion_id = p_organizacion_id
        and c.producto_id = v_producto
        and c.codigo_busqueda = case
          when v_tipo in ('EAN13', 'EAN8', 'DUN14', 'UPC') then lpad(btrim(f ->> 'codigo'), 14, '0')
          else btrim(f ->> 'codigo')
        end;
      perform api.guardar_codigo(
        p_organizacion_id, coalesce(v_codigo, gen_random_uuid()), v_producto, v_presentacion,
        f ->> 'codigo', v_tipo
      );
    end if;

  elsif p_tipo = 'proveedores' then
    v_cuit := regexp_replace(coalesce(f ->> 'cuit', ''), '[^0-9]', '', 'g');
    select pr.id into v_id from compras.proveedores pr
    where pr.organizacion_id = p_organizacion_id and pr.cuit = v_cuit;

    perform api.guardar_proveedor(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), f ->> 'proveedor', v_cuit,
      f ->> 'contacto', f ->> 'telefono_whatsapp', f ->> 'email',
      coalesce((f ->> 'canal_envio')::compras.canal_envio, 'MANUAL'),
      (f ->> 'plazo_entrega_dias')::int,
      (select array_agg(d::int) from jsonb_array_elements_text(
        case when jsonb_typeof(f -> 'dias_pedido') = 'array' then f -> 'dias_pedido' else '[]'::jsonb end
      ) as d),
      (f ->> 'monto_minimo')::numeric
    );

  elsif p_tipo = 'precios' then
    v_producto := compras.importar_producto_existente(p_organizacion_id, f ->> 'producto');

    select pr.id into v_presentacion from compras.presentaciones pr
    where pr.producto_id = v_producto and lower(pr.nombre) = lower(btrim(f ->> 'presentacion'));
    if not found then
      raise exception 'NO_ENCONTRADO: "%" no tiene la presentación "%". Importá primero las presentaciones',
        btrim(f ->> 'producto'), btrim(f ->> 'presentacion') using errcode = 'P0002';
    end if;

    v_cuit := regexp_replace(coalesce(f ->> 'cuit', ''), '[^0-9]', '', 'g');
    select pr.id into v_proveedor from compras.proveedores pr
    where pr.organizacion_id = p_organizacion_id and pr.cuit = v_cuit;
    if not found then
      raise exception 'NO_ENCONTRADO: no existe el proveedor con CUIT %. Importá primero los proveedores', v_cuit
        using errcode = 'P0002';
    end if;

    -- Cada proveedor del producto es una fila: quien arma el pedido elige entre ellos.
    select pp.id into v_id from compras.producto_proveedor pp
    where pp.producto_id = v_producto and pp.proveedor_id = v_proveedor
      and pp.presentacion_id = v_presentacion;

    perform api.guardar_producto_proveedor(
      p_organizacion_id, coalesce(v_id, gen_random_uuid()), v_producto, v_proveedor, v_presentacion,
      (f ->> 'precio')::numeric, f ->> 'codigo_proveedor',
      coalesce((f ->> 'preferido')::boolean, false)
    );
  end if;

  return v_id is null;
end;
$$;

/** api.importar_catalogo — Importa filas de un tipo (rubros, categorias, productos,
 *  presentaciones, proveedores, precios). Sin p_aplicar, o con algún error, deshace todo
 *  y devuelve el diagnóstico por fila.
 *  Precondiciones: entre 1 y 5000 filas. Permisos: compras.catalogo.gestionar.
 *  Eventos: los de cada RPC de alta/edición, solo si se aplica. */
create function api.importar_catalogo(p_organizacion_id uuid, p_tipo text, p_filas jsonb, p_aplicar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.catalogo.gestionar');
  v_fila jsonb;
  v_indice int := 0;
  v_creados int := 0;
  v_actualizados int := 0;
  v_errores jsonb := '[]'::jsonb;
  v_aplicado boolean := true;
begin
  if p_tipo not in ('rubros', 'categorias', 'productos', 'presentaciones', 'proveedores', 'precios') then
    raise exception 'PRECONDICION: tipo de importación desconocido' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) = 0 then
    raise exception 'PRECONDICION: el archivo no tiene filas' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_filas) > 5000 then
    raise exception 'PRECONDICION: el archivo supera las 5000 filas: dividilo en partes' using errcode = 'P0001';
  end if;

  begin
    for v_fila in select value from jsonb_array_elements(p_filas) loop
      v_indice := v_indice + 1;
      begin
        if compras.importar_fila(v_m.organizacion_id, p_tipo, v_fila) then
          v_creados := v_creados + 1;
        else
          v_actualizados := v_actualizados + 1;
        end if;
      exception when others then
        v_errores := v_errores || jsonb_build_object(
          'fila', coalesce((v_fila ->> 'fila')::int, v_indice),
          'mensaje', regexp_replace(sqlerrm, '^[A-Z_]+:\s*', '')
        );
      end;
    end loop;

    if not p_aplicar or jsonb_array_length(v_errores) > 0 then
      raise exception 'deshacer' using errcode = 'ZZ000';
    end if;
  exception when sqlstate 'ZZ000' then
    v_aplicado := false;
  end;

  return jsonb_build_object(
    'filas', v_indice,
    'creados', v_creados,
    'actualizados', v_actualizados,
    'errores', v_errores,
    'aplicado', v_aplicado
  );
end;
$$;

/** api.catalogo_compras — Catálogo para armar pedidos en una sede: productos activos con
 *  sus ofertas, filtrado por los rubros del sector de la cuenta (si tiene).
 *  Permisos: compras.catalogo.ver en la sede. Eventos: ninguno. */
create function api.catalogo_compras(p_sede_id uuid)
returns table (
  producto_id uuid, sku text, nombre text, unidad_stock compras.unidad_stock, rubro_id uuid,
  rubro text, categoria_id uuid, categoria text, regla_modo compras.modo_regla,
  regla_monto_umbral numeric, ofertas jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select s.organizacion_id from nucleo.sedes s where s.id = p_sede_id), 'sede');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.catalogo.ver', p_sede_id);
  v_rubros uuid[];
begin
  -- Un sector solo restringe si tiene rubros asignados, y un rol sin sector no restringe.
  if not exists (
    select 1
    from nucleo.membresia_roles mr
    join nucleo.roles r on r.id = mr.rol_id and r.activo
    join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.catalogo.ver'
    where mr.membresia_id = v_m.id
      and (mr.sede_id is null or mr.sede_id = p_sede_id)
      and (
        mr.sector_id is null
        or not exists (select 1 from compras.sector_rubros sr where sr.sector_id = mr.sector_id)
      )
  ) then
    select array_agg(distinct sr.rubro_id) into v_rubros
    from nucleo.membresia_roles mr
    join compras.sector_rubros sr on sr.sector_id = mr.sector_id
    where mr.membresia_id = v_m.id and (mr.sede_id is null or mr.sede_id = p_sede_id);
  end if;

  return query
  select
    p.id, p.sku, p.nombre, p.unidad_stock, c.rubro_id, ru.nombre, p.categoria_id, c.nombre,
    regla.modo, regla.monto_umbral, o.ofertas
  from compras.productos p
  left join compras.categorias c on c.id = p.categoria_id
  left join compras.rubros ru on ru.id = c.rubro_id
  left join lateral compras.regla_producto(v_org, p.id) regla on true
  join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', pp.id,
        'proveedor_id', prov.id,
        'proveedor', prov.nombre,
        'proveedor_codigo', prov.codigo,
        'monto_minimo', prov.monto_minimo,
        'plazo_entrega_dias', prov.plazo_entrega_dias,
        'presentacion_id', pre.id,
        'presentacion', pre.nombre,
        'factor', pre.factor,
        'precio', pp.precio_actual,
        'preferido', pp.preferido
      )
      order by pp.preferido desc, pp.precio_actual asc nulls last, prov.nombre
    ) as ofertas
    from compras.producto_proveedor pp
    join compras.proveedores prov on prov.id = pp.proveedor_id and prov.activo
    join compras.presentaciones pre on pre.id = pp.presentacion_id and pre.activa
    where pp.producto_id = p.id and pp.activo
  ) o on o.ofertas is not null
  where p.organizacion_id = v_org
    and p.activo
    and not p.pendiente_validacion
    and coalesce(c.activo, true)
    and coalesce(ru.activo, true)
    and (v_rubros is null or c.rubro_id = any (v_rubros))
    and (p.sede_id is null or p.sede_id = p_sede_id)
  order by ru.nombre nulls last, c.nombre nulls last, p.nombre;
end;
$$;

-- ---------------------------------------------------------------------------
-- Aprobación
-- ---------------------------------------------------------------------------

/** api.guardar_regla_aprobacion — Crea o actualiza la regla de un alcance (empresa,
 *  rubro, categoría o producto).
 *  Precondiciones: alcance existente; monto válido si es por monto; nivel >= 1 y algún
 *    rol que apruebe en ese nivel si la regla exige aprobación.
 *  Permisos: compras.aprobacion.configurar. Eventos: regla_aprobacion/guardada. */
create function api.guardar_regla_aprobacion(
  p_organizacion_id uuid,
  p_alcance compras.alcance_regla,
  p_alcance_id uuid,
  p_modo compras.modo_regla,
  p_monto_umbral numeric default null,
  p_nivel_requerido int default 1,
  p_activa boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.aprobacion.configurar');
  v_org uuid := v_m.organizacion_id;
  v_umbral numeric := case when p_modo = 'POR_MONTO' then p_monto_umbral end;
  v_nivel int := case when p_modo = 'NUNCA' then 0 else p_nivel_requerido end;
  v_id uuid;
begin
  if p_alcance = 'EMPRESA' and p_alcance_id is not null then
    raise exception 'PRECONDICION: la regla de empresa no apunta a un rubro, categoría o producto'
      using errcode = 'P0001';
  end if;
  if p_alcance <> 'EMPRESA' and not exists (
    select 1 from compras.rubros x
    where p_alcance = 'RUBRO' and x.id = p_alcance_id and x.organizacion_id = v_org
    union all
    select 1 from compras.categorias x
    where p_alcance = 'CATEGORIA' and x.id = p_alcance_id and x.organizacion_id = v_org
    union all
    select 1 from compras.productos x
    where p_alcance = 'PRODUCTO' and x.id = p_alcance_id and x.organizacion_id = v_org
  ) then
    raise exception 'NO_ENCONTRADO: no existe a qué aplicar la regla' using errcode = 'P0002';
  end if;
  if p_modo = 'POR_MONTO' and (v_umbral is null or v_umbral < 0) then
    raise exception 'PRECONDICION: la regla por monto necesita un monto válido' using errcode = 'P0001';
  end if;
  if p_modo <> 'NUNCA' then
    if coalesce(v_nivel, 0) < 1 then
      raise exception 'PRECONDICION: la regla necesita un nivel de aprobación' using errcode = 'P0001';
    end if;
    -- Sin esto, las órdenes quedarían esperando a un aprobador que no existe.
    if p_activa and not exists (
      select 1 from nucleo.roles r
      join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
      where r.organizacion_id = v_org and r.activo and r.nivel_aprobacion >= v_nivel
    ) then
      raise exception 'PRECONDICION: ningún rol puede aprobar en el nivel %', v_nivel using errcode = 'P0001';
    end if;
  end if;

  insert into compras.reglas_aprobacion
    (organizacion_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido, activa)
  values
    (v_org, p_alcance, p_alcance_id, p_modo, v_umbral, v_nivel, p_activa)
  on conflict (organizacion_id, alcance, alcance_id) do update
    set modo = excluded.modo,
        monto_umbral = excluded.monto_umbral,
        nivel_requerido = excluded.nivel_requerido,
        activa = excluded.activa
  returning id into v_id;

  perform nucleo.registrar_evento(
    v_org, null, 'regla_aprobacion', v_id, 'guardada',
    jsonb_build_object(
      'alcance', p_alcance, 'alcance_id', p_alcance_id, 'modo', p_modo,
      'monto_umbral', v_umbral, 'nivel_requerido', v_nivel, 'activa', p_activa
    )
  );
  return v_id;
end;
$$;

/** api.fijar_autoaprobacion — Permite o no que alguien apruebe sus propias órdenes.
 *  Permisos: compras.aprobacion.configurar. Eventos: configuracion_compras/autoaprobacion. */
create function api.fijar_autoaprobacion(p_organizacion_id uuid, p_permitir boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.aprobacion.configurar');
begin
  insert into compras.configuracion (organizacion_id, permitir_autoaprobacion)
  values (v_m.organizacion_id, p_permitir)
  on conflict (organizacion_id) do update
    set permitir_autoaprobacion = excluded.permitir_autoaprobacion, actualizado_en = now();

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'configuracion_compras', v_m.organizacion_id, 'autoaprobacion',
    jsonb_build_object('permitir', p_permitir)
  );
end;
$$;

/** api.evaluar_aprobacion — Simula la aprobación de una OC antes de confirmar (no
 *  escribe). Permisos: compras.pedido.crear en la sede. Eventos: ninguno. */
create function api.evaluar_aprobacion(p_sede_id uuid, p_items jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select s.organizacion_id from nucleo.sedes s where s.id = p_sede_id), 'sede');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.pedido.crear', p_sede_id);
begin
  return compras.evaluar_aprobacion(v_org, v_m.cuenta_id, p_sede_id, p_items);
end;
$$;

/** api.bandeja_aprobacion — OC pendientes que la cuenta puede aprobar (nivel suficiente
 *  y, si la autoaprobación está apagada, que no sean propias).
 *  Permisos: compras.oc.aprobar. Eventos: ninguno. */
create function api.bandeja_aprobacion(p_organizacion_id uuid)
returns table (
  id uuid, numero text, sede text, proveedor text, emisor text, creado_en timestamptz,
  total_estimado numeric, nivel_requerido int, reglas_aplicadas jsonb, items jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'compras.oc.aprobar');
  v_autoaprobacion boolean := coalesce(
    (select c.permitir_autoaprobacion from compras.configuracion c where c.organizacion_id = p_organizacion_id),
    true
  );
begin
  return query
  select
    o.id, o.numero, s.nombre, pr.nombre, nucleo.nombre_cuenta(o.usuario_id), o.creado_en,
    o.total_estimado, o.nivel_requerido, o.reglas_aplicadas,
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'producto', i.producto_nombre, 'sku', i.sku, 'presentacion', i.presentacion_nombre,
        'cantidad', i.cantidad, 'subtotal', i.subtotal, 'disparo_aprobacion', i.disparo_aprobacion
      ) order by i.disparo_aprobacion desc, i.producto_nombre), '[]'::jsonb)
      from compras.oc_items i where i.oc_id = o.id
    )
  from compras.ordenes_compra o
  join nucleo.sedes s on s.id = o.sede_id
  join compras.proveedores pr on pr.id = o.proveedor_id
  where o.organizacion_id = p_organizacion_id
    and o.estado = 'PENDIENTE_APROBACION'
    and nucleo.nivel_aprobacion(p_organizacion_id, v_m.cuenta_id, o.sede_id) >= o.nivel_requerido
    and (v_autoaprobacion or o.usuario_id <> v_m.cuenta_id)
  order by o.creado_en;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pedidos y órdenes de compra
-- ---------------------------------------------------------------------------

/** api.confirmar_pedido — Confirma un pedido multiproveedor: una OC por proveedor, cada
 *  una evaluada contra las reglas de aprobación y numerada por sede. Idempotente por
 *  p_request_uuid (un reintento devuelve el mismo resumen con duplicada = true).
 *  Precondiciones: ítems con oferta vigente y cantidad > 0.
 *  Permisos: compras.pedido.crear en la sede.
 *  Eventos: orden_compra/creada (una por OC) y pedido/confirmado. */
create function api.confirmar_pedido(p_request_uuid uuid, p_sede_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select s.organizacion_id from nucleo.sedes s where s.id = p_sede_id), 'sede');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.pedido.crear', p_sede_id);
  v_pedido uuid;
  v_lineas jsonb;
  v_proveedor record;
  v_del_proveedor jsonb;
  v_evaluacion jsonb;
  v_oc uuid;
  v_numero text;
  v_estado compras.estado_oc;
  v_total numeric;
  v_no_disponible text;
begin
  if p_request_uuid is null then
    raise exception 'PRECONDICION: falta el identificador del pedido' using errcode = 'P0001';
  end if;

  insert into compras.pedidos_compra (organizacion_id, sede_id, usuario_id, request_uuid)
  values (v_org, p_sede_id, v_m.cuenta_id, p_request_uuid)
  on conflict (organizacion_id, request_uuid) do nothing
  returning id into v_pedido;

  if v_pedido is null then
    select p.id into v_pedido from compras.pedidos_compra p
    where p.organizacion_id = v_org and p.request_uuid = p_request_uuid;
    return compras.resumen_pedido(v_pedido) || jsonb_build_object('duplicada', true);
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'PRECONDICION: el pedido no tiene ítems' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where (i ->> 'cantidad') is null or (i ->> 'cantidad')::numeric <= 0
  ) then
    raise exception 'PRECONDICION: hay un ítem con una cantidad no válida' using errcode = 'P0001';
  end if;

  -- Un pedido hecho sin señal pudo quedar viejo: el catálogo se revisa al confirmar.
  select coalesce(pr.nombre, 'un producto') into v_no_disponible
  from jsonb_array_elements(p_items) i
  left join compras.producto_proveedor pp
    on pp.id = (i ->> 'oferta_id')::uuid and pp.organizacion_id = v_org
  left join compras.productos pr on pr.id = pp.producto_id
  left join compras.proveedores prov on prov.id = pp.proveedor_id
  left join compras.presentaciones pre on pre.id = pp.presentacion_id
  where pp.id is null or not (pp.activo and pr.activo and prov.activo and pre.activa)
  limit 1;
  if found then
    raise exception 'PRECONDICION: % ya no está disponible. Revisá el pedido', v_no_disponible
      using errcode = 'P0001';
  end if;

  select jsonb_agg(jsonb_build_object(
    'oferta_id', pp.id, 'cantidad', i.cantidad, 'producto_id', pr.id, 'proveedor_id', pp.proveedor_id,
    'presentacion_id', pre.id, 'presentacion', pre.nombre, 'factor', pre.factor,
    'precio', pp.precio_actual, 'nombre', pr.nombre, 'sku', pr.sku,
    'subtotal', round(coalesce(pp.precio_actual, 0) * i.cantidad, 2)
  ))
  into v_lineas
  from (
    select (e ->> 'oferta_id')::uuid as oferta_id, sum((e ->> 'cantidad')::numeric) as cantidad
    from jsonb_array_elements(p_items) e
    group by 1
  ) i
  join compras.producto_proveedor pp on pp.id = i.oferta_id
  join compras.productos pr on pr.id = pp.producto_id
  join compras.presentaciones pre on pre.id = pp.presentacion_id;

  insert into compras.pedido_items (organizacion_id, pedido_id, producto_proveedor_id, presentacion_id, cantidad)
  select v_org, v_pedido, (l ->> 'oferta_id')::uuid, (l ->> 'presentacion_id')::uuid,
    (l ->> 'cantidad')::numeric
  from jsonb_array_elements(v_lineas) l;

  for v_proveedor in
    select distinct pr.id, pr.nombre, pr.plazo_entrega_dias
    from jsonb_array_elements(v_lineas) l
    join compras.proveedores pr on pr.id = (l ->> 'proveedor_id')::uuid
    order by pr.nombre
  loop
    select jsonb_agg(l), sum((l ->> 'subtotal')::numeric)
    into v_del_proveedor, v_total
    from jsonb_array_elements(v_lineas) l
    where (l ->> 'proveedor_id')::uuid = v_proveedor.id;

    v_evaluacion := compras.evaluar_aprobacion(
      v_org, v_m.cuenta_id, p_sede_id,
      (select jsonb_agg(jsonb_build_object('producto_id', l -> 'producto_id', 'subtotal', l -> 'subtotal'))
       from jsonb_array_elements(v_del_proveedor) l)
    );
    v_estado := (v_evaluacion ->> 'estado')::compras.estado_oc;
    v_numero := compras.siguiente_numero_oc(v_org, p_sede_id);

    insert into compras.ordenes_compra (
      organizacion_id, sede_id, proveedor_id, numero, pedido_id, estado, usuario_id,
      requiere_aprobacion, nivel_requerido, tipo_aprobacion, aprobada_por, aprobada_en,
      reglas_aplicadas, fecha_entrega_estimada, total_estimado
    ) values (
      v_org, p_sede_id, v_proveedor.id, v_numero, v_pedido, v_estado, v_m.cuenta_id,
      (v_evaluacion ->> 'requiere_aprobacion')::boolean,
      (v_evaluacion ->> 'nivel_requerido')::int,
      (v_evaluacion ->> 'tipo_aprobacion')::compras.tipo_aprobacion,
      case when v_evaluacion ->> 'tipo_aprobacion' = 'AUTOAPROBADA' then v_m.cuenta_id end,
      case when v_estado = 'APROBADA' then now() end,
      v_evaluacion,
      (now() at time zone 'America/Argentina/Buenos_Aires')::date + v_proveedor.plazo_entrega_dias,
      v_total
    )
    returning id into v_oc;

    insert into compras.oc_items (
      organizacion_id, sede_id, oc_id, producto_id, cantidad, producto_proveedor_id, presentacion_id,
      producto_nombre, sku, presentacion_nombre, factor, precio_unitario, subtotal, disparo_aprobacion
    )
    select
      v_org, p_sede_id, v_oc, (l ->> 'producto_id')::uuid, (l ->> 'cantidad')::numeric,
      (l ->> 'oferta_id')::uuid, (l ->> 'presentacion_id')::uuid, l ->> 'nombre', l ->> 'sku',
      l ->> 'presentacion', (l ->> 'factor')::numeric, (l ->> 'precio')::numeric,
      (l ->> 'subtotal')::numeric, (v_evaluacion -> 'productos_disparadores') ? (l ->> 'producto_id')
    from jsonb_array_elements(v_del_proveedor) l;

    perform nucleo.registrar_evento(
      v_org, p_sede_id, 'orden_compra', v_oc, 'creada',
      jsonb_build_object(
        'numero', v_numero, 'pedido_id', v_pedido, 'proveedor_id', v_proveedor.id, 'total', v_total,
        'estado', v_estado, 'tipo_aprobacion', v_evaluacion ->> 'tipo_aprobacion',
        'nivel_requerido', v_evaluacion -> 'nivel_requerido'
      )
    );
  end loop;

  update compras.pedidos_compra set estado = 'CONFIRMADO', confirmado_en = now() where id = v_pedido;

  perform nucleo.registrar_evento(
    v_org, p_sede_id, 'pedido', v_pedido, 'confirmado',
    jsonb_build_object('request_uuid', p_request_uuid)
  );

  return compras.resumen_pedido(v_pedido) || jsonb_build_object('duplicada', false);
end;
$$;

/** api.aprobar_oc — Aprueba una OC pendiente. Idempotente.
 *  Precondiciones: OC en PENDIENTE_APROBACION; nivel suficiente; autoaprobación según
 *    configuración. Permisos: compras.oc.aprobar en la sede de la OC.
 *  Eventos: orden_compra/estado:APROBADA. */
create function api.aprobar_oc(p_oc_id uuid)
returns compras.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc compras.ordenes_compra := compras.exigir_oc_para_decidir(p_oc_id);
begin
  if v_oc.estado = 'APROBADA' then
    return v_oc.estado;
  end if;

  perform compras.cambiar_estado_oc(v_oc, 'APROBADA', jsonb_build_object('tipo_aprobacion', 'MANUAL'));
  update compras.ordenes_compra
  set tipo_aprobacion = 'MANUAL', aprobada_por = auth.uid(), aprobada_en = now()
  where id = p_oc_id;
  return 'APROBADA';
end;
$$;

/** api.rechazar_oc — Rechaza una OC pendiente con motivo. Idempotente.
 *  Permisos: compras.oc.aprobar en la sede, con nivel suficiente.
 *  Eventos: orden_compra/estado:RECHAZADA. */
create function api.rechazar_oc(p_oc_id uuid, p_motivo text)
returns compras.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc compras.ordenes_compra := compras.exigir_oc_para_decidir(p_oc_id);
begin
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: rechazar requiere un motivo' using errcode = 'P0001';
  end if;
  if v_oc.estado = 'RECHAZADA' then
    return v_oc.estado;
  end if;

  perform compras.cambiar_estado_oc(v_oc, 'RECHAZADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update compras.ordenes_compra set motivo_rechazo = btrim(p_motivo) where id = p_oc_id;
  return 'RECHAZADA';
end;
$$;

/** api.anular_oc — Anula una OC aprobada o enviada, con motivo. Idempotente.
 *  Precondiciones: sin recepciones (salvo rechazadas).
 *  Permisos: compras.oc.anular en la sede. Eventos: orden_compra/estado:ANULADA. */
create function api.anular_oc(p_oc_id uuid, p_motivo text)
returns compras.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc compras.ordenes_compra := compras.exigir_oc_con_permiso(p_oc_id, 'compras.oc.anular');
begin
  if v_oc.estado = 'ANULADA' then
    return v_oc.estado;  -- reintento
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: anular requiere un motivo' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from recepcion.recepciones r
    where r.oc_id = p_oc_id and r.estado <> 'RECHAZADA'
  ) then
    raise exception 'PRECONDICION: la orden % ya tiene recepciones: no se puede anular', v_oc.numero
      using errcode = 'P0001';
  end if;

  perform compras.cambiar_estado_oc(v_oc, 'ANULADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update compras.ordenes_compra set motivo_cierre = btrim(p_motivo) where id = p_oc_id;
  return 'ANULADA';
end;
$$;

/** api.cerrar_saldo_oc — Cierra el saldo de una OC recibida en parte.
 *  Precondiciones: OC en RECIBIDA_PARCIAL; motivo; sin recepciones en curso.
 *  Permisos: compras.oc.cerrar_saldo en la sede. Eventos: orden_compra/estado:CERRADA. */
create function api.cerrar_saldo_oc(p_oc_id uuid, p_motivo text)
returns compras.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc compras.ordenes_compra := compras.exigir_oc_con_permiso(p_oc_id, 'compras.oc.cerrar_saldo');
begin
  if v_oc.estado = 'CERRADA' then
    return v_oc.estado;  -- reintento
  end if;
  if v_oc.estado <> 'RECIBIDA_PARCIAL' then
    raise exception 'PRECONDICION: solo se cierra el saldo de una orden recibida en parte (la % está en %)',
      v_oc.numero, v_oc.estado using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: cerrar el saldo requiere un motivo' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from recepcion.recepciones r
    where r.oc_id = p_oc_id and r.estado in ('ABIERTA', 'EN_CONTROL', 'RECHAZADA')
  ) then
    raise exception 'PRECONDICION: la orden % tiene una recepción en curso: terminala antes de cerrar el saldo', v_oc.numero
      using errcode = 'P0001';
  end if;

  perform compras.cambiar_estado_oc(v_oc, 'CERRADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update compras.ordenes_compra set motivo_cierre = btrim(p_motivo) where id = p_oc_id;
  return 'CERRADA';
end;
$$;

/** api.marcar_oc_enviada — Marca una OC aprobada como enviada al proveedor. Idempotente.
 *  Permisos: compras.oc.ver_todas en la sede, o ser quien la emitió con
 *    compras.pedido.crear. Eventos: orden_compra/estado:ENVIADA. */
create function api.marcar_oc_enviada(p_oc_id uuid, p_canal compras.canal_envio default 'MANUAL')
returns compras.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select o.organizacion_id from compras.ordenes_compra o where o.id = p_oc_id), 'orden de compra');
  v_oc compras.ordenes_compra;
begin
  select * into v_oc from compras.ordenes_compra o
  where o.id = p_oc_id and o.organizacion_id = v_org
  for update;

  if not (
    nucleo.tiene_permiso(v_org, 'compras.oc.ver_todas', v_oc.sede_id)
    or (v_oc.usuario_id = auth.uid() and nucleo.tiene_permiso(v_org, 'compras.pedido.crear', v_oc.sede_id))
  ) then
    raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
  end if;

  if v_oc.estado in ('ENVIADA', 'RECIBIDA_PARCIAL', 'RECIBIDA', 'CERRADA') then
    return v_oc.estado;  -- reintento
  end if;

  perform compras.cambiar_estado_oc(v_oc, 'ENVIADA', jsonb_build_object('canal', p_canal));
  update compras.ordenes_compra set enviada_en = now(), canal_envio = p_canal where id = p_oc_id;
  return 'ENVIADA';
end;
$$;
