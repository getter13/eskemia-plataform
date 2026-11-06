-- Eskemia · Línea base v1 · 08: funciones internas de Compras.
--
-- Qué hace: transiciones de OC, reglas y evaluación de aprobación, numeración, resumen
-- de pedido, recálculo de estado por recepciones, guardas de OC y ayudantes de
-- importación.
-- Dónde encaja: port de app_private.* del legado. Las que antes leían el perfil único
-- ahora reciben la organización o la toman de la OC.

/** Nombre visible de una cuenta: "Nombre Apellido" o, si no cargó nombre, su email. */
create function nucleo.nombre_cuenta(p_cuenta_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellido)), ''), u.email)
  from auth.users u
  left join nucleo.cuentas c on c.id = u.id
  where u.id = p_cuenta_id;
$$;

/** Cambia el estado de una OC validando la transición y escribe el evento
 *  orden_compra/estado:<nuevo>. */
create function compras.cambiar_estado_oc(p_oc compras.ordenes_compra, p_nuevo compras.estado_oc, p_payload jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    (p_oc.estado = 'PENDIENTE_APROBACION' and p_nuevo in ('APROBADA', 'RECHAZADA'))
    or (p_oc.estado = 'APROBADA' and p_nuevo in ('ENVIADA', 'ANULADA'))
    or (p_oc.estado = 'ENVIADA' and p_nuevo in ('RECIBIDA_PARCIAL', 'RECIBIDA', 'ANULADA'))
    or (p_oc.estado = 'RECIBIDA_PARCIAL' and p_nuevo in ('RECIBIDA', 'CERRADA'))
    or (p_oc.estado = 'RECIBIDA' and p_nuevo = 'CERRADA')
  ) then
    raise exception 'PRECONDICION: transición inválida de % a %', p_oc.estado, p_nuevo
      using errcode = 'P0001';
  end if;

  update compras.ordenes_compra set estado = p_nuevo where id = p_oc.id;

  perform nucleo.registrar_evento(
    p_oc.organizacion_id, p_oc.sede_id, 'orden_compra', p_oc.id, 'estado:' || p_nuevo::text,
    jsonb_build_object('desde', p_oc.estado, 'hasta', p_nuevo, 'numero', p_oc.numero) || p_payload
  );
end;
$$;

/** Regla de aprobación que aplica a un producto: la más específica entre producto,
 *  categoría, rubro y empresa. */
create function compras.regla_producto(p_organizacion_id uuid, p_producto_id uuid)
returns compras.reglas_aprobacion
language sql
stable
security definer
set search_path = ''
as $$
  select ra.*
  from compras.productos p
  left join compras.categorias c on c.id = p.categoria_id
  join compras.reglas_aprobacion ra on ra.organizacion_id = p_organizacion_id
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

/** Evalúa si una OC (ítems con producto_id y subtotal) requiere aprobación, con qué
 *  nivel, y si la cuenta la autoaprueba. No escribe nada. */
create function compras.evaluar_aprobacion(p_organizacion_id uuid, p_cuenta_id uuid, p_sede_id uuid, p_items jsonb)
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
      select 1 from compras.productos p
      where p.id = (i ->> 'producto_id')::uuid and p.organizacion_id = p_organizacion_id
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
    join compras.productos p on p.id = i.producto_id
    left join lateral compras.regla_producto(p_organizacion_id, p.id) r on true
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

  -- Límite: solo cuentan los roles con los que puede pedir en esa sede. Vale el más
  -- permisivo, y un rol sin límite propio no le impone ninguno.
  select bool_or(r.limite_monto_sin_aprobacion is null), max(r.limite_monto_sin_aprobacion)
  into v_algun_sin_limite, v_limite
  from nucleo.membresias m
  join nucleo.membresia_roles mr on mr.membresia_id = m.id
  join nucleo.roles r on r.id = mr.rol_id and r.activo
  join nucleo.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.pedido.crear'
  where m.organizacion_id = p_organizacion_id and m.cuenta_id = p_cuenta_id
    and (mr.sede_id is null or mr.sede_id = p_sede_id);

  if v_algun_sin_limite is false and v_total > v_limite then
    v_excede_limite := true;
    v_nivel := greatest(v_nivel, 1);
  end if;

  v_nivel_usuario := nucleo.nivel_aprobacion(p_organizacion_id, p_cuenta_id, p_sede_id);

  select coalesce(
    (select c.permitir_autoaprobacion from compras.configuracion c where c.organizacion_id = p_organizacion_id),
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

/** Próximo número de OC por sede y año: OC-<codigo sede>-<año>-<000001>. */
create function compras.siguiente_numero_oc(p_organizacion_id uuid, p_sede_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anio int := extract(year from now() at time zone 'America/Argentina/Buenos_Aires');
  v_numero bigint;
  v_codigo text;
begin
  insert into compras.secuencias (organizacion_id, sede_id, tipo, anio, ultimo_numero)
  values (p_organizacion_id, p_sede_id, 'OC', v_anio, 1)
  on conflict (organizacion_id, sede_id, tipo, anio) do update
    set ultimo_numero = compras.secuencias.ultimo_numero + 1
  returning ultimo_numero into v_numero;

  select coalesce(s.codigo, 'S' || upper(left(s.id::text, 4))) into v_codigo
  from nucleo.sedes s where s.id = p_sede_id;

  return 'OC-' || v_codigo || '-' || v_anio || '-' || lpad(v_numero::text, 6, '0');
end;
$$;

/** Resumen de un pedido confirmado: sus órdenes por proveedor. */
create function compras.resumen_pedido(p_pedido_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'pedido_id', p_pedido_id,
    'ordenes', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', o.id, 'numero', o.numero, 'estado', o.estado,
        'proveedor', pr.nombre, 'total_estimado', o.total_estimado
      ) order by o.numero
    ), '[]'::jsonb)
  )
  from compras.ordenes_compra o
  join compras.proveedores pr on pr.id = o.proveedor_id
  where o.pedido_id = p_pedido_id;
$$;

/** Recalcula el estado de una OC según lo recibido (lo llaman las RPC de Recepción).
 *  Escribe orden_compra/estado:<nuevo> con origen recepcion si cambia. */
create function compras.recalcular_estado_oc(p_oc_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc compras.ordenes_compra;
  v_recibido numeric;
  v_con_saldo boolean;
  v_nuevo compras.estado_oc;
begin
  if p_oc_id is null then
    return;
  end if;
  select * into v_oc from compras.ordenes_compra o where o.id = p_oc_id for update;
  if not found or v_oc.estado not in ('APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL', 'RECIBIDA') then
    return;
  end if;

  select sum(s.cant_recibida), bool_or(s.cant_recibida < s.cant_pedida)
  into v_recibido, v_con_saldo
  from compras.v_oc_saldos s where s.oc_id = p_oc_id;

  v_nuevo := case
    when coalesce(v_recibido, 0) = 0 then
      case when v_oc.enviada_en is not null then 'ENVIADA' else 'APROBADA' end::compras.estado_oc
    when v_con_saldo then 'RECIBIDA_PARCIAL'::compras.estado_oc
    else 'RECIBIDA'::compras.estado_oc
  end;
  if v_nuevo = v_oc.estado then
    return;
  end if;

  update compras.ordenes_compra set estado = v_nuevo where id = p_oc_id;
  perform nucleo.registrar_evento(
    v_oc.organizacion_id, v_oc.sede_id, 'orden_compra', v_oc.id, 'estado:' || v_nuevo::text,
    jsonb_build_object('desde', v_oc.estado, 'hasta', v_nuevo, 'numero', v_oc.numero, 'origen', 'recepcion')
  );
end;
$$;

/** Bloquea y devuelve la OC si la cuenta tiene el permiso en su sede.
 *  NO_ENCONTRADO si es de otra organización; SIN_PERMISO si falta el permiso. */
create function compras.exigir_oc_con_permiso(p_oc_id uuid, p_permiso text)
returns compras.ordenes_compra
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select o.organizacion_id from compras.ordenes_compra o where o.id = p_oc_id), 'orden de compra');
  v_oc compras.ordenes_compra;
begin
  select * into v_oc from compras.ordenes_compra o where o.id = p_oc_id and o.organizacion_id = v_org
  for update;
  if not nucleo.tiene_permiso(v_org, p_permiso, v_oc.sede_id) then
    perform nucleo.exigir_permiso(v_org, p_permiso);  -- informa módulo deshabilitado
    raise exception 'SIN_PERMISO: falta el permiso %', p_permiso using errcode = '42501';
  end if;
  return v_oc;
end;
$$;

/** Bloquea y devuelve la OC a aprobar o rechazar por la cuenta actual: exige
 *  compras.oc.aprobar en su sede, nivel suficiente y respeta la autoaprobación. */
create function compras.exigir_oc_para_decidir(p_oc_id uuid)
returns compras.ordenes_compra
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select o.organizacion_id from compras.ordenes_compra o where o.id = p_oc_id), 'orden de compra');
  v_membresia nucleo.membresias := nucleo.exigir_permiso(v_org, 'compras.oc.aprobar');
  v_oc compras.ordenes_compra;
begin
  select * into v_oc from compras.ordenes_compra o where o.id = p_oc_id and o.organizacion_id = v_org
  for update;
  if not nucleo.tiene_permiso(v_org, 'compras.oc.aprobar', v_oc.sede_id) then
    raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
  end if;
  if nucleo.nivel_aprobacion(v_org, v_membresia.cuenta_id, v_oc.sede_id) < v_oc.nivel_requerido then
    raise exception 'SIN_PERMISO: esta orden requiere nivel de aprobación %', v_oc.nivel_requerido
      using errcode = '42501';
  end if;
  if v_oc.usuario_id = v_membresia.cuenta_id and not coalesce(
    (select c.permitir_autoaprobacion from compras.configuracion c where c.organizacion_id = v_org),
    true
  ) then
    raise exception 'SIN_PERMISO: en esta empresa nadie aprueba sus propias órdenes' using errcode = '42501';
  end if;
  return v_oc;
end;
$$;

-- Ayudantes de importación ------------------------------------------------------

/** Id del producto con ese nombre (sin distinguir mayúsculas), o nulo. Falla si hay
 *  más de uno. */
create function compras.importar_producto(p_organizacion_id uuid, p_nombre text)
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
  from compras.productos pr
  where pr.organizacion_id = p_organizacion_id and lower(pr.nombre) = lower(btrim(p_nombre));

  if v_cantidad > 1 then
    raise exception 'PRECONDICION: hay % productos llamados "%"', v_cantidad, btrim(p_nombre)
      using errcode = 'P0001';
  end if;
  return v_id;
end;
$$;

/** Como importar_producto, pero el producto tiene que existir. */
create function compras.importar_producto_existente(p_organizacion_id uuid, p_nombre text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid := compras.importar_producto(p_organizacion_id, p_nombre);
begin
  if v_id is null then
    raise exception 'NO_ENCONTRADO: no existe el producto "%". Importá primero los productos', btrim(p_nombre)
      using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;

/** Id del rubro con ese nombre; tiene que existir. */
create function compras.importar_rubro_existente(p_organizacion_id uuid, p_nombre text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select r.id into v_id from compras.rubros r
  where r.organizacion_id = p_organizacion_id and lower(r.nombre) = lower(btrim(p_nombre));
  if not found then
    raise exception 'NO_ENCONTRADO: no existe el rubro "%". Importá primero los rubros', btrim(p_nombre)
      using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;
