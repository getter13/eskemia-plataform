-- Eskemia · Al recibir sobre una orden de compra no se carga remito.
-- Lo recibido se compara contra lo pedido, y las diferencias aparecen solas.
-- El remito solo se carga en una recepción sin orden.

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
          -- Con orden de compra no se carga remito: se compara contra lo pedido.
          and not exists (
            select 1 from public.recepciones r where r.id = p_recepcion_id and r.oc_id is not null
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

create or replace function public.fijar_control_item(
  p_recepcion_id uuid,
  p_producto_id uuid,
  p_cant_remito numeric,
  p_tipo_diferencia public.tipo_diferencia default null,
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
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
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
    select 1 from public.productos pr
    where pr.id = p_producto_id and pr.tenant_id = v_rec.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  insert into public.recepcion_items
    (tenant_id, sede_id, recepcion_id, producto_id, lote, vencimiento,
     cant_remito, tipo_diferencia, motivo_diferencia)
  values
    (v_rec.tenant_id, v_rec.sede_id, p_recepcion_id, p_producto_id, v_lote, p_vencimiento,
     p_cant_remito, p_tipo_diferencia, nullif(btrim(p_motivo), ''))
  on conflict (recepcion_id, producto_id, lote, vencimiento) do update
    set cant_remito = excluded.cant_remito,
        tipo_diferencia = excluded.tipo_diferencia,
        motivo_diferencia = excluded.motivo_diferencia
  returning id into v_item_id;

  perform app_private.registrar_evento(
    v_rec.tenant_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'control_item',
    jsonb_build_object(
      'item_id', v_item_id, 'producto_id', p_producto_id, 'cant_remito', p_cant_remito,
      'tipo_diferencia', p_tipo_diferencia, 'motivo', p_motivo
    )
  );
  return v_item_id;
end;
$$;
