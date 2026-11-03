-- Eskemia · Recepción de Mercadería
-- 2/6: tabla eventos append-only con hash encadenado por tenant.

-- sha256(hash_prev + payload). El material incluye también los metadatos del evento,
-- para detectar además una alteración de la acción, el usuario o la fecha.
create function app_private.hash_evento(e public.eventos)
returns text
language sql
stable
set search_path = ''
as $$
  select encode(
    extensions.digest(
      coalesce(e.hash_prev, '') || jsonb_build_object(
        'tenant_id', e.tenant_id,
        'sede_id', e.sede_id,
        'secuencia', e.secuencia,
        'entidad', e.entidad,
        'entidad_id', e.entidad_id,
        'accion', e.accion,
        'payload', e.payload,
        'usuario_id', e.usuario_id,
        'dispositivo_id', e.dispositivo_id,
        'creado_en', to_char(e.creado_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
      )::text,
      'sha256'
    ),
    'hex'
  );
$$;

create function app_private.eventos_encadenar()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_secuencia bigint;
  v_hash text;
begin
  -- Serializa por tenant hasta el fin de la transacción, para que la cadena no se bifurque.
  perform pg_advisory_xact_lock(hashtextextended('eventos:' || new.tenant_id::text, 0));

  select e.secuencia, e.hash into v_secuencia, v_hash
  from public.eventos e
  where e.tenant_id = new.tenant_id
  order by e.secuencia desc
  limit 1;

  new.secuencia := coalesce(v_secuencia, 0) + 1;
  new.hash_prev := v_hash;
  new.creado_en := clock_timestamp();
  new.hash := app_private.hash_evento(new);
  return new;
end;
$$;

create trigger eventos_encadenar
  before insert on public.eventos
  for each row execute function app_private.eventos_encadenar();

create function app_private.eventos_inmutables()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'eventos es append-only: % no permitido', tg_op using errcode = '42501';
end;
$$;

create trigger eventos_sin_update_delete
  before update or delete on public.eventos
  for each row execute function app_private.eventos_inmutables();

create trigger eventos_sin_truncate
  before truncate on public.eventos
  for each statement execute function app_private.eventos_inmutables();

-- Único punto de escritura de eventos. Se llama solo desde las RPC.
create function app_private.registrar_evento(
  p_tenant_id uuid,
  p_sede_id uuid,
  p_entidad text,
  p_entidad_id uuid,
  p_accion text,
  p_payload jsonb default '{}'::jsonb,
  p_dispositivo_id uuid default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.eventos
    (tenant_id, sede_id, secuencia, entidad, entidad_id, accion, payload,
     usuario_id, dispositivo_id, hash)
  values
    (p_tenant_id, p_sede_id, 0, p_entidad, p_entidad_id, p_accion, p_payload,
     auth.uid(), p_dispositivo_id, '');
$$;
