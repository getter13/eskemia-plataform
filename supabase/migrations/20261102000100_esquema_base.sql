-- Eskemia · Recepción de Mercadería
-- 1/6: extensiones, tipos y tablas.

create extension if not exists pgcrypto with schema extensions;

-- Funciones internas: este esquema no se expone por la API.
create schema if not exists app_private;
revoke all on schema app_private from public;

create type public.rol_usuario as enum ('operario', 'supervisor', 'admin');
create type public.tipo_medida as enum ('UNIDAD', 'PESO');
create type public.estado_recepcion as enum (
  'ABIERTA', 'EN_CONTROL', 'CERRADA_OK', 'CERRADA_CON_DIFERENCIAS',
  'VALIDADA', 'INGRESADA_A_SISTEMA', 'RECHAZADA'
);
create type public.tipo_lectura as enum ('ESCANEO', 'MANUAL', 'PESAJE');
create type public.tipo_adjunto as enum (
  'REMITO', 'RECHAZO', 'MANUAL', 'FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA'
);
create type public.tipo_diferencia as enum ('FALTANTE', 'SOBRANTE', 'RECHAZO');

-- Valida longitud y dígito verificador de GTIN-8/12/13/14.
create function app_private.gtin_valido(p_gtin text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_largo int;
  v_suma int := 0;
begin
  if p_gtin is null or p_gtin !~ '^([0-9]{8}|[0-9]{12,14})$' then
    return false;
  end if;
  v_largo := length(p_gtin);
  for i in 1 .. v_largo - 1 loop
    v_suma := v_suma
      + substr(p_gtin, v_largo - i, 1)::int * (case when i % 2 = 1 then 3 else 1 end);
  end loop;
  return (10 - v_suma % 10) % 10 = substr(p_gtin, v_largo, 1)::int;
end;
$$;

create table public.tenants (
  id        uuid primary key default gen_random_uuid(),
  nombre    text not null check (btrim(nombre) <> ''),
  creado_en timestamptz not null default now()
);

create table public.sedes (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  nombre    text not null check (btrim(nombre) <> ''),
  creado_en timestamptz not null default now(),
  unique (tenant_id, id)
);

-- sede_id nulo: solo admin, con alcance sobre todas las sedes del tenant.
create table public.perfiles (
  user_id   uuid primary key references auth.users (id),
  tenant_id uuid not null references public.tenants (id),
  sede_id   uuid,
  rol       public.rol_usuario not null,
  nombre    text not null,
  activo    boolean not null default true,
  creado_en timestamptz not null default now(),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  check (rol = 'admin' or sede_id is not null)
);

create table public.dispositivos (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  sede_id   uuid not null,
  nombre    text not null,
  creado_en timestamptz not null default now(),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id)
);

-- Catálogos: sede_id nulo significa compartido por todas las sedes del tenant.
create table public.proveedores (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  sede_id   uuid,
  nombre    text not null check (btrim(nombre) <> ''),
  cuit      text not null check (cuit ~ '^[0-9]{11}$'),
  creado_en timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, cuit),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id)
);

create table public.productos (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.tenants (id),
  sede_id              uuid,
  gtin                 text check (gtin is null or app_private.gtin_valido(gtin)),
  nombre               text not null check (btrim(nombre) <> ''),
  tipo_medida          public.tipo_medida not null default 'UNIDAD',
  requiere_lote        boolean not null default false,
  requiere_vencimiento boolean not null default false,
  pendiente_validacion boolean not null default false,
  creado_en            timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, gtin),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id)
);

-- Vacías en el MVP: las alimentará el módulo Compras.
create table public.ordenes_compra (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  sede_id      uuid not null,
  proveedor_id uuid not null,
  numero       text not null,
  creado_en    timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  foreign key (tenant_id, proveedor_id) references public.proveedores (tenant_id, id)
);

create table public.oc_items (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  sede_id     uuid not null,
  oc_id       uuid not null,
  producto_id uuid not null,
  cantidad    numeric(14, 3) not null check (cantidad > 0),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  foreign key (tenant_id, oc_id) references public.ordenes_compra (tenant_id, id),
  foreign key (tenant_id, producto_id) references public.productos (tenant_id, id)
);

-- El id lo genera el cliente, para poder crear recepciones sin conexión.
create table public.recepciones (
  id           uuid primary key,
  tenant_id    uuid not null,
  sede_id      uuid not null,
  estado       public.estado_recepcion not null default 'ABIERTA',
  proveedor_id uuid not null,
  nro_remito   text not null check (btrim(nro_remito) <> ''),
  oc_id        uuid,
  usuario_id   uuid not null references auth.users (id),
  abierta_en   timestamptz not null default now(),
  cerrada_en   timestamptz,
  validada_por uuid references auth.users (id),
  validada_en  timestamptz,
  observacion  text,
  creado_en    timestamptz not null default now(),
  unique (tenant_id, sede_id, id),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  foreign key (tenant_id, proveedor_id) references public.proveedores (tenant_id, id),
  foreign key (tenant_id, oc_id) references public.ordenes_compra (tenant_id, id)
);
create index recepciones_bandeja_idx on public.recepciones (tenant_id, sede_id, abierta_en desc);
create index recepciones_remito_idx on public.recepciones
  (tenant_id, proveedor_id, lower(btrim(nro_remito)));

-- Un mismo producto con otro lote o vencimiento es otra línea.
create table public.recepcion_items (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null,
  sede_id           uuid not null,
  recepcion_id      uuid not null,
  producto_id       uuid not null,
  cant_remito       numeric(14, 3) check (cant_remito >= 0),
  cant_recibida     numeric(14, 3) not null default 0 check (cant_recibida >= 0),
  diferencia        numeric(14, 3) generated always as (cant_recibida - cant_remito) stored,
  tipo_diferencia   public.tipo_diferencia,
  motivo_diferencia text,
  lote              text,
  vencimiento       date,
  creado_en         timestamptz not null default now(),
  unique (recepcion_id, id),
  unique nulls not distinct (recepcion_id, producto_id, lote, vencimiento),
  foreign key (tenant_id, sede_id, recepcion_id)
    references public.recepciones (tenant_id, sede_id, id),
  foreign key (tenant_id, producto_id) references public.productos (tenant_id, id)
);

-- Registro crudo: no se corrige. El botón "-" agrega una lectura con cantidad negativa.
create table public.lecturas (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null,
  sede_id        uuid not null,
  recepcion_id   uuid not null,
  item_id        uuid not null,
  tipo           public.tipo_lectura not null,
  valor_crudo    text,
  producto_id    uuid not null,
  cantidad       numeric(14, 3) not null check (cantidad <> 0),
  motivo         text,
  dispositivo_id uuid references public.dispositivos (id),
  leido_en       timestamptz not null default now(),
  client_uuid    uuid not null unique,
  creado_en      timestamptz not null default now(),
  check (tipo <> 'ESCANEO' or valor_crudo is not null),
  check (tipo <> 'MANUAL' or coalesce(btrim(motivo), '') <> ''),
  foreign key (tenant_id, sede_id, recepcion_id)
    references public.recepciones (tenant_id, sede_id, id),
  foreign key (recepcion_id, item_id) references public.recepcion_items (recepcion_id, id),
  foreign key (tenant_id, producto_id) references public.productos (tenant_id, id)
);
create index lecturas_recepcion_idx on public.lecturas (recepcion_id, leido_en);

-- anulado_en conserva como evidencia las firmas reemplazadas.
create table public.adjuntos (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null,
  sede_id      uuid not null,
  recepcion_id uuid not null,
  item_id      uuid,
  tipo         public.tipo_adjunto not null,
  storage_path text not null unique,
  client_uuid  uuid not null unique,
  usuario_id   uuid not null references auth.users (id),
  creado_en    timestamptz not null default now(),
  anulado_en   timestamptz,
  foreign key (tenant_id, sede_id, recepcion_id)
    references public.recepciones (tenant_id, sede_id, id),
  foreign key (recepcion_id, item_id) references public.recepcion_items (recepcion_id, id)
);
create index adjuntos_recepcion_idx on public.adjuntos (recepcion_id, tipo);
create unique index adjuntos_firma_vigente_idx on public.adjuntos (recepcion_id, tipo)
  where tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA') and anulado_en is null;

-- Append-only. secuencia, hash_prev, hash y creado_en los asigna un trigger.
create table public.eventos (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.tenants (id),
  sede_id        uuid,
  secuencia      bigint not null,
  entidad        text not null,
  entidad_id     uuid not null,
  accion         text not null,
  payload        jsonb not null default '{}'::jsonb,
  usuario_id     uuid,
  dispositivo_id uuid,
  creado_en      timestamptz not null default clock_timestamp(),
  hash_prev      text,
  hash           text not null,
  unique (tenant_id, secuencia)
);
create index eventos_entidad_idx on public.eventos (entidad, entidad_id, creado_en);
