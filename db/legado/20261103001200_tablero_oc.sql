-- Eskemia · Tablero de órdenes de compra (plan de Compras, etapa 9): anular y cerrar saldo.

-- Motivo de la anulación o del cierre de saldo.
alter table public.ordenes_compra add column motivo_cierre text;

create function app_private.exigir_oc_con_permiso(p_oc_id uuid, p_permiso text)
returns public.ordenes_compra
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.perfil_activo();
  v_oc public.ordenes_compra;
begin
  select * into v_oc from public.ordenes_compra o
  where o.id = p_oc_id and o.tenant_id = v_perfil.tenant_id
  for update;

  if not found then
    raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
  end if;
  if not app_private.tiene_permiso(p_permiso, v_oc.sede_id) then
    raise exception 'SIN_PERMISO: falta el permiso %', p_permiso using errcode = '42501';
  end if;
  return v_oc;
end;
$$;

-- APROBADA | ENVIADA -> ANULADA. Una recepción rechazada no cuenta: no recibió nada.
create function public.anular_oc(p_oc_id uuid, p_motivo text)
returns public.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc public.ordenes_compra := app_private.exigir_oc_con_permiso(p_oc_id, 'compras.oc.anular');
begin
  if v_oc.estado = 'ANULADA' then
    return v_oc.estado;  -- reintento
  end if;
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: anular requiere un motivo' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.recepciones r
    where r.oc_id = p_oc_id and r.estado <> 'RECHAZADA'
  ) then
    raise exception 'PRECONDICION: la orden % ya tiene recepciones: no se puede anular', v_oc.numero
      using errcode = 'P0001';
  end if;

  perform app_private.cambiar_estado_oc(v_oc, 'ANULADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update public.ordenes_compra set motivo_cierre = btrim(p_motivo) where id = p_oc_id;
  return 'ANULADA';
end;
$$;

-- RECIBIDA_PARCIAL -> CERRADA: lo que falta ya no se espera y deja de estar pendiente.
create function public.cerrar_saldo_oc(p_oc_id uuid, p_motivo text)
returns public.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc public.ordenes_compra := app_private.exigir_oc_con_permiso(p_oc_id, 'compras.oc.cerrar_saldo');
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
    select 1 from public.recepciones r
    where r.oc_id = p_oc_id and r.estado in ('ABIERTA', 'EN_CONTROL', 'RECHAZADA')
  ) then
    raise exception 'PRECONDICION: la orden % tiene una recepción en curso: terminala antes de cerrar el saldo', v_oc.numero
      using errcode = 'P0001';
  end if;

  perform app_private.cambiar_estado_oc(v_oc, 'CERRADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update public.ordenes_compra set motivo_cierre = btrim(p_motivo) where id = p_oc_id;
  return 'CERRADA';
end;
$$;

revoke all on function app_private.exigir_oc_con_permiso(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.anular_oc(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.cerrar_saldo_oc(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.anular_oc(uuid, text) to authenticated;
grant execute on function public.cerrar_saldo_oc(uuid, text) to authenticated;
