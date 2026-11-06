-- Eskemia · Importación CSV del catálogo (plan de Compras, etapa 3).
-- Las filas se identifican por nombre o CUIT y pasan por las RPC guardar_*, que validan y dejan evento.

create function app_private.importar_producto(p_tenant_id uuid, p_nombre text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cantidad int;
  v_id uuid;
begin
  select count(*), min(pr.id::text)::uuid into v_cantidad, v_id
  from public.productos pr
  where pr.tenant_id = p_tenant_id and lower(pr.nombre) = lower(btrim(p_nombre));

  if v_cantidad > 1 then
    raise exception 'PRECONDICION: hay % productos llamados "%"', v_cantidad, btrim(p_nombre)
      using errcode = 'P0001';
  end if;
  return v_id;
end;
$$;

create function app_private.importar_producto_existente(p_tenant_id uuid, p_nombre text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid := app_private.importar_producto(p_tenant_id, p_nombre);
begin
  if v_id is null then
    raise exception 'NO_ENCONTRADO: no existe el producto "%". Importá primero los productos', btrim(p_nombre)
      using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;

create function app_private.importar_rubro_existente(p_tenant_id uuid, p_nombre text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select r.id into v_id from public.rubros r
  where r.tenant_id = p_tenant_id and lower(r.nombre) = lower(btrim(p_nombre));
  if not found then
    raise exception 'NO_ENCONTRADO: no existe el rubro "%". Importá primero los rubros', btrim(p_nombre)
      using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;

-- Procesa una fila. Devuelve true si creó el registro y false si lo actualizó.
create function app_private.importar_fila(p_tenant_id uuid, p_tipo text, f jsonb)
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
  v_tipo public.tipo_codigo;
  v_cuit text;
begin
  if p_tipo = 'rubros' then
    select r.id into v_id from public.rubros r
    where r.tenant_id = p_tenant_id and lower(r.nombre) = lower(btrim(f ->> 'rubro'));

    perform public.guardar_rubro(
      coalesce(v_id, gen_random_uuid()), f ->> 'rubro', coalesce((f ->> 'orden')::int, 0)
    );

  elsif p_tipo = 'categorias' then
    v_rubro := app_private.importar_rubro_existente(p_tenant_id, f ->> 'rubro');

    -- Una categoría anterior a los rubros se adopta en lugar de duplicarse.
    select c.id into v_id from public.categorias c
    where c.tenant_id = p_tenant_id
      and (c.rubro_id = v_rubro or c.rubro_id is null)
      and lower(c.nombre) = lower(btrim(f ->> 'categoria'))
    order by c.rubro_id nulls last
    limit 1;

    perform public.guardar_categoria(
      coalesce(v_id, gen_random_uuid()), v_rubro, f ->> 'categoria', coalesce((f ->> 'orden')::int, 0)
    );

  elsif p_tipo = 'productos' then
    v_rubro := app_private.importar_rubro_existente(p_tenant_id, f ->> 'rubro');

    select c.id into v_categoria from public.categorias c
    where c.tenant_id = p_tenant_id and c.rubro_id = v_rubro
      and lower(c.nombre) = lower(btrim(f ->> 'categoria'));
    if not found then
      raise exception 'NO_ENCONTRADO: el rubro "%" no tiene la categoría "%". Importá primero las categorías',
        btrim(f ->> 'rubro'), btrim(f ->> 'categoria') using errcode = 'P0002';
    end if;

    v_id := app_private.importar_producto(p_tenant_id, f ->> 'producto');
    perform public.guardar_producto(
      coalesce(v_id, gen_random_uuid()), v_categoria, f ->> 'producto',
      (f ->> 'unidad')::public.unidad_stock,
      coalesce((f ->> 'requiere_lote')::boolean, false),
      coalesce((f ->> 'requiere_vencimiento')::boolean, false)
    );

  elsif p_tipo = 'presentaciones' then
    v_producto := app_private.importar_producto_existente(p_tenant_id, f ->> 'producto');

    select pr.id into v_id from public.presentaciones pr
    where pr.producto_id = v_producto and lower(pr.nombre) = lower(btrim(f ->> 'presentacion'));

    v_presentacion := public.guardar_presentacion(
      coalesce(v_id, gen_random_uuid()), v_producto, f ->> 'presentacion', (f ->> 'factor')::numeric
    );

    if nullif(btrim(f ->> 'codigo'), '') is not null then
      v_tipo := (f ->> 'tipo_codigo')::public.tipo_codigo;
      -- Un código ajeno no se reasigna: guardar_codigo lo rechaza por repetido.
      select c.id into v_codigo from public.producto_codigos c
      where c.tenant_id = p_tenant_id
        and c.producto_id = v_producto
        and c.codigo_busqueda = case
          when v_tipo in ('EAN13', 'EAN8', 'DUN14', 'UPC') then lpad(btrim(f ->> 'codigo'), 14, '0')
          else btrim(f ->> 'codigo')
        end;
      perform public.guardar_codigo(
        coalesce(v_codigo, gen_random_uuid()), v_producto, v_presentacion, f ->> 'codigo', v_tipo
      );
    end if;

  elsif p_tipo = 'proveedores' then
    v_cuit := regexp_replace(coalesce(f ->> 'cuit', ''), '[^0-9]', '', 'g');
    select pr.id into v_id from public.proveedores pr
    where pr.tenant_id = p_tenant_id and pr.cuit = v_cuit;

    perform public.guardar_proveedor(
      coalesce(v_id, gen_random_uuid()), f ->> 'proveedor', v_cuit,
      f ->> 'contacto', f ->> 'telefono_whatsapp', f ->> 'email',
      coalesce((f ->> 'canal_envio')::public.canal_envio, 'MANUAL'),
      (f ->> 'plazo_entrega_dias')::int,
      (select array_agg(d::int) from jsonb_array_elements_text(
        case when jsonb_typeof(f -> 'dias_pedido') = 'array' then f -> 'dias_pedido' else '[]'::jsonb end
      ) as d),
      (f ->> 'monto_minimo')::numeric
    );

  elsif p_tipo = 'precios' then
    v_producto := app_private.importar_producto_existente(p_tenant_id, f ->> 'producto');

    select pr.id into v_presentacion from public.presentaciones pr
    where pr.producto_id = v_producto and lower(pr.nombre) = lower(btrim(f ->> 'presentacion'));
    if not found then
      raise exception 'NO_ENCONTRADO: "%" no tiene la presentación "%". Importá primero las presentaciones',
        btrim(f ->> 'producto'), btrim(f ->> 'presentacion') using errcode = 'P0002';
    end if;

    v_cuit := regexp_replace(coalesce(f ->> 'cuit', ''), '[^0-9]', '', 'g');
    select pr.id into v_proveedor from public.proveedores pr
    where pr.tenant_id = p_tenant_id and pr.cuit = v_cuit;
    if not found then
      raise exception 'NO_ENCONTRADO: no existe el proveedor con CUIT %. Importá primero los proveedores', v_cuit
        using errcode = 'P0002';
    end if;

    -- Cada proveedor del producto es una fila: quien arma el pedido elige entre ellos.
    select pp.id into v_id from public.producto_proveedor pp
    where pp.producto_id = v_producto and pp.proveedor_id = v_proveedor
      and pp.presentacion_id = v_presentacion;

    perform public.guardar_producto_proveedor(
      coalesce(v_id, gen_random_uuid()), v_producto, v_proveedor, v_presentacion,
      (f ->> 'precio')::numeric, f ->> 'codigo_proveedor',
      coalesce((f ->> 'preferido')::boolean, false)
    );
  end if;

  return v_id is null;
end;
$$;

-- Todo o nada: se ejecuta de verdad y se deshace si hay errores o si es una vista previa,
-- así la vista previa ve lo mismo que la carga, incluidas las filas anteriores del archivo.
create function public.importar_catalogo(p_tipo text, p_filas jsonb, p_aplicar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
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
        if app_private.importar_fila(v_perfil.tenant_id, p_tipo, v_fila) then
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

revoke all on function app_private.importar_producto(uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.importar_producto_existente(uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.importar_rubro_existente(uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.importar_fila(uuid, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.importar_catalogo(text, jsonb, boolean) from public, anon, authenticated, service_role;
grant execute on function public.importar_catalogo(text, jsonb, boolean) to authenticated;
