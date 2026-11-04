-- Eskemia · Pendientes en Recepción (plan de Compras, etapa 8).
-- Las órdenes aprobadas aparecen en el kiosco. Al recibir sobre una, sus cantidades se precargan
-- y las diferencias entre lo pedido y lo recibido se detectan solas.
-- Se compara por producto: un mismo producto puede venir en varios lotes o presentaciones.

-- oc_numero se copia porque el operario no lee órdenes de compra: llevan precios.
alter table public.recepciones add column oc_numero text;
create index recepciones_oc_idx on public.recepciones (oc_id) where oc_id is not null;

-- cant_pedida: saldo de la orden al abrir la recepción, en unidades de stock.
alter table public.recepcion_items
  add column cant_pedida numeric(17, 3) check (cant_pedida >= 0);

-- Lo recibido se deriva: una recepción rechazada o en curso no cuenta, sin tocar contadores.
create view public.v_oc_saldos
with (security_invoker = true)
as
select
  i.tenant_id,
  i.sede_id,
  i.oc_id,
  i.producto_id,
  min(i.producto_nombre) as producto_nombre,
  min(i.sku) as sku,
  sum(i.cant_pedida) as cant_pedida,
  coalesce((
    select sum(ri.cant_recibida)
    from public.recepcion_items ri
    join public.recepciones r on r.id = ri.recepcion_id
    where r.oc_id = i.oc_id
      and ri.producto_id = i.producto_id
      and r.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS', 'VALIDADA', 'INGRESADA_A_SISTEMA')
  ), 0) as cant_recibida
from public.oc_items i
group by i.tenant_id, i.sede_id, i.oc_id, i.producto_id;

revoke all on public.v_oc_saldos from public, anon, authenticated, service_role;
grant select on public.v_oc_saldos to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Estado de la orden según lo recibido
-- ---------------------------------------------------------------------------

-- Deriva el estado de los saldos, en ambos sentidos: rechazar una recepción puede devolver
-- la orden a pendiente. Por eso no pasa por las transiciones manuales de cambiar_estado_oc.
create function app_private.recalcular_estado_oc(p_oc_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc public.ordenes_compra;
  v_recibido numeric;
  v_con_saldo boolean;
  v_nuevo public.estado_oc;
begin
  if p_oc_id is null then
    return;
  end if;
  select * into v_oc from public.ordenes_compra o where o.id = p_oc_id for update;
  if not found or v_oc.estado not in ('APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL', 'RECIBIDA') then
    return;
  end if;

  select sum(s.cant_recibida), bool_or(s.cant_recibida < s.cant_pedida)
  into v_recibido, v_con_saldo
  from public.v_oc_saldos s where s.oc_id = p_oc_id;

  v_nuevo := case
    when coalesce(v_recibido, 0) = 0 then
      case when v_oc.enviada_en is not null then 'ENVIADA' else 'APROBADA' end::public.estado_oc
    when v_con_saldo then 'RECIBIDA_PARCIAL'::public.estado_oc
    else 'RECIBIDA'::public.estado_oc
  end;
  if v_nuevo = v_oc.estado then
    return;
  end if;

  update public.ordenes_compra set estado = v_nuevo where id = p_oc_id;
  perform app_private.registrar_evento(
    v_oc.tenant_id, v_oc.sede_id, 'orden_compra', v_oc.id, 'estado:' || v_nuevo::text,
    jsonb_build_object('desde', v_oc.estado, 'hasta', v_nuevo, 'numero', v_oc.numero, 'origen', 'recepcion')
  );
end;
$$;

-- Una diferencia es contra el remito o, si hay orden, contra lo pedido.
create function app_private.recepcion_tiene_diferencias(p_recepcion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.recepcion_items i
    where i.recepcion_id = p_recepcion_id and i.diferencia <> 0
  )
  or exists (
    select 1
    from public.recepcion_items i
    join public.recepciones r on r.id = i.recepcion_id
    where i.recepcion_id = p_recepcion_id and r.oc_id is not null
    group by i.producto_id
    having sum(i.cant_recibida) <> coalesce(sum(i.cant_pedida), 0)
  );
$$;

create or replace function app_private.checklist(p_recepcion_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with base as (
    select
      exists (
        select 1 from public.adjuntos a
        where a.recepcion_id = p_recepcion_id and a.tipo = 'REMITO' and a.anulado_en is null
      ) as foto_remito,
      exists (
        select 1 from public.recepcion_items i where i.recepcion_id = p_recepcion_id
      ) as tiene_items,
      not exists (
        select 1 from public.recepcion_items i
        where i.recepcion_id = p_recepcion_id and i.cant_remito is null
          -- La línea precargada de un producto que llegó en otras líneas (por lote) no se controla.
          and not (
            i.cant_pedida is not null and i.cant_recibida = 0 and exists (
              select 1 from public.recepcion_items o
              where o.recepcion_id = i.recepcion_id and o.producto_id = i.producto_id and o.id <> i.id
            )
          )
      ) as cantidades_remito,
      not exists (
        select 1 from public.recepcion_items i
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
        from public.recepcion_items i
        join public.recepciones r on r.id = i.recepcion_id
        where i.recepcion_id = p_recepcion_id and r.oc_id is not null
        group by i.producto_id
        having sum(i.cant_recibida) <> coalesce(sum(i.cant_pedida), 0)
          and not bool_or(coalesce(btrim(i.motivo_diferencia), '') <> '' and i.tipo_diferencia is not null)
      ) as motivos_diferencias,
      not exists (
        select 1 from public.recepcion_items i
        where i.recepcion_id = p_recepcion_id
          and exists (
            select 1 from public.lecturas l where l.item_id = i.id and l.tipo = 'MANUAL'
          )
          and not exists (
            select 1 from public.adjuntos a
            where a.item_id = i.id and a.tipo = 'MANUAL' and a.anulado_en is null
          )
      ) as fotos_manuales,
      exists (
        select 1 from public.adjuntos a
        where a.recepcion_id = p_recepcion_id and a.tipo = 'FIRMA_RECEPTOR' and a.anulado_en is null
      ) as firma_receptor,
      exists (
        select 1 from public.adjuntos a
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

drop function public.abrir_recepcion(uuid, uuid, text, uuid, timestamptz, uuid);

create function public.abrir_recepcion(
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
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_sede uuid;
  v_oc public.ordenes_compra;
begin
  -- Reintento de la cola: si ya existe, no se hace nada.
  if exists (
    select 1 from public.recepciones r
    where r.id = p_id and r.tenant_id = v_perfil.tenant_id
  ) then
    return p_id;
  end if;

  v_sede := app_private.resolver_sede(v_perfil, p_sede_id, 'recepcion.recepcion.operar');

  if coalesce(btrim(p_nro_remito), '') = '' then
    raise exception 'PRECONDICION: falta el número de remito' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.proveedores pr
    where pr.id = p_proveedor_id and pr.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: proveedor inexistente' using errcode = 'P0002';
  end if;

  if p_oc_id is not null then
    select * into v_oc from public.ordenes_compra o
    where o.id = p_oc_id and o.tenant_id = v_perfil.tenant_id and o.sede_id = v_sede;
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

  insert into public.recepciones
    (id, tenant_id, sede_id, proveedor_id, nro_remito, usuario_id, abierta_en, oc_id, oc_numero)
  values
    (p_id, v_perfil.tenant_id, v_sede, p_proveedor_id, btrim(p_nro_remito), auth.uid(),
     coalesce(p_abierta_en, now()), p_oc_id, v_oc.numero);

  -- Precarga lo que falta recibir de la orden, para comparar contra eso.
  if p_oc_id is not null then
    insert into public.recepcion_items (tenant_id, sede_id, recepcion_id, producto_id, cant_pedida)
    select v_perfil.tenant_id, v_sede, p_id, s.producto_id, s.cant_pedida - s.cant_recibida
    from public.v_oc_saldos s
    where s.oc_id = p_oc_id and s.cant_pedida > s.cant_recibida;
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_sede, 'recepcion', p_id, 'abierta',
    jsonb_build_object('proveedor_id', p_proveedor_id, 'nro_remito', btrim(p_nro_remito), 'oc_id', p_oc_id, 'oc_numero', v_oc.numero),
    p_dispositivo_id
  );
  return p_id;
end;
$$;

create or replace function public.cerrar_recepcion(
  p_recepcion_id uuid,
  p_cerrada_en timestamptz default null,
  p_dispositivo_id uuid default null
)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
  v_checklist jsonb;
  v_nuevo public.estado_recepcion;
begin
  if v_rec.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS', 'VALIDADA', 'INGRESADA_A_SISTEMA') then
    return v_rec.estado;  -- reintento de la cola
  end if;

  v_checklist := app_private.checklist(p_recepcion_id);
  if not (v_checklist ->> 'completo')::boolean then
    raise exception 'PRECONDICION: control incompleto: %', v_checklist using errcode = 'P0001';
  end if;

  v_nuevo := case
    when app_private.recepcion_tiene_diferencias(p_recepcion_id) then 'CERRADA_CON_DIFERENCIAS'::public.estado_recepcion
    else 'CERRADA_OK'::public.estado_recepcion
  end;

  perform app_private.cambiar_estado(v_rec, v_nuevo, '{}'::jsonb, p_dispositivo_id);
  update public.recepciones set cerrada_en = coalesce(p_cerrada_en, now())
  where id = p_recepcion_id;
  perform app_private.recalcular_estado_oc(v_rec.oc_id);
  return v_nuevo;
end;
$$;

create or replace function public.rechazar_recepcion(p_recepcion_id uuid, p_observacion text)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.validar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.validar');
begin
  if coalesce(btrim(p_observacion), '') = '' then
    raise exception 'PRECONDICION: rechazar requiere una observación' using errcode = 'P0001';
  end if;

  perform app_private.cambiar_estado(
    v_rec, 'RECHAZADA', jsonb_build_object('observacion', p_observacion)
  );
  update public.recepciones set observacion = btrim(p_observacion) where id = p_recepcion_id;
  perform app_private.recalcular_estado_oc(v_rec.oc_id);
  return 'RECHAZADA';
end;
$$;

-- ---------------------------------------------------------------------------
-- Lista de pendientes
-- ---------------------------------------------------------------------------

-- Sin precios, salvo que el permiso los habilite. Lo que está en aprobación se ve pero no se recibe.
create function public.pendientes_recepcion(p_sede_id uuid)
returns table (
  id uuid,
  numero text,
  estado public.estado_oc,
  proveedor_id uuid,
  proveedor text,
  fecha_entrega_estimada date,
  atrasada boolean,
  no_enviada boolean,
  se_puede_recibir boolean,
  total_estimado numeric,
  items jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.pendientes.ver', p_sede_id);
  v_en_aprobacion boolean := app_private.tiene_permiso('recepcion.pendientes.ver_en_aprobacion', p_sede_id);
  v_precios boolean := app_private.tiene_permiso('recepcion.precios.ver', p_sede_id);
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
      from public.v_oc_saldos s
      join public.productos p on p.id = s.producto_id
      where s.oc_id = o.id
    )
  from public.ordenes_compra o
  join public.proveedores pr on pr.id = o.proveedor_id
  where o.tenant_id = v_perfil.tenant_id
    and o.sede_id = p_sede_id
    and (
      o.estado in ('APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL')
      or (v_en_aprobacion and o.estado = 'PENDIENTE_APROBACION')
    )
  order by o.fecha_entrega_estimada nulls last, o.numero;
end;
$$;

-- ---------------------------------------------------------------------------
-- Back: el semáforo también mira lo pedido
-- ---------------------------------------------------------------------------

create or replace view public.v_recepciones_bandeja
with (security_invoker = true)
as
select
  r.id,
  r.tenant_id,
  r.sede_id,
  s.nombre as sede,
  r.estado,
  r.proveedor_id,
  p.nombre as proveedor,
  r.nro_remito,
  r.usuario_id,
  r.abierta_en,
  r.cerrada_en,
  r.validada_por,
  r.validada_en,
  r.observacion,
  (r.abierta_en at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
  coalesce(i.items, 0) as items,
  coalesce(i.items_con_diferencia, 0) as items_con_diferencia,
  c.checklist,
  -- Alerta para el back: no bloquea, para no trabar la sincronización offline.
  exists (
    select 1 from public.recepciones otra
    where otra.tenant_id = r.tenant_id
      and otra.proveedor_id = r.proveedor_id
      and lower(btrim(otra.nro_remito)) = lower(btrim(r.nro_remito))
      and otra.id <> r.id
  ) as remito_duplicado,
  case
    when not (c.checklist ->> 'completo')::boolean then 'CONTROL_INCOMPLETO'
    when coalesce(i.items_con_diferencia, 0) > 0 then 'CON_DIFERENCIAS'
    else 'OK'
  end as semaforo,
  r.oc_id,
  r.oc_numero
from public.recepciones r
join public.sedes s on s.id = r.sede_id
join public.proveedores p on p.id = r.proveedor_id
left join lateral (
  select
    count(*) as items,
    count(*) filter (
      where ri.diferencia <> 0 or (r.oc_id is not null and t.recibida <> t.pedida)
    ) as items_con_diferencia
  from public.recepcion_items ri
  cross join lateral (
    select sum(x.cant_recibida) as recibida, coalesce(sum(x.cant_pedida), 0) as pedida
    from public.recepcion_items x
    where x.recepcion_id = ri.recepcion_id and x.producto_id = ri.producto_id
  ) t
  where ri.recepcion_id = r.id
) i on true
cross join lateral (select app_private.checklist(r.id) as checklist) c;

revoke all on function app_private.recalcular_estado_oc(uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.recepcion_tiene_diferencias(uuid) from public, anon, authenticated, service_role;
revoke all on function public.abrir_recepcion(uuid, uuid, text, uuid, timestamptz, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.pendientes_recepcion(uuid) from public, anon, authenticated, service_role;
grant execute on function public.abrir_recepcion(uuid, uuid, text, uuid, timestamptz, uuid, uuid) to authenticated;
grant execute on function public.pendientes_recepcion(uuid) to authenticated;
