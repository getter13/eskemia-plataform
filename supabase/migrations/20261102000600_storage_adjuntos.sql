-- Eskemia · Recepción de Mercadería
-- 6/6: bucket privado de adjuntos (fotos y firmas).
-- Ruta: <tenant_id>/<sede_id>/<recepcion_id>/<archivo>
-- Sin políticas de update ni delete: la evidencia no se reemplaza ni se borra.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'adjuntos', 'adjuntos', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create function app_private.ruta_adjunto_visible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    then app_private.puede_ver_sede(
      split_part(p_name, '/', 1)::uuid,
      split_part(p_name, '/', 2)::uuid
    )
    else false
  end;
$$;

-- Para subir, la recepción ya tiene que existir en esa sede.
create function app_private.ruta_adjunto_escribible(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.ruta_adjunto_visible(p_name)
    and exists (
      select 1 from public.recepciones r
      where r.tenant_id = split_part(p_name, '/', 1)::uuid
        and r.sede_id = split_part(p_name, '/', 2)::uuid
        and r.id = split_part(p_name, '/', 3)::uuid
    );
$$;

revoke all on function app_private.ruta_adjunto_visible(text) from public;
revoke all on function app_private.ruta_adjunto_escribible(text) from public;
grant execute on function app_private.ruta_adjunto_visible(text) to authenticated;
grant execute on function app_private.ruta_adjunto_escribible(text) to authenticated;

create policy adjuntos_lectura on storage.objects
  for select to authenticated
  using (bucket_id = 'adjuntos' and app_private.ruta_adjunto_visible(name));

create policy adjuntos_subida on storage.objects
  for insert to authenticated
  with check (bucket_id = 'adjuntos' and app_private.ruta_adjunto_escribible(name));
