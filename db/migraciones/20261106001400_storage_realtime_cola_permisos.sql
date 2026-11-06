-- Eskemia · Línea base v1 · 14: Storage, Realtime, cola de emails y privilegios.
--
-- Qué hace: bucket adjuntos con políticas por organización y sede; ordenes_compra en
-- Realtime; cola pgmq 'emails'; y los privilegios de ejecución: authenticated ejecuta
-- las RPC de api y las funciones que usan las políticas y vistas; anon no ejecuta nada.
-- Dónde encaja: cierra la línea base v1. apps/api (Etapa 9) consume la cola con
-- service_role.

-- Storage -----------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('adjuntos', 'adjuntos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy adjuntos_lectura on storage.objects for select to authenticated
  using (bucket_id = 'adjuntos' and recepcion.ruta_adjunto_visible(name));

create policy adjuntos_subida on storage.objects for insert to authenticated
  with check (bucket_id = 'adjuntos' and recepcion.ruta_adjunto_escribible(name));

-- Realtime: la bandeja de Pendientes escucha altas y cambios de OC. Realtime respeta
-- RLS: cada cuenta recibe solo lo que puede leer.
alter publication supabase_realtime add table compras.ordenes_compra;

-- Cola de emails ----------------------------------------------------------------

select pgmq.create('emails');

-- Privilegios -------------------------------------------------------------------

revoke all on all functions in schema api from public, anon;
grant execute on all functions in schema api to authenticated;

revoke all on all tables in schema api from public, anon;
grant select on all tables in schema api to authenticated;

-- Vista interna que leen api.oc_saldos y las RPC (security_invoker: RLS de las tablas).
revoke all on compras.v_oc_saldos from public, anon;
grant select on compras.v_oc_saldos to authenticated;

-- Funciones que evalúan las políticas RLS, las vistas y Storage con los permisos de
-- quien consulta.
grant execute on function
  nucleo.es_miembro(uuid),
  nucleo.modulo_habilitado(uuid, text),
  nucleo.tiene_permiso(uuid, text, uuid),
  nucleo.puede_ver_sede(uuid, uuid),
  nucleo.comparte_organizacion(uuid),
  nucleo.nombre_cuenta(uuid),
  recepcion.checklist(uuid),
  recepcion.ruta_adjunto_visible(text),
  recepcion.ruta_adjunto_escribible(text),
  colab.puede_ver_sala(uuid)
to authenticated;
