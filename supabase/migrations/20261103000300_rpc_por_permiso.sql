-- Eskemia · Las RPC de Recepción pasan de roles fijos a permisos.
-- Solo cambia la autorización: la lógica es la de 20261102000400_rpc_recepcion.sql.
-- create or replace conserva los grants existentes.

-- Comprueba el permiso en la sede pedida: tener un rol en una sede no habilita otra.
create function app_private.resolver_sede(p_perfil public.perfiles, p_sede_id uuid, p_permiso text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sede uuid := coalesce(p_sede_id, p_perfil.sede_id);
begin
  if v_sede is null then
    raise exception 'PRECONDICION: hay que indicar la sede' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.sedes s where s.id = v_sede and s.tenant_id = p_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  if not app_private.tiene_permiso(p_permiso, v_sede) then
    raise exception 'SIN_PERMISO: la sede no corresponde al usuario' using errcode = '42501';
  end if;
  return v_sede;
end;
$$;

-- Trae la recepción con lock de fila, para serializar las operaciones sobre ella.
create function app_private.exigir_recepcion(p_recepcion_id uuid, p_perfil public.perfiles, p_permiso text)
returns public.recepciones
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec public.recepciones;
begin
  select * into v_rec from public.recepciones r
  where r.id = p_recepcion_id and r.tenant_id = p_perfil.tenant_id
  for update;

  if not found or not app_private.tiene_permiso(p_permiso, v_rec.sede_id) then
    raise exception 'NO_ENCONTRADO: recepción inexistente' using errcode = 'P0002';
  end if;
  return v_rec;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.registrar_dispositivo(p_id uuid, p_nombre text, p_sede_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_sede uuid := app_private.resolver_sede(v_perfil, p_sede_id, 'recepcion.recepcion.operar');
begin
  if exists (
    select 1 from public.dispositivos d
    where d.id = p_id and d.tenant_id = v_perfil.tenant_id
  ) then
    return p_id;
  end if;

  insert into public.dispositivos (id, tenant_id, sede_id, nombre)
  values (p_id, v_perfil.tenant_id, v_sede, p_nombre);

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_sede, 'dispositivo', p_id, 'alta',
    jsonb_build_object('nombre', p_nombre), p_id
  );
  return p_id;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.alta_rapida_proveedor(p_id uuid, p_nombre text, p_cuit text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_cuit text := regexp_replace(coalesce(p_cuit, ''), '[^0-9]', '', 'g');
  v_id uuid;
begin
  if v_cuit !~ '^[0-9]{11}$' then
    raise exception 'PRECONDICION: el CUIT debe tener 11 dígitos' using errcode = 'P0001';
  end if;

  select pr.id into v_id from public.proveedores pr
  where pr.tenant_id = v_perfil.tenant_id and (pr.cuit = v_cuit or pr.id = p_id)
  limit 1;
  if found then
    return v_id;
  end if;

  insert into public.proveedores (id, tenant_id, nombre, cuit)
  values (p_id, v_perfil.tenant_id, btrim(p_nombre), v_cuit);

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_perfil.sede_id, 'proveedor', p_id, 'alta_rapida',
    jsonb_build_object('nombre', p_nombre, 'cuit', v_cuit)
  );
  return p_id;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.alta_rapida_producto(
  p_id uuid,
  p_nombre text,
  p_gtin text default null,
  p_tipo_medida public.tipo_medida default 'UNIDAD',
  p_requiere_lote boolean default false,
  p_requiere_vencimiento boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_gtin text := nullif(btrim(p_gtin), '');
  v_id uuid;
begin
  if v_gtin is not null and not app_private.gtin_valido(v_gtin) then
    raise exception 'PRECONDICION: el GTIN no es válido' using errcode = 'P0001';
  end if;

  select pr.id into v_id from public.productos pr
  where pr.tenant_id = v_perfil.tenant_id and (pr.gtin = v_gtin or pr.id = p_id)
  limit 1;
  if found then
    return v_id;
  end if;

  insert into public.productos
    (id, tenant_id, gtin, nombre, tipo_medida, requiere_lote, requiere_vencimiento, pendiente_validacion)
  values
    (p_id, v_perfil.tenant_id, v_gtin, btrim(p_nombre), p_tipo_medida,
     p_requiere_lote, p_requiere_vencimiento, true);

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_perfil.sede_id, 'producto', p_id, 'alta_rapida',
    jsonb_build_object('nombre', p_nombre, 'gtin', v_gtin)
  );
  return p_id;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.abrir_recepcion(
  p_id uuid,
  p_proveedor_id uuid,
  p_nro_remito text,
  p_sede_id uuid default null,
  p_abierta_en timestamptz default null,
  p_dispositivo_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_sede uuid;
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

  insert into public.recepciones
    (id, tenant_id, sede_id, proveedor_id, nro_remito, usuario_id, abierta_en)
  values
    (p_id, v_perfil.tenant_id, v_sede, p_proveedor_id, btrim(p_nro_remito), auth.uid(),
     coalesce(p_abierta_en, now()));

  perform app_private.registrar_evento(
    v_perfil.tenant_id, v_sede, 'recepcion', p_id, 'abierta',
    jsonb_build_object('proveedor_id', p_proveedor_id, 'nro_remito', btrim(p_nro_remito)),
    p_dispositivo_id
  );
  return p_id;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.registrar_adjunto(
  p_client_uuid uuid,
  p_recepcion_id uuid,
  p_tipo public.tipo_adjunto,
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
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
  v_prefijo text := v_rec.tenant_id || '/' || v_rec.sede_id || '/' || v_rec.id || '/';
  v_id uuid;
begin
  select a.id into v_id from public.adjuntos a
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
    select 1 from public.recepcion_items i
    where i.id = p_item_id and i.recepcion_id = p_recepcion_id
  ) then
    raise exception 'NO_ENCONTRADO: ítem inexistente' using errcode = 'P0002';
  end if;

  -- Una firma nueva reemplaza a la anterior, que queda como evidencia.
  if p_tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA') then
    update public.adjuntos set anulado_en = now()
    where recepcion_id = p_recepcion_id and tipo = p_tipo and anulado_en is null;
  end if;

  insert into public.adjuntos
    (tenant_id, sede_id, recepcion_id, item_id, tipo, storage_path, client_uuid, usuario_id)
  values
    (v_rec.tenant_id, v_rec.sede_id, p_recepcion_id, p_item_id, p_tipo, p_storage_path,
     p_client_uuid, auth.uid())
  returning id into v_id;

  perform app_private.registrar_evento(
    v_rec.tenant_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'adjunto:' || p_tipo::text,
    jsonb_build_object('adjunto_id', v_id, 'storage_path', p_storage_path, 'item_id', p_item_id),
    p_dispositivo_id
  );
  return v_id;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.registrar_lectura(
  p_client_uuid uuid,
  p_recepcion_id uuid,
  p_tipo public.tipo_lectura,
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
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
  v_prod public.productos;
  v_previa public.lecturas;
  v_lote text := nullif(btrim(p_lote), '');
  v_item_id uuid;
  v_cant numeric;
  v_lectura_id uuid;
begin
  -- El reintento se responde antes de mirar el estado: la recepción pudo avanzar.
  select * into v_previa from public.lecturas l where l.client_uuid = p_client_uuid;
  if found then
    if v_previa.recepcion_id <> p_recepcion_id then
      raise exception 'PRECONDICION: client_uuid ya usado en otra recepción' using errcode = 'P0001';
    end if;
    select i.cant_recibida into v_cant from public.recepcion_items i where i.id = v_previa.item_id;
    return jsonb_build_object(
      'lectura_id', v_previa.id, 'item_id', v_previa.item_id,
      'cant_recibida', v_cant, 'duplicada', true
    );
  end if;

  if v_rec.estado not in ('ABIERTA', 'EN_CONTROL') then
    raise exception 'PRECONDICION: la recepción está en estado % y no admite lecturas', v_rec.estado
      using errcode = 'P0001';
  end if;

  select * into v_prod from public.productos pr
  where pr.id = p_producto_id and pr.tenant_id = v_rec.tenant_id;
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

  insert into public.recepcion_items
    (tenant_id, sede_id, recepcion_id, producto_id, lote, vencimiento)
  values
    (v_rec.tenant_id, v_rec.sede_id, p_recepcion_id, p_producto_id, v_lote, p_vencimiento)
  on conflict (recepcion_id, producto_id, lote, vencimiento) do nothing;

  select i.id, i.cant_recibida + p_cantidad into v_item_id, v_cant
  from public.recepcion_items i
  where i.recepcion_id = p_recepcion_id
    and i.producto_id = p_producto_id
    and i.lote is not distinct from v_lote
    and i.vencimiento is not distinct from p_vencimiento;

  if v_cant < 0 then
    raise exception 'PRECONDICION: la cantidad recibida no puede quedar negativa'
      using errcode = 'P0001';
  end if;

  update public.recepcion_items set cant_recibida = v_cant where id = v_item_id;

  insert into public.lecturas
    (tenant_id, sede_id, recepcion_id, item_id, tipo, valor_crudo, producto_id, cantidad,
     motivo, dispositivo_id, leido_en, client_uuid)
  values
    (v_rec.tenant_id, v_rec.sede_id, p_recepcion_id, v_item_id, p_tipo, p_valor_crudo,
     p_producto_id, p_cantidad, nullif(btrim(p_motivo), ''), p_dispositivo_id,
     coalesce(p_leido_en, now()), p_client_uuid)
  returning id into v_lectura_id;

  perform app_private.registrar_evento(
    v_rec.tenant_id, v_rec.sede_id, 'recepcion', p_recepcion_id, 'lectura:' || p_tipo::text,
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

-- recepcion.recepcion.operar
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
  if p_cant_remito is null or p_cant_remito < 0 then
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

-- recepcion.recepcion.operar
create or replace function public.iniciar_control(p_recepcion_id uuid, p_dispositivo_id uuid default null)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
begin
  if v_rec.estado <> 'ABIERTA' then
    return v_rec.estado;  -- reintento de la cola
  end if;
  if not (app_private.checklist(p_recepcion_id) ->> 'foto_remito')::boolean then
    raise exception 'PRECONDICION: falta la foto del remito' using errcode = 'P0001';
  end if;
  perform app_private.cambiar_estado(v_rec, 'EN_CONTROL', '{}'::jsonb, p_dispositivo_id);
  return 'EN_CONTROL';
end;
$$;

-- recepcion.recepcion.operar
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
    when exists (
      select 1 from public.recepcion_items i
      where i.recepcion_id = p_recepcion_id and i.diferencia <> 0
    ) then 'CERRADA_CON_DIFERENCIAS'::public.estado_recepcion
    else 'CERRADA_OK'::public.estado_recepcion
  end;

  perform app_private.cambiar_estado(v_rec, v_nuevo, '{}'::jsonb, p_dispositivo_id);
  update public.recepciones set cerrada_en = coalesce(p_cerrada_en, now())
  where id = p_recepcion_id;
  return v_nuevo;
end;
$$;

-- recepcion.recepcion.operar
create or replace function public.reabrir_recepcion(p_recepcion_id uuid, p_dispositivo_id uuid default null)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.operar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.operar');
begin
  if v_rec.estado = 'EN_CONTROL' then
    return v_rec.estado;  -- reintento de la cola
  end if;

  perform app_private.cambiar_estado(v_rec, 'EN_CONTROL', '{}'::jsonb, p_dispositivo_id);
  update public.adjuntos set anulado_en = now()
  where recepcion_id = p_recepcion_id
    and tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA')
    and anulado_en is null;
  update public.recepciones set cerrada_en = null where id = p_recepcion_id;
  return 'EN_CONTROL';
end;
$$;

-- recepcion.recepcion.validar
create or replace function public.validar_recepcion(p_recepcion_id uuid, p_observacion text default null)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.validar');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.validar');
  v_checklist jsonb := app_private.checklist(p_recepcion_id);
begin
  if not (v_checklist ->> 'completo')::boolean then
    raise exception 'PRECONDICION: control incompleto: %', v_checklist using errcode = 'P0001';
  end if;

  perform app_private.cambiar_estado(
    v_rec, 'VALIDADA', jsonb_build_object('observacion', p_observacion)
  );
  update public.recepciones
  set validada_por = auth.uid(),
      validada_en = now(),
      observacion = coalesce(nullif(btrim(p_observacion), ''), observacion)
  where id = p_recepcion_id;
  return 'VALIDADA';
end;
$$;

-- recepcion.recepcion.validar
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
  return 'RECHAZADA';
end;
$$;

-- recepcion.recepcion.marcar_ingresada
create or replace function public.marcar_ingresada(p_recepcion_id uuid)
returns public.estado_recepcion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('recepcion.recepcion.marcar_ingresada');
  v_rec public.recepciones := app_private.exigir_recepcion(p_recepcion_id, v_perfil, 'recepcion.recepcion.marcar_ingresada');
begin
  perform app_private.cambiar_estado(v_rec, 'INGRESADA_A_SISTEMA');
  return 'INGRESADA_A_SISTEMA';
end;
$$;

-- admin.eventos.verificar
create or replace function public.verificar_cadena_eventos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('admin.eventos.verificar');
  e public.eventos;
  v_prev text := null;
  v_esperada bigint := 1;
begin
  for e in
    select * from public.eventos ev
    where ev.tenant_id = v_perfil.tenant_id
    order by ev.secuencia
  loop
    if e.secuencia <> v_esperada
       or e.hash_prev is distinct from v_prev
       or e.hash <> app_private.hash_evento(e) then
      return jsonb_build_object('ok', false, 'total', v_esperada - 1, 'rota_en', v_esperada);
    end if;
    v_prev := e.hash;
    v_esperada := v_esperada + 1;
  end loop;
  return jsonb_build_object('ok', true, 'total', v_esperada - 1, 'rota_en', null);
end;
$$;

drop function app_private.exigir_perfil(public.rol_usuario[]);
drop function app_private.resolver_sede(public.perfiles, uuid);
drop function app_private.exigir_recepcion(uuid, public.perfiles);

revoke all on function app_private.resolver_sede(public.perfiles, uuid, text) from public, anon, authenticated, service_role;
revoke all on function app_private.exigir_recepcion(uuid, public.perfiles, text) from public, anon, authenticated, service_role;
