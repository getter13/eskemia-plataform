-- Eskemia · Bandeja de aprobación (plan de Compras, etapa 7).

-- El nivel con el que el usuario puede aprobar en esa sede. 0: no aprueba.
create function app_private.nivel_aprobacion_usuario(p_user_id uuid, p_sede_id uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(r.nivel_aprobacion), 0)
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
  join public.perfiles p on p.user_id = ur.user_id and p.activo
  where ur.user_id = p_user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);
$$;

-- Trae la orden bloqueada y valida que este usuario pueda decidir sobre ella.
create function app_private.exigir_oc_para_decidir(p_oc_id uuid, p_perfil public.perfiles)
returns public.ordenes_compra
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_oc public.ordenes_compra;
begin
  select * into v_oc from public.ordenes_compra o
  where o.id = p_oc_id and o.tenant_id = p_perfil.tenant_id
  for update;

  if not found or not app_private.tiene_permiso('compras.oc.aprobar', v_oc.sede_id) then
    raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
  end if;
  if app_private.nivel_aprobacion_usuario(p_perfil.user_id, v_oc.sede_id) < v_oc.nivel_requerido then
    raise exception 'SIN_PERMISO: esta orden requiere nivel de aprobación %', v_oc.nivel_requerido
      using errcode = '42501';
  end if;
  if v_oc.usuario_id = p_perfil.user_id and not coalesce(
    (select ce.permitir_autoaprobacion from public.configuracion_empresa ce where ce.tenant_id = v_oc.tenant_id),
    true
  ) then
    raise exception 'SIN_PERMISO: en esta empresa nadie aprueba sus propias órdenes' using errcode = '42501';
  end if;
  return v_oc;
end;
$$;

-- Las órdenes que este usuario puede decidir, con sus ítems y el motivo de la aprobación.
create function public.bandeja_aprobacion()
returns table (
  id uuid,
  numero text,
  sede text,
  proveedor text,
  emisor text,
  creado_en timestamptz,
  total_estimado numeric,
  nivel_requerido int,
  reglas_aplicadas jsonb,
  items jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.oc.aprobar');
  v_autoaprobacion boolean := coalesce(
    (select ce.permitir_autoaprobacion from public.configuracion_empresa ce where ce.tenant_id = v_perfil.tenant_id),
    true
  );
begin
  return query
  select
    o.id, o.numero, s.nombre, pr.nombre, em.nombre, o.creado_en, o.total_estimado, o.nivel_requerido,
    o.reglas_aplicadas,
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'producto', i.producto_nombre, 'sku', i.sku, 'presentacion', i.presentacion_nombre,
        'cantidad', i.cantidad, 'subtotal', i.subtotal, 'disparo_aprobacion', i.disparo_aprobacion
      ) order by i.disparo_aprobacion desc, i.producto_nombre), '[]'::jsonb)
      from public.oc_items i where i.oc_id = o.id
    )
  from public.ordenes_compra o
  join public.sedes s on s.id = o.sede_id
  join public.proveedores pr on pr.id = o.proveedor_id
  left join public.perfiles em on em.user_id = o.usuario_id
  where o.tenant_id = v_perfil.tenant_id
    and o.estado = 'PENDIENTE_APROBACION'
    and app_private.nivel_aprobacion_usuario(v_perfil.user_id, o.sede_id) >= o.nivel_requerido
    and (v_autoaprobacion or o.usuario_id <> v_perfil.user_id)
  order by o.creado_en;
end;
$$;

-- PENDIENTE_APROBACION -> APROBADA. Reintentar sobre una ya aprobada no hace nada.
create function public.aprobar_oc(p_oc_id uuid)
returns public.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.oc.aprobar');
  v_oc public.ordenes_compra := app_private.exigir_oc_para_decidir(p_oc_id, v_perfil);
begin
  if v_oc.estado = 'APROBADA' then
    return v_oc.estado;
  end if;

  perform app_private.cambiar_estado_oc(v_oc, 'APROBADA', jsonb_build_object('tipo_aprobacion', 'MANUAL'));
  update public.ordenes_compra
  set tipo_aprobacion = 'MANUAL', aprobada_por = v_perfil.user_id, aprobada_en = now()
  where id = p_oc_id;
  return 'APROBADA';
end;
$$;

-- PENDIENTE_APROBACION -> RECHAZADA. El motivo es obligatorio.
create function public.rechazar_oc(p_oc_id uuid, p_motivo text)
returns public.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.oc.aprobar');
  v_oc public.ordenes_compra := app_private.exigir_oc_para_decidir(p_oc_id, v_perfil);
begin
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'PRECONDICION: rechazar requiere un motivo' using errcode = 'P0001';
  end if;
  if v_oc.estado = 'RECHAZADA' then
    return v_oc.estado;
  end if;

  perform app_private.cambiar_estado_oc(v_oc, 'RECHAZADA', jsonb_build_object('motivo', btrim(p_motivo)));
  update public.ordenes_compra set motivo_rechazo = btrim(p_motivo) where id = p_oc_id;
  return 'RECHAZADA';
end;
$$;

revoke all on function app_private.nivel_aprobacion_usuario(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.exigir_oc_para_decidir(uuid, public.perfiles) from public, anon, authenticated, service_role;
revoke all on function public.bandeja_aprobacion() from public, anon, authenticated, service_role;
revoke all on function public.aprobar_oc(uuid) from public, anon, authenticated, service_role;
revoke all on function public.rechazar_oc(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.bandeja_aprobacion() to authenticated;
grant execute on function public.aprobar_oc(uuid) to authenticated;
grant execute on function public.rechazar_oc(uuid, text) to authenticated;
