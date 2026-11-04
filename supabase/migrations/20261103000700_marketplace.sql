-- Eskemia · Marketplace de Compras (plan de Compras, etapa 5).
-- Identificadores de negocio y catálogo para el celular.

-- sku y codigo (el "ID" del proveedor) son los identificadores que usará la empresa.
-- id sigue siendo la clave técnica. Nulos hasta que se carguen.
alter table public.productos
  add column sku text check (btrim(sku) <> ''),
  add unique (tenant_id, sku);

alter table public.proveedores
  add column codigo text check (btrim(codigo) <> ''),
  add unique (tenant_id, codigo);

create function public.fijar_sku_producto(p_producto_id uuid, p_sku text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
  v_sku text := nullif(btrim(p_sku), '');
begin
  update public.productos p set sku = v_sku
  where p.id = p_producto_id and p.tenant_id = v_perfil.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'producto', p_producto_id, 'sku', jsonb_build_object('sku', v_sku)
  );
exception when unique_violation then
  raise exception 'PRECONDICION: ese SKU ya está asignado a otro producto' using errcode = 'P0001';
end;
$$;

create function public.fijar_codigo_proveedor(p_proveedor_id uuid, p_codigo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
  v_codigo text := nullif(btrim(p_codigo), '');
begin
  update public.proveedores p set codigo = v_codigo
  where p.id = p_proveedor_id and p.tenant_id = v_perfil.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: proveedor inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'proveedor', p_proveedor_id, 'codigo', jsonb_build_object('codigo', v_codigo)
  );
exception when unique_violation then
  raise exception 'PRECONDICION: ese ID ya está asignado a otro proveedor' using errcode = 'P0001';
end;
$$;

-- Único lugar donde se decide qué regla le toca a un producto.
create function app_private.regla_producto(p_tenant_id uuid, p_producto_id uuid)
returns public.reglas_aprobacion
language sql
stable
security definer
set search_path = ''
as $$
  select ra.*
  from public.productos p
  left join public.categorias c on c.id = p.categoria_id
  join public.reglas_aprobacion ra on ra.tenant_id = p_tenant_id
    and ra.activa
    and (
      (ra.alcance = 'PRODUCTO' and ra.alcance_id = p.id)
      or (ra.alcance = 'CATEGORIA' and ra.alcance_id = c.id)
      or (ra.alcance = 'RUBRO' and ra.alcance_id = c.rubro_id)
      or ra.alcance = 'EMPRESA'
    )
  where p.id = p_producto_id
  order by case ra.alcance
    when 'PRODUCTO' then 1 when 'CATEGORIA' then 2 when 'RUBRO' then 3 else 4
  end
  limit 1;
$$;

create or replace function app_private.evaluar_aprobacion(
  p_tenant_id uuid,
  p_user_id uuid,
  p_sede_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total numeric;
  v_reglas jsonb;
  v_nivel int;
  v_disparadores jsonb;
  v_algun_sin_limite boolean;
  v_limite numeric;
  v_excede_limite boolean := false;
  v_nivel_usuario int;
  v_autoaprobacion boolean;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'PRECONDICION: la orden no tiene ítems' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where (i ->> 'subtotal') is null or (i ->> 'subtotal')::numeric < 0
  ) then
    raise exception 'PRECONDICION: hay un ítem sin subtotal válido' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where not exists (
      select 1 from public.productos p
      where p.id = (i ->> 'producto_id')::uuid and p.tenant_id = p_tenant_id
    )
  ) then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  select sum((i ->> 'subtotal')::numeric) into v_total from jsonb_array_elements(p_items) i;

  with items as (
    select (i ->> 'producto_id')::uuid as producto_id, (i ->> 'subtotal')::numeric as subtotal
    from jsonb_array_elements(p_items) i
  ),
  resueltos as (
    select i.producto_id, i.subtotal, r.id as regla_id, r.alcance, r.alcance_id, r.modo,
           r.monto_umbral, r.nivel_requerido
    from items i
    join public.productos p on p.id = i.producto_id
    left join lateral app_private.regla_producto(p_tenant_id, p.id) r on true
    where r.id is not null
  ),
  grupos as (
    select regla_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido,
           sum(subtotal) as subtotal, jsonb_agg(distinct producto_id) as productos
    from resueltos
    group by regla_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido
  ),
  disparadas as (
    select * from grupos g
    where g.modo = 'SIEMPRE' or (g.modo = 'POR_MONTO' and g.subtotal > g.monto_umbral)
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'regla_id', d.regla_id, 'alcance', d.alcance, 'alcance_id', d.alcance_id, 'modo', d.modo,
      'monto_umbral', d.monto_umbral, 'nivel_requerido', d.nivel_requerido,
      'subtotal', d.subtotal, 'productos', d.productos
    )), '[]'::jsonb),
    coalesce(max(d.nivel_requerido), 0),
    coalesce((select jsonb_agg(distinct x) from disparadas d2, jsonb_array_elements(d2.productos) x), '[]'::jsonb)
  into v_reglas, v_nivel, v_disparadores
  from disparadas d;

  -- Límite del perfil: solo cuentan los roles con los que puede pedir en esa sede. Vale el más
  -- permisivo, y un rol sin límite propio no le impone ninguno.
  select bool_or(r.limite_monto_sin_aprobacion is null), max(r.limite_monto_sin_aprobacion)
  into v_algun_sin_limite, v_limite
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.pedido.crear'
  where ur.user_id = p_user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);

  if v_algun_sin_limite is false and v_total > v_limite then
    v_excede_limite := true;
    v_nivel := greatest(v_nivel, 1);
  end if;

  select coalesce(max(r.nivel_aprobacion), 0) into v_nivel_usuario
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
  where ur.user_id = p_user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);

  select coalesce(
    (select ce.permitir_autoaprobacion from public.configuracion_empresa ce where ce.tenant_id = p_tenant_id),
    true
  ) into v_autoaprobacion;

  return jsonb_build_object(
    'total', v_total,
    'requiere_aprobacion', v_nivel > 0,
    'nivel_requerido', v_nivel,
    'estado', case
      when v_nivel = 0 then 'APROBADA'
      when v_autoaprobacion and v_nivel_usuario >= v_nivel then 'APROBADA'
      else 'PENDIENTE_APROBACION'
    end,
    'tipo_aprobacion', case
      when v_nivel = 0 then 'AUTOMATICA'
      when v_autoaprobacion and v_nivel_usuario >= v_nivel then 'AUTOAPROBADA'
    end,
    'nivel_usuario', v_nivel_usuario,
    'excede_limite_rol', v_excede_limite,
    'limite_rol', case when v_excede_limite then v_limite end,
    'productos_disparadores', v_disparadores,
    'reglas_aplicadas', v_reglas
  );
end;
$$;

-- Todo el catálogo que el usuario puede pedir, de una vez: el celular lo guarda para abrir sin
-- señal y busca localmente. Cada oferta es un proveedor con su presentación: si hay varias,
-- elige quien arma el pedido. El orden solo pone primero a la preferida.
create function public.catalogo_compras(p_sede_id uuid)
returns table (
  producto_id uuid,
  sku text,
  nombre text,
  unidad_stock public.unidad_stock,
  rubro_id uuid,
  rubro text,
  categoria_id uuid,
  categoria text,
  regla_modo public.modo_regla,
  regla_monto_umbral numeric,
  ofertas jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.ver', p_sede_id);
  v_rubros uuid[];
begin
  -- Un sector solo restringe si tiene rubros asignados, y un rol sin sector no restringe.
  if not exists (
    select 1
    from public.usuario_roles ur
    join public.roles r on r.id = ur.rol_id and r.activo
    join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.catalogo.ver'
    where ur.user_id = v_perfil.user_id
      and (ur.sede_id is null or ur.sede_id = p_sede_id)
      and (
        ur.sector_id is null
        or not exists (select 1 from public.sector_rubros sr where sr.sector_id = ur.sector_id)
      )
  ) then
    select array_agg(distinct sr.rubro_id) into v_rubros
    from public.usuario_roles ur
    join public.sector_rubros sr on sr.sector_id = ur.sector_id
    where ur.user_id = v_perfil.user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);
  end if;

  return query
  select
    p.id, p.sku, p.nombre, p.unidad_stock, c.rubro_id, ru.nombre, p.categoria_id, c.nombre,
    regla.modo, regla.monto_umbral, o.ofertas
  from public.productos p
  left join public.categorias c on c.id = p.categoria_id
  left join public.rubros ru on ru.id = c.rubro_id
  left join lateral app_private.regla_producto(v_perfil.tenant_id, p.id) regla on true
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
    from public.producto_proveedor pp
    join public.proveedores prov on prov.id = pp.proveedor_id and prov.activo
    join public.presentaciones pre on pre.id = pp.presentacion_id and pre.activa
    where pp.producto_id = p.id and pp.activo
  ) o on o.ofertas is not null
  where p.tenant_id = v_perfil.tenant_id
    and p.activo
    and not p.pendiente_validacion
    and coalesce(c.activo, true)
    and coalesce(ru.activo, true)
    and (v_rubros is null or c.rubro_id = any (v_rubros))
    and (p.sede_id is null or p.sede_id = p_sede_id)
  order by ru.nombre nulls last, c.nombre nulls last, p.nombre;
end;
$$;

revoke all on function app_private.regla_producto(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.fijar_sku_producto(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.fijar_codigo_proveedor(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.catalogo_compras(uuid) from public, anon, authenticated, service_role;
grant execute on function public.fijar_sku_producto(uuid, text) to authenticated;
grant execute on function public.fijar_codigo_proveedor(uuid, text) to authenticated;
grant execute on function public.catalogo_compras(uuid) to authenticated;
