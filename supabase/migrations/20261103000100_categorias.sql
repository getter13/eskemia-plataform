-- Eskemia · Recepción de Mercadería
-- Categorías de producto, para la carga manual por navegación en el kiosco.
-- sede_id nulo: compartida por todas las sedes del tenant, igual que productos.

create table public.categorias (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  sede_id   uuid,
  nombre    text not null check (btrim(nombre) <> ''),
  orden     int not null default 0,
  creado_en timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, nombre),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id)
);

-- Sin categoría es válido: así quedan las altas rápidas hasta que alguien las clasifique.
alter table public.productos
  add column categoria_id uuid,
  add foreign key (tenant_id, categoria_id) references public.categorias (tenant_id, id);

create index productos_categoria_idx on public.productos (tenant_id, categoria_id);

revoke all on public.categorias from public, anon, authenticated, service_role;
grant select on public.categorias to authenticated, service_role;

alter table public.categorias enable row level security;

create policy categorias_select on public.categorias
  for select to authenticated
  using (app_private.puede_ver_sede(tenant_id, sede_id));
