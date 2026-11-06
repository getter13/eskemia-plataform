-- Eskemia · Recepción de Mercadería
-- 5/6: vistas para el back y para el reporte diario (n8n).
-- security_invoker hace que las vistas respeten el RLS de quien consulta.

create view public.v_recepciones_bandeja
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
  end as semaforo
from public.recepciones r
join public.sedes s on s.id = r.sede_id
join public.proveedores p on p.id = r.proveedor_id
left join lateral (
  select
    count(*) as items,
    count(*) filter (where ri.diferencia <> 0) as items_con_diferencia
  from public.recepcion_items ri
  where ri.recepcion_id = r.id
) i on true
cross join lateral (select app_private.checklist(r.id) as checklist) c;

create view public.v_resumen_diario
with (security_invoker = true)
as
select
  b.tenant_id,
  b.sede_id,
  b.sede,
  b.fecha,
  count(*) as recepciones,
  count(*) filter (where b.semaforo = 'OK') as ok,
  count(*) filter (where b.semaforo = 'CON_DIFERENCIAS') as con_diferencias,
  count(*) filter (where b.semaforo = 'CONTROL_INCOMPLETO') as control_incompleto,
  count(*) filter (where b.estado in ('ABIERTA', 'EN_CONTROL')) as en_curso,
  count(*) filter (where b.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS')) as pendientes_validar,
  count(*) filter (where b.estado in ('VALIDADA', 'INGRESADA_A_SISTEMA')) as validadas,
  count(*) filter (where b.estado = 'RECHAZADA') as rechazadas,
  count(*) filter (where b.remito_duplicado) as remitos_duplicados,
  sum(b.items) as items,
  sum(b.items_con_diferencia) as items_con_diferencia
from public.v_recepciones_bandeja b
group by b.tenant_id, b.sede_id, b.sede, b.fecha;

revoke all on public.v_recepciones_bandeja, public.v_resumen_diario
  from public, anon, authenticated, service_role;
grant select on public.v_recepciones_bandeja, public.v_resumen_diario
  to authenticated, service_role;
