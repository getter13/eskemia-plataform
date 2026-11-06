-- Eskemia · Línea base v1 · 10: funciones y RPC de Recepción.
--
-- Qué hace: checklist de control, transiciones de estado, guarda de recepción, rutas de
-- Storage y las RPC del kiosco (abrir, leer, controlar, cerrar, validar, rechazar,
-- reabrir, marcar ingresada, adjuntos, dispositivos, pendientes) y las altas rápidas.
-- Dónde encaja: port fiel del legado. abrir_recepcion, registrar_dispositivo y las altas
-- rápidas reciben p_organizacion_id; el resto la toma de la recepción.
-- Todas exigen el módulo recepcion habilitado (y Recepción requiere Compras).

-- ---------------------------------------------------------------------------
-- Internas
-- ---------------------------------------------------------------------------

/** Checklist de control de una recepción: qué falta para cerrarla. Security invoker:
 *  lo usan las vistas con los permisos de quien consulta. */
create function recepcion.checklist(p_recepcion_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with base as (
    select
      exists (
        select 1 from recepcion.adjuntos a
        where a.recepcion_id = p_recepcion_id and a.tipo = 'REMITO' and a.anulado_en is null
      ) as foto_remito,
      exists (
        select 1 from recepcion.recepcion_items i where i.recepcion_id = p_recepcion_id
      ) as tiene_items,
      not exists (
        select 1 from recepcion.recepcion_items i
        where i.recepcion_id = p_recepcion_id and i.cant_remito is null
          -- Con orden de compra no se carga remito: se compara contra lo pedido.
          and not exists (
            select 1 from recepcion.recepciones r where r.id = p_recepcion_id and r.oc_id is not null
          )
      ) as cantidades_remito,
      not exists (
        select 1 from recepcion.recepcion_items i
        where i.recepcion_id = p_recepcion_id
          and i.diferencia <> 0
          and (
            coalesce(btrim(i.motivo_diferencia), '') = ''
            or i.tipo_diferencia is null
            or (i.tipo_diferencia in ('FALTANTE', 'RECHAZO') and i.diferencia > 0)
            or (i.tipo_diferencia = 'SOBRANTE' and i.diferencia < 0)
          )
      ) and not exists (
        -- Con orden de compra, lo recibido contra lo pedido también exige motivo.
        select 1
        from recepcion.recepcion_items i
        join recepcion.recepciones r on r.id = i.recepcion_id
        where i.recepcion_id = p_recepcion_id and r.oc_id is not null
        group by i.producto_id
        having sum(i.cant_recibida) <> coalesce(sum(i.cant_pedida), 0)
          and not bool_or(coalesce(btrim(i.motivo_diferencia), '') <> '' and i.tipo_diferencia is not null)
      ) as motivos_diferencias,
      not exists (
        select 1 from recepcion.recepcion_items i
        where i.recepcion_id = p_recepcion_id
          and exists (
            select 1 from recepcion.lecturas l where l.item_id = i.id and l.tipo = 'MANUAL'
          )
          and not exists (
            select 1 from recepcion.adjuntos a
            where a.item_id = i.id and a.tipo = 'MANUAL' and a.anulado_en is null
          )
      ) as fotos_manuales,
      exists (
        select 1 from recepcion.adjuntos a
        where a.recepcion_id = p_recepcion_id and a.tipo = 'FIRMA_RECEPTOR' and a.anulado_en is null
      ) as firma_receptor,
      exists (
        select 1 from recepcion.adjuntos a
        where a.recepcion_id = p_recepcion_id and a.tipo = 'FIRMA_TRANSPORTISTA' and a.anulado_en is null
      ) as firma_transportista
  )
  select jsonb_build_object(
    'foto_remito', b.foto_remito,
    'tiene_items', b.tiene_items,
    'cantidades_remito', b.cantidades_remito,
    'motivos_diferencias', b.motivos_diferencias,
    'fotos_manuales', b.fotos_manuales,
    'firma_receptor', b.firma_receptor,
    'firma_transportista', b.firma_transportista,
    'completo', b.foto_remito and b.tiene_items and b.cantidades_remito
      and b.motivos_diferencias and b.fotos_manuales
      and b.firma_receptor and b.firma_transportista
  )
  from base b;
$$;

/** true si algún ítem tiene diferencia contra el remito o contra lo pedido en la OC. */
create function recepcion.tiene_diferencias(p_recepcion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from recepcion.recepcion_items i
    where i.recepcion_id = p_recepcion_id and i.diferencia <> 0
  )
  or exists (
    select 1
    from recepcion.recepcion_items i
    join recepcion.recepciones r on r.id = i.recepcion_id
    where i.recepcion_id = p_recepcion_id and r.oc_id is not null
    group by i.producto_id
    having sum(i.cant_recibida) <> coalesce(sum(i.cant_pedida), 0)
  );
$$;

/** Cambia el estado de una recepción validando la transición y escribe el evento
 *  recepcion/estado:<nuevo>. */
create function recepcion.cambiar_estado(
  p_rec recepcion.recepciones,
  p_nuevo recepcion.estado_recepcion,
  p_payload jsonb default '{}'::jsonb,
  p_dispositivo_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    (p_rec.estado = 'ABIERTA' and p_nuevo = 'EN_CONTROL')
    or (p_rec.estado = 'EN_CONTROL' and p_nuevo in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS'))
    or (p_rec.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS') and p_nuevo in ('VALIDADA', 'RECHAZADA'))
    or (p_rec.estado = 'VALIDADA' and p_nuevo = 'INGRESADA_A_SISTEMA')
    or (p_rec.estado = 'RECHAZADA' and p_nuevo = 'EN_CONTROL')
  ) then
    raise exception 'PRECONDICION: transición inválida de % a %', p_rec.estado, p_nuevo
      using errcode = 'P0001';
  end if;

  update recepcion.recepciones set estado = p_nuevo where id = p_rec.id;

  perform nucleo.registrar_evento(
    p_rec.organizacion_id, p_rec.sede_id, 'recepcion', p_rec.id, 'estado:' || p_nuevo::text,
    jsonb_build_object('desde', p_rec.estado, 'hasta', p_nuevo) || p_payload,
    p_dispositivo_id
  );
end;
$$;

/** Exige el permiso en la organización de la recepción, la bloquea y la devuelve.
 *  SIN_PERMISO si la cuenta no tiene el permiso en ninguna sede; NO_ENCONTRADO si la
 *  recepción es de otra organización o de una sede que la cuenta no alcanza. */
create function recepcion.exigir_recepcion(p_recepcion_id uuid, p_permiso text)
returns recepcion.recepciones
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro(
    (select r.organizacion_id from recepcion.recepciones r where r.id = p_recepcion_id), 'recepción');
  v_rec recepcion.recepciones;
begin
  perform nucleo.exigir_permiso(v_org, p_permiso);
  select * into v_rec from recepcion.recepciones r
  where r.id = p_recepcion_id and r.organizacion_id = v_org
  for update;
  if not nucleo.tiene_permiso(v_org, p_permiso, v_rec.sede_id) then
    raise exception 'NO_ENCONTRADO: recepción inexistente' using errcode = 'P0002';
  end if;
  return v_rec;
end;
$$;

/** true si la ruta de Storage es <org>/<sede>/<recepcion>/<archivo> y la cuenta alcanza
 *  esa sede. Base de la política de lectura del bucket adjuntos. */
create function recepcion.ruta_adjunto_visible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    then nucleo.puede_ver_sede(split_part(p_name, '/', 1)::uuid, split_part(p_name, '/', 2)::uuid)
    else false
  end;
$$;

/** Como ruta_adjunto_visible y además la recepción existe en esa organización y sede.
 *  Base de la política de subida. */
create function recepcion.ruta_adjunto_escribible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select recepcion.ruta_adjunto_visible(p_name)
    and exists (
      select 1 from recepcion.recepciones r
      where r.organizacion_id = split_part(p_name, '/', 1)::uuid
        and r.sede_id = split_part(p_name, '/', 2)::uuid
        and r.id = split_part(p_name, '/', 3)::uuid
    );
$$;

-- ---------------------------------------------------------------------------
-- Altas rápidas desde el kiosco
-- ---------------------------------------------------------------------------

/** api.alta_rapida_proveedor — Alta mínima de un proveedor durante una recepción.
 *  Idempotente por id o CUIT (devuelve el existente).
 *  Precondiciones: CUIT de 11 dígitos. Permisos: recepcion.recepcion.operar.
 *  Eventos: proveedor/alta_rapida. */
create function api.alta_rapida_proveedor(p_organizacion_id uuid, p_id uuid, p_nombre text, p_cuit text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'recepcion.recepcion.operar');
  v_cuit text := regexp_replace(coalesce(p_cuit, ''), '[^0-9]', '', 'g');
  v_id uuid;
begin
  if v_cuit !~ '^[0-9]{11}$' then
    raise exception 'PRECONDICION: el CUIT debe tener 11 dígitos' using errcode = 'P0001';
  end if;

  select pr.id into v_id from compras.proveedores pr
  where pr.organizacion_id = v_m.organizacion_id and (pr.cuit = v_cuit or pr.id = p_id)
  limit 1;
  if found then
    return v_id;
  end if;

  insert into compras.proveedores (id, organizacion_id, nombre, cuit)
  values (p_id, v_m.organizacion_id, btrim(p_nombre), v_cuit);

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'proveedor', p_id, 'alta_rapida',
    jsonb_build_object('nombre', p_nombre, 'cuit', v_cuit)
  );
  return p_id;
end;
$$;

/** api.alta_rapida_producto — Alta mínima de un producto durante una recepción; queda
 *  pendiente de validación hasta que Compras lo complete. Idempotente por id o GTIN.
 *  Precondiciones: GTIN válido si viene. Permisos: recepcion.recepcion.operar.
 *  Eventos: producto/alta_rapida. */
create function api.alta_rapida_producto(
  p_organizacion_id uuid,
  p_id uuid,
  p_nombre text,
  p_gtin text default null,
  p_tipo_medida compras.tipo_medida default 'UNIDAD',
  p_requiere_lote boolean default false,
  p_requiere_vencimiento boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'recepcion.recepcion.operar');
  v_gtin text := nullif(btrim(p_gtin), '');
  v_id uuid;
begin
  if v_gtin is not null and not compras.gtin_valido(v_gtin) then
    raise exception 'PRECONDICION: el GTIN no es válido' using errcode = 'P0001';
  end if;

  select pr.id into v_id from compras.productos pr
  where pr.organizacion_id = v_m.organizacion_id and (pr.gtin = v_gtin or pr.id = p_id)
  limit 1;
  if found then
    return v_id;
  end if;

  insert into compras.productos
    (id, organizacion_id, gtin, nombre, tipo_medida, requiere_lote, requiere_vencimiento, pendiente_validacion)
  values
    (p_id, v_m.organizacion_id, v_gtin, btrim(p_nombre), p_tipo_medida,
     p_requiere_lote, p_requiere_vencimiento, true);

  perform nucleo.registrar_evento(
    v_m.organizacion_id, null, 'producto', p_id, 'alta_rapida',
    jsonb_build_object('nombre', p_nombre, 'gtin', v_gtin)
  );
  return p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Ciclo de la recepción
-- ---------------------------------------------------------------------------

/** api.registrar_dispositivo — Registra el dispositivo (kiosco o celular) en una sede.
 *  Idempotente por id. Permisos: recepcion.recepcion.operar en la sede.
 *  Eventos: dispositivo/alta. */
create function api.registrar_dispositivo(p_organizacion_id uuid, p_id uuid, p_nombre text, p_sede_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'recepcion.recepcion.operar');
  v_sede uuid := nucleo.resolver_sede(v_m, p_sede_id, 'recepcion.recepcion.operar');
begin
  if exists (
    select 1 from recepcion.dispositivos d
    where d.id = p_id and d.organizacion_id = v_m.organizacion_id
  ) then
    return p_id;
  end if;

  insert into recepcion.dispositivos (id, organizacion_id, sede_id, nombre)
  values (p_id, v_m.organizacion_id, v_sede, p_nombre);

  perform nucleo.registrar_evento(
    v_m.organizacion_id, v_sede, 'dispositivo', p_id, 'alta',
    jsonb_build_object('nombre', p_nombre), p_id
  );
  return p_id;
end;
$$;

/** api.abrir_recepcion — Abre una recepción (id generado en el cliente, para operar sin
 *  conexión). Con OC, precarga lo que falta recibir. Idempotente por id.
 *  Precondiciones: remito no vacío; proveedor de la organización; OC de la sede, del
 *    mismo proveedor y en estado recibible.
 *  Permisos: recepcion.recepcion.operar en la sede. Eventos: recepcion/abierta. */
create function api.abrir_recepcion(
  p_organizacion_id uuid,
  p_id uuid,
  p_proveedor_id uuid,
  p_nro_remito text,
  p_sede_id uuid default null,
  p_abierta_en timestamptz default null,
  p_dispositivo_id uuid default null,
  p_oc_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m nucleo.membresias := nucleo.exigir_permiso(p_organizacion_id, 'recepcion.recepcion.operar');
  v_org uuid := v_m.organizacion_id;
  v_sede uuid;
  v_oc compras.ordenes_compra;
begin
  -- Reintento de la cola: si ya existe, no se hace nada.
  if exists (select 1 from recepcion.recepciones r where r.id = p_id and r.organizacion_id = v_org) then
    return p_id;
  end if;

  v_sede := nucleo.resolver_sede(v_m, p_sede_id, 'recepcion.recepcion.operar');

  if coalesce(btrim(p_nro_remito), '') = '' then
    raise exception 'PRECONDICION: falta el número de remito' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from compras.proveedores pr where pr.id = p_proveedor_id and pr.organizacion_id = v_org
  ) then
    raise exception 'NO_ENCONTRADO: proveedor inexistente' using errcode = 'P0002';
  end if;

  if p_oc_id is not null then
    select * into v_oc from compras.ordenes_compra o
    where o.id = p_oc_id and o.organizacion_id = v_org and o.sede_id = v_sede;
    if not found then
      raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
    end if;
    if v_oc.proveedor_id <> p_proveedor_id then
      raise exception 'PRECONDICION: la orden % es de otro proveedor', v_oc.numero using errcode = 'P0001';
    end if;
    if v_oc.estado not in ('APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL') then
      raise exception 'PRECONDICION: la orden % no se puede recibir (está en estado %)', v_oc.numero, v_oc.estado
        using errcode = 'P0001';
    end if;
  end if;

  insert into recepcion.recepciones
    (id, organizacion_id, sede_id, proveedor_id, nro_remito, usuario_id, abierta_en, oc_id, oc_numero)
  values
    (p_id, v_org, v_sede, p_proveedor_id, btrim(p_nro_remito), auth.uid(),
     coalesce(p_abierta_en, now()), p_oc_id, v_oc.numero);

  -- Precarga lo que falta recibir de la orden, para comparar contra eso.
  if p_oc_id is not null then
    insert into recepcion.recepcion_items (organizacion_id, sede_id, recepcion_id, producto_id, cant_pedida)
    select v_org, v_sede, p_id, s.producto_id, s.cant_pedida - s.cant_recibida
    from compras.v_oc_saldos s
    where s.oc_id = p_oc_id and s.cant_pedida > s.cant_recibida;
  end if;

  perform nucleo.registrar_evento(
    v_org, v_sede, 'recepcion', p_id, 'abierta',
    jsonb_build_object('proveedor_id', p_proveedor_id, 'nro_remito', btrim(p_nro_remito),
                       'oc_id', p_oc_id, 'oc_numero', v_oc.numero),
    p_dispositivo_id
  );
  return p_id;
end;
$$;

/** api.registrar_adjunto — Registra un archivo ya subido a Storage (remito, rechazo,
 *  foto de carga manual o firma). Una firma nueva anula la anterior. Idempotente por
 *  client_uuid.
 *  Precondiciones: recepción ABIERTA o EN_CONTROL; ruta bajo <org>/<sede>/<recepcion>/;
 *    el objeto existe; la foto manual indica el ítem.
 *  Permisos: recepcion.recepcion.operar en la sede. Eventos: recepcion/adjunto:<tipo>. */
create function api.registrar_adjunto(
  p_client_uuid uuid,
  p_recepcion_id uuid,
  p_tipo recepcion.tipo_adjunto,
  p_storage_path text,
  p_item_id uuid default null,
  p_dispositivo_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
  v_prefijo text := v_rec.organizacion_id || '/' || v_rec.sede_id || '/' || v_rec.id || '/';
  v_id uuid;
begin
  select a.id into v_id from recepcion.adjuntos a
  where a.client_uuid = p_client_uuid and a.recepcion_id = p_recepcion_id;
  if found then
    return v_id;
  end if;

  if v_rec.estado not in ('ABIERTA', 'EN_CONTROL') then
    raise exception 'PRECONDICION: la recepción está en estado % y no admite adjuntos', v_rec.estado
      using errcode = 'P0001';
  end if;
  if p_storage_path is null or left(p_storage_path, length(v_prefijo)) <> v_prefijo then
    raise exception 'PRECONDICION: la ruta del archivo no corresponde a la recepción'
      using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'adjuntos' and o.name = p_storage_path
  ) then
    raise exception 'PRECONDICION: el archivo todavía no está en Storage' using errcode = 'P0001';
  end if;
  if p_tipo = 'MANUAL' and p_item_id is null then
    raise exception 'PRECONDICION: la foto de carga manual debe indicar el ítem'
      using errcode = 'P0001';
  end if;
  if p_item_id is not null and not exists (
    select 1 from recepcion.recepcion_items i
    where i.id = p_item_id and i.recepcion_id = p_recepcion_id
  ) then
    raise exception 'NO_ENCONTRADO: ítem inexistente' using errcode = 'P0002';
  end if;

  -- Una firma nueva reemplaza a la anterior, que queda como evidencia.
  if p_tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA') then
    update recepcion.adjuntos set anulado_en = now()
    where recepcion_id = p_recepcion_id and tipo = p_tipo and anulado_en is null;
  end if;

  insert into recepcion.adjuntos
    (organizacion_id, sede_id, recepcion_id, item_id, tipo, storage_path, client_uuid, usuario_id)
  values
    (v_rec.organizacion_id, v_rec.sede_id, p_recepcion_id, p_item_id, p_tipo, p_storage_path,
     p_client_uuid, auth.uid())
  returning id into v_id;

  perform nucleo.registrar_evento(
    v_rec.organizacion_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'adjunto:' || p_tipo::text,
    jsonb_build_object('adjunto_id', v_id, 'storage_path', p_storage_path, 'item_id', p_item_id),
    p_dispositivo_id
  );
  return v_id;
end;
$$;

/** api.iniciar_control — Pasa la recepción de ABIERTA a EN_CONTROL. Idempotente.
 *  Precondiciones: foto del remito cargada. Permisos: recepcion.recepcion.operar.
 *  Eventos: recepcion/estado:EN_CONTROL. */
create function api.iniciar_control(p_recepcion_id uuid, p_dispositivo_id uuid default null)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
begin
  if v_rec.estado <> 'ABIERTA' then
    return v_rec.estado;  -- reintento de la cola
  end if;
  if not (recepcion.checklist(p_recepcion_id) ->> 'foto_remito')::boolean then
    raise exception 'PRECONDICION: falta la foto del remito' using errcode = 'P0001';
  end if;
  perform recepcion.cambiar_estado(v_rec, 'EN_CONTROL', '{}'::jsonb, p_dispositivo_id);
  return 'EN_CONTROL';
end;
$$;

/** api.registrar_lectura — Registra una lectura (escaneo, carga manual o pesaje) y
 *  acumula lo recibido en el ítem del producto/lote/vencimiento. Idempotente por
 *  client_uuid (responde el reintento aunque la recepción haya avanzado).
 *  Precondiciones: recepción ABIERTA o EN_CONTROL; producto de la organización; cantidad
 *    distinta de cero y entera si se cuenta por unidad; lote y vencimiento si el producto
 *    los requiere; motivo si es manual; valor leído si es escaneo; el total no queda negativo.
 *  Permisos: recepcion.recepcion.operar. Eventos: recepcion/lectura:<tipo>. */
create function api.registrar_lectura(
  p_client_uuid uuid,
  p_recepcion_id uuid,
  p_tipo recepcion.tipo_lectura,
  p_producto_id uuid,
  p_cantidad numeric,
  p_valor_crudo text default null,
  p_lote text default null,
  p_vencimiento date default null,
  p_motivo text default null,
  p_dispositivo_id uuid default null,
  p_leido_en timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
  v_prod compras.productos;
  v_previa recepcion.lecturas;
  v_lote text := nullif(btrim(p_lote), '');
  v_item_id uuid;
  v_cant numeric;
  v_lectura_id uuid;
begin
  -- El reintento se responde antes de mirar el estado: la recepción pudo avanzar.
  select * into v_previa from recepcion.lecturas l where l.client_uuid = p_client_uuid;
  if found then
    if v_previa.recepcion_id <> p_recepcion_id then
      raise exception 'PRECONDICION: client_uuid ya usado en otra recepción' using errcode = 'P0001';
    end if;
    select i.cant_recibida into v_cant from recepcion.recepcion_items i where i.id = v_previa.item_id;
    return jsonb_build_object(
      'lectura_id', v_previa.id, 'item_id', v_previa.item_id,
      'cant_recibida', v_cant, 'duplicada', true
    );
  end if;

  if v_rec.estado not in ('ABIERTA', 'EN_CONTROL') then
    raise exception 'PRECONDICION: la recepción está en estado % y no admite lecturas', v_rec.estado
      using errcode = 'P0001';
  end if;

  select * into v_prod from compras.productos pr
  where pr.id = p_producto_id and pr.organizacion_id = v_rec.organizacion_id;
  if not found then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  if p_cantidad is null or p_cantidad = 0 then
    raise exception 'PRECONDICION: la cantidad no puede ser cero' using errcode = 'P0001';
  end if;
  if v_prod.tipo_medida = 'UNIDAD' and p_cantidad <> trunc(p_cantidad) then
    raise exception 'PRECONDICION: este producto se cuenta por unidad' using errcode = 'P0001';
  end if;
  if v_prod.requiere_lote and v_lote is null then
    raise exception 'PRECONDICION: este producto requiere lote' using errcode = 'P0001';
  end if;
  if v_prod.requiere_vencimiento and p_vencimiento is null then
    raise exception 'PRECONDICION: este producto requiere vencimiento' using errcode = 'P0001';
  end if;
  if p_tipo = 'MANUAL' and coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: la carga manual requiere motivo' using errcode = 'P0001';
  end if;
  if p_tipo = 'ESCANEO' and coalesce(btrim(p_valor_crudo), '') = '' then
    raise exception 'PRECONDICION: el escaneo requiere el valor leído' using errcode = 'P0001';
  end if;

  insert into recepcion.recepcion_items
    (organizacion_id, sede_id, recepcion_id, producto_id, lote, vencimiento)
  values
    (v_rec.organizacion_id, v_rec.sede_id, p_recepcion_id, p_producto_id, v_lote, p_vencimiento)
  on conflict (recepcion_id, producto_id, lote, vencimiento) do nothing;

  select i.id, i.cant_recibida + p_cantidad into v_item_id, v_cant
  from recepcion.recepcion_items i
  where i.recepcion_id = p_recepcion_id
    and i.producto_id = p_producto_id
    and i.lote is not distinct from v_lote
    and i.vencimiento is not distinct from p_vencimiento;

  if v_cant < 0 then
    raise exception 'PRECONDICION: la cantidad recibida no puede quedar negativa'
      using errcode = 'P0001';
  end if;

  update recepcion.recepcion_items set cant_recibida = v_cant where id = v_item_id;

  insert into recepcion.lecturas
    (organizacion_id, sede_id, recepcion_id, item_id, tipo, valor_crudo, producto_id, cantidad,
     motivo, dispositivo_id, leido_en, client_uuid)
  values
    (v_rec.organizacion_id, v_rec.sede_id, p_recepcion_id, v_item_id, p_tipo, p_valor_crudo,
     p_producto_id, p_cantidad, nullif(btrim(p_motivo), ''), p_dispositivo_id,
     coalesce(p_leido_en, now()), p_client_uuid)
  returning id into v_lectura_id;

  perform nucleo.registrar_evento(
    v_rec.organizacion_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'lectura:' || p_tipo::text,
    jsonb_build_object(
      'lectura_id', v_lectura_id, 'item_id', v_item_id, 'producto_id', p_producto_id,
      'cantidad', p_cantidad, 'valor_crudo', p_valor_crudo, 'motivo', p_motivo
    ),
    p_dispositivo_id
  );

  return jsonb_build_object(
    'lectura_id', v_lectura_id, 'item_id', v_item_id,
    'cant_recibida', v_cant, 'duplicada', false
  );
end;
$$;

/** api.fijar_control_item — Carga lo que dice el remito para un ítem y, si hay
 *  diferencia, su tipo y motivo (upsert por producto/lote/vencimiento).
 *  Precondiciones: recepción EN_CONTROL; cantidad de remito >= 0 (obligatoria sin OC);
 *    producto de la organización. Permisos: recepcion.recepcion.operar.
 *  Eventos: recepcion/control_item. */
create function api.fijar_control_item(
  p_recepcion_id uuid,
  p_producto_id uuid,
  p_cant_remito numeric,
  p_tipo_diferencia recepcion.tipo_diferencia default null,
  p_motivo text default null,
  p_lote text default null,
  p_vencimiento date default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
  v_lote text := nullif(btrim(p_lote), '');
  v_item_id uuid;
begin
  if v_rec.estado <> 'EN_CONTROL' then
    raise exception 'PRECONDICION: solo se controla en estado EN_CONTROL (está en %)', v_rec.estado
      using errcode = 'P0001';
  end if;
  -- Sin orden de compra, lo que dice el remito es la única referencia.
  if (p_cant_remito is null and v_rec.oc_id is null) or p_cant_remito < 0 then
    raise exception 'PRECONDICION: la cantidad del remito no es válida' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from compras.productos pr
    where pr.id = p_producto_id and pr.organizacion_id = v_rec.organizacion_id
  ) then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  insert into recepcion.recepcion_items
    (organizacion_id, sede_id, recepcion_id, producto_id, lote, vencimiento,
     cant_remito, tipo_diferencia, motivo_diferencia)
  values
    (v_rec.organizacion_id, v_rec.sede_id, p_recepcion_id, p_producto_id, v_lote, p_vencimiento,
     p_cant_remito, p_tipo_diferencia, nullif(btrim(p_motivo), ''))
  on conflict (recepcion_id, producto_id, lote, vencimiento) do update
    set cant_remito = excluded.cant_remito,
        tipo_diferencia = excluded.tipo_diferencia,
        motivo_diferencia = excluded.motivo_diferencia
  returning id into v_item_id;

  perform nucleo.registrar_evento(
    v_rec.organizacion_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'control_item',
    jsonb_build_object(
      'item_id', v_item_id, 'producto_id', p_producto_id, 'cant_remito', p_cant_remito,
      'tipo_diferencia', p_tipo_diferencia, 'motivo', p_motivo
    )
  );
  return v_item_id;
end;
$$;

/** api.checklist_recepcion — Checklist de control de una recepción visible para la
 *  cuenta. Precondiciones: la recepción es visible por RLS. Eventos: ninguno. */
create function api.checklist_recepcion(p_recepcion_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (select 1 from recepcion.recepciones r where r.id = p_recepcion_id) then
    raise exception 'NO_ENCONTRADO: recepción inexistente' using errcode = 'P0002';
  end if;
  return recepcion.checklist(p_recepcion_id);
end;
$$;

/** api.cerrar_recepcion — Cierra el control: CERRADA_OK o CERRADA_CON_DIFERENCIAS y
 *  recalcula el estado de la OC. Idempotente.
 *  Precondiciones: checklist completo. Permisos: recepcion.recepcion.operar.
 *  Eventos: recepcion/estado:<cerrada> (y orden_compra/estado:* si cambia la OC). */
create function api.cerrar_recepcion(p_recepcion_id uuid, p_cerrada_en timestamptz default null, p_dispositivo_id uuid default null)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
  v_checklist jsonb;
  v_nuevo recepcion.estado_recepcion;
begin
  if v_rec.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS', 'VALIDADA', 'INGRESADA_A_SISTEMA') then
    return v_rec.estado;  -- reintento de la cola
  end if;

  v_checklist := recepcion.checklist(p_recepcion_id);
  if not (v_checklist ->> 'completo')::boolean then
    raise exception 'PRECONDICION: control incompleto: %', v_checklist using errcode = 'P0001';
  end if;

  v_nuevo := case
    when recepcion.tiene_diferencias(p_recepcion_id) then 'CERRADA_CON_DIFERENCIAS'::recepcion.estado_recepcion
    else 'CERRADA_OK'::recepcion.estado_recepcion
  end;

  perform recepcion.cambiar_estado(v_rec, v_nuevo, '{}'::jsonb, p_dispositivo_id);
  update recepcion.recepciones set cerrada_en = coalesce(p_cerrada_en, now())
  where id = p_recepcion_id;
  perform compras.recalcular_estado_oc(v_rec.oc_id);
  return v_nuevo;
end;
$$;

/** api.validar_recepcion — El supervisor valida una recepción cerrada.
 *  Precondiciones: checklist completo; estado cerrado.
 *  Permisos: recepcion.recepcion.validar en la sede. Eventos: recepcion/estado:VALIDADA. */
create function api.validar_recepcion(p_recepcion_id uuid, p_observacion text default null)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.validar');
  v_checklist jsonb := recepcion.checklist(p_recepcion_id);
begin
  if not (v_checklist ->> 'completo')::boolean then
    raise exception 'PRECONDICION: control incompleto: %', v_checklist using errcode = 'P0001';
  end if;

  perform recepcion.cambiar_estado(v_rec, 'VALIDADA', jsonb_build_object('observacion', p_observacion));
  update recepcion.recepciones
  set validada_por = auth.uid(),
      validada_en = now(),
      observacion = coalesce(nullif(btrim(p_observacion), ''), observacion)
  where id = p_recepcion_id;
  return 'VALIDADA';
end;
$$;

/** api.rechazar_recepcion — El supervisor rechaza una recepción cerrada, con
 *  observación, y recalcula la OC.
 *  Permisos: recepcion.recepcion.validar en la sede. Eventos: recepcion/estado:RECHAZADA. */
create function api.rechazar_recepcion(p_recepcion_id uuid, p_observacion text)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.validar');
begin
  if coalesce(btrim(p_observacion), '') = '' then
    raise exception 'PRECONDICION: rechazar requiere una observación' using errcode = 'P0001';
  end if;

  perform recepcion.cambiar_estado(v_rec, 'RECHAZADA', jsonb_build_object('observacion', p_observacion));
  update recepcion.recepciones set observacion = btrim(p_observacion) where id = p_recepcion_id;
  perform compras.recalcular_estado_oc(v_rec.oc_id);
  return 'RECHAZADA';
end;
$$;

/** api.reabrir_recepcion — Vuelve una recepción rechazada a EN_CONTROL; anula las
 *  firmas vigentes. Idempotente. Permisos: recepcion.recepcion.operar.
 *  Eventos: recepcion/estado:EN_CONTROL. */
create function api.reabrir_recepcion(p_recepcion_id uuid, p_dispositivo_id uuid default null)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.operar');
begin
  if v_rec.estado = 'EN_CONTROL' then
    return v_rec.estado;  -- reintento de la cola
  end if;

  perform recepcion.cambiar_estado(v_rec, 'EN_CONTROL', '{}'::jsonb, p_dispositivo_id);
  update recepcion.adjuntos set anulado_en = now()
  where recepcion_id = p_recepcion_id
    and tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA')
    and anulado_en is null;
  update recepcion.recepciones set cerrada_en = null where id = p_recepcion_id;
  return 'EN_CONTROL';
end;
$$;

/** api.marcar_ingresada — Marca una recepción validada como ingresada al sistema de
 *  stock. Permisos: recepcion.recepcion.marcar_ingresada en la sede.
 *  Eventos: recepcion/estado:INGRESADA_A_SISTEMA. */
create function api.marcar_ingresada(p_recepcion_id uuid)
returns recepcion.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec recepcion.recepciones := recepcion.exigir_recepcion(p_recepcion_id, 'recepcion.recepcion.marcar_ingresada');
begin
  perform recepcion.cambiar_estado(v_rec, 'INGRESADA_A_SISTEMA');
  return 'INGRESADA_A_SISTEMA';
end;
$$;

/** api.pendientes_recepcion — OC que la sede espera recibir, con saldo por producto.
 *  Las pendientes de aprobación solo con recepcion.pendientes.ver_en_aprobacion; el total
 *  solo con recepcion.precios.ver.
 *  Permisos: recepcion.pendientes.ver en la sede. Eventos: ninguno. */
create function api.pendientes_recepcion(p_sede_id uuid)
returns table (
  id uuid, numero text, estado compras.estado_oc, proveedor_id uuid, proveedor text,
  fecha_entrega_estimada date, atrasada boolean, no_enviada boolean, se_puede_recibir boolean,
  total_estimado numeric, items jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := nucleo.exigir_miembro((select s.organizacion_id from nucleo.sedes s where s.id = p_sede_id), 'sede');
  v_m nucleo.membresias := nucleo.exigir_permiso(v_org, 'recepcion.pendientes.ver', p_sede_id);
  v_en_aprobacion boolean := nucleo.tiene_permiso(v_org, 'recepcion.pendientes.ver_en_aprobacion', p_sede_id);
  v_precios boolean := nucleo.tiene_permiso(v_org, 'recepcion.precios.ver', p_sede_id);
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  return query
  select
    o.id, o.numero, o.estado, o.proveedor_id, pr.nombre, o.fecha_entrega_estimada,
    coalesce(o.fecha_entrega_estimada < v_hoy, false) and o.estado <> 'PENDIENTE_APROBACION',
    o.estado = 'APROBADA',
    o.estado <> 'PENDIENTE_APROBACION',
    case when v_precios then o.total_estimado end,
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'producto_id', s.producto_id,
        'nombre', s.producto_nombre,
        'sku', s.sku,
        'tipo_medida', p.tipo_medida,
        'requiere_lote', p.requiere_lote,
        'requiere_vencimiento', p.requiere_vencimiento,
        'cant_pedida', s.cant_pedida,
        'cant_recibida', s.cant_recibida,
        'saldo', greatest(s.cant_pedida - s.cant_recibida, 0)
      ) order by s.producto_nombre), '[]'::jsonb)
      from compras.v_oc_saldos s
      join compras.productos p on p.id = s.producto_id
      where s.oc_id = o.id
    )
  from compras.ordenes_compra o
  join compras.proveedores pr on pr.id = o.proveedor_id
  where o.organizacion_id = v_m.organizacion_id
    and o.sede_id = p_sede_id
    and (
      o.estado in ('APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL')
      or (v_en_aprobacion and o.estado = 'PENDIENTE_APROBACION')
    )
  order by o.fecha_entrega_estimada nulls last, o.numero;
end;
$$;
