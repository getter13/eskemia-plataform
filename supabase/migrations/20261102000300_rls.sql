-- Eskemia · Recepción de Mercadería
-- 3/6: permisos y RLS por tenant y rol.
--
-- Regla: desde la API las tablas son de solo lectura y RLS filtra lo visible.
-- Toda escritura pasa por las funciones RPC.

create function app_private.tenant_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.tenant_id from public.perfiles p
  where p.user_id = (select auth.uid()) and p.activo;
$$;

create function app_private.sede_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.sede_id from public.perfiles p
  where p.user_id = (select auth.uid()) and p.activo;
$$;

create function app_private.rol_actual()
returns public.rol_usuario
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol from public.perfiles p
  where p.user_id = (select auth.uid()) and p.activo;
$$;

-- Admin ve todo su tenant. El resto, su sede y los catálogos compartidos (sede nula).
create function app_private.puede_ver_sede(p_tenant_id uuid, p_sede_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_tenant_id = app_private.tenant_actual()
    and (
      app_private.rol_actual() = 'admin'
      or p_sede_id is null
      or p_sede_id = app_private.sede_actual()
    ),
    false
  );
$$;

revoke all on all functions in schema app_private from public;
grant usage on schema app_private to authenticated, service_role;
grant execute on function app_private.tenant_actual() to authenticated, service_role;
grant execute on function app_private.sede_actual() to authenticated, service_role;
grant execute on function app_private.rol_actual() to authenticated, service_role;
grant execute on function app_private.puede_ver_sede(uuid, uuid) to authenticated, service_role;

-- Sin escritura directa para nadie: tampoco service_role, ni sobre eventos.
revoke all on all tables in schema public from public, anon, authenticated, service_role;
grant select on all tables in schema public to authenticated, service_role;

alter table public.tenants         enable row level security;
alter table public.sedes           enable row level security;
alter table public.perfiles        enable row level security;
alter table public.dispositivos    enable row level security;
alter table public.proveedores     enable row level security;
alter table public.productos       enable row level security;
alter table public.ordenes_compra  enable row level security;
alter table public.oc_items        enable row level security;
alter table public.recepciones     enable row level security;
alter table public.recepcion_items enable row level security;
alter table public.lecturas        enable row level security;
alter table public.adjuntos        enable row level security;
alter table public.eventos         enable row level security;

create policy tenants_select on public.tenants
  for select to authenticated
  using (id = app_private.tenant_actual());

create policy sedes_select on public.sedes
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, id));

-- Cada usuario ve su perfil. Supervisor y admin ven también los de su alcance.
create policy perfiles_select on public.perfiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      app_private.rol_actual() in ('supervisor', 'admin')
      and app_private.puede_ver_sede(tenant_id, sede_id)
    )
  );

create policy dispositivos_select on public.dispositivos
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy proveedores_select on public.proveedores
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy productos_select on public.productos
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy ordenes_compra_select on public.ordenes_compra
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy oc_items_select on public.oc_items
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy recepciones_select on public.recepciones
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy recepcion_items_select on public.recepcion_items
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy lecturas_select on public.lecturas
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

create policy adjuntos_select on public.adjuntos
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));

-- La línea de tiempo es del back: el operario no la lee.
create policy eventos_select on public.eventos
  for select to authenticated
  using (
    app_private.rol_actual() in ('supervisor', 'admin')
    and app_private.puede_ver_sede(tenant_id, sede_id)
  );
