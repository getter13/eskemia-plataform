-- Eskemia · Línea base v1 · 07: tipos y tablas de Recepción.
--
-- Qué hace: dispositivos, recepciones, ítems controlados, lecturas crudas y adjuntos
-- (fotos y firmas en Storage).
-- Dónde encaja: port fiel del estado final de db/legado/ con tenant_id → organizacion_id.
-- Productos, proveedores y órdenes de compra vienen de compras.

create type recepcion.estado_recepcion as enum (
  'ABIERTA', 'EN_CONTROL', 'CERRADA_OK', 'CERRADA_CON_DIFERENCIAS',
  'VALIDADA', 'INGRESADA_A_SISTEMA', 'RECHAZADA'
);
create type recepcion.tipo_lectura as enum ('ESCANEO', 'MANUAL', 'PESAJE');
create type recepcion.tipo_adjunto as enum (
  'REMITO', 'RECHAZO', 'MANUAL', 'FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA'
);
create type recepcion.tipo_diferencia as enum ('FALTANTE', 'SOBRANTE', 'RECHAZO', 'NO_PEDIDO', 'SUSTITUCION');

create table recepcion.dispositivos (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  sede_id         uuid not null,
  nombre          text not null,
  creado_en       timestamptz not null default now(),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id)
);

-- El id lo genera el cliente, para poder crear recepciones sin conexión.
create table recepcion.recepciones (
  id              uuid primary key,
  organizacion_id uuid not null,
  sede_id         uuid not null,
  estado          recepcion.estado_recepcion not null default 'ABIERTA',
  proveedor_id    uuid not null,
  nro_remito      text not null check (btrim(nro_remito) <> ''),
  oc_id           uuid,
  oc_numero       text,
  usuario_id      uuid not null references auth.users (id),
  abierta_en      timestamptz not null default now(),
  cerrada_en      timestamptz,
  validada_por    uuid references auth.users (id),
  validada_en     timestamptz,
  observacion     text,
  creado_en       timestamptz not null default now(),
  unique (organizacion_id, sede_id, id),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, proveedor_id) references compras.proveedores (organizacion_id, id),
  foreign key (organizacion_id, oc_id) references compras.ordenes_compra (organizacion_id, id)
);
create index recepciones_bandeja_idx on recepcion.recepciones (organizacion_id, sede_id, abierta_en desc);
create index recepciones_remito_idx on recepcion.recepciones
  (organizacion_id, proveedor_id, lower(btrim(nro_remito)));
create index recepciones_oc_idx on recepcion.recepciones (oc_id) where oc_id is not null;

-- Un mismo producto con otro lote o vencimiento es otra línea. cant_pedida: saldo de la
-- OC al abrir (en unidad de stock).
create table recepcion.recepcion_items (
  id                uuid primary key default gen_random_uuid(),
  organizacion_id   uuid not null,
  sede_id           uuid not null,
  recepcion_id      uuid not null,
  producto_id       uuid not null,
  cant_pedida       numeric(17, 3) check (cant_pedida >= 0),
  cant_remito       numeric(14, 3) check (cant_remito >= 0),
  cant_recibida     numeric(14, 3) not null default 0 check (cant_recibida >= 0),
  diferencia        numeric(14, 3) generated always as (cant_recibida - cant_remito) stored,
  tipo_diferencia   recepcion.tipo_diferencia,
  motivo_diferencia text,
  lote              text,
  vencimiento       date,
  creado_en         timestamptz not null default now(),
  unique (recepcion_id, id),
  unique nulls not distinct (recepcion_id, producto_id, lote, vencimiento),
  foreign key (organizacion_id, sede_id, recepcion_id)
    references recepcion.recepciones (organizacion_id, sede_id, id),
  foreign key (organizacion_id, producto_id) references compras.productos (organizacion_id, id)
);

-- Registro crudo: no se corrige. El botón "-" agrega una lectura con cantidad negativa.
create table recepcion.lecturas (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  sede_id         uuid not null,
  recepcion_id    uuid not null,
  item_id         uuid not null,
  tipo            recepcion.tipo_lectura not null,
  valor_crudo     text,
  producto_id     uuid not null,
  cantidad        numeric(14, 3) not null check (cantidad <> 0),
  motivo          text,
  dispositivo_id  uuid references recepcion.dispositivos (id),
  leido_en        timestamptz not null default now(),
  client_uuid     uuid not null unique,
  creado_en       timestamptz not null default now(),
  check (tipo <> 'ESCANEO' or valor_crudo is not null),
  check (tipo <> 'MANUAL' or coalesce(btrim(motivo), '') <> ''),
  foreign key (organizacion_id, sede_id, recepcion_id)
    references recepcion.recepciones (organizacion_id, sede_id, id),
  foreign key (recepcion_id, item_id) references recepcion.recepcion_items (recepcion_id, id),
  foreign key (organizacion_id, producto_id) references compras.productos (organizacion_id, id)
);
create index lecturas_recepcion_idx on recepcion.lecturas (recepcion_id, leido_en);

-- anulado_en conserva como evidencia las firmas reemplazadas.
-- storage_path: <organizacion_id>/<sede_id>/<recepcion_id>/<archivo> en el bucket adjuntos.
create table recepcion.adjuntos (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  sede_id         uuid not null,
  recepcion_id    uuid not null,
  item_id         uuid,
  tipo            recepcion.tipo_adjunto not null,
  storage_path    text not null unique,
  client_uuid     uuid not null unique,
  usuario_id      uuid not null references auth.users (id),
  creado_en       timestamptz not null default now(),
  anulado_en      timestamptz,
  foreign key (organizacion_id, sede_id, recepcion_id)
    references recepcion.recepciones (organizacion_id, sede_id, id),
  foreign key (recepcion_id, item_id) references recepcion.recepcion_items (recepcion_id, id)
);
create index adjuntos_recepcion_idx on recepcion.adjuntos (recepcion_id, tipo);
create unique index adjuntos_firma_vigente_idx on recepcion.adjuntos (recepcion_id, tipo)
  where tipo in ('FIRMA_RECEPTOR', 'FIRMA_TRANSPORTISTA') and anulado_en is null;

-- Saldo por OC y producto: lo pedido contra lo recibido en recepciones cerradas.
-- Interna (security_invoker): la usan las funciones de los dos módulos y api.oc_saldos.
create view compras.v_oc_saldos with (security_invoker = true) as
  select
    i.organizacion_id,
    i.sede_id,
    i.oc_id,
    i.producto_id,
    min(i.producto_nombre) as producto_nombre,
    min(i.sku) as sku,
    sum(i.cant_pedida) as cant_pedida,
    coalesce((
      select sum(ri.cant_recibida)
      from recepcion.recepcion_items ri
      join recepcion.recepciones r on r.id = ri.recepcion_id
      where r.oc_id = i.oc_id and ri.producto_id = i.producto_id
        and r.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS', 'VALIDADA', 'INGRESADA_A_SISTEMA')
    ), 0) as cant_recibida
  from compras.oc_items i
  group by i.organizacion_id, i.sede_id, i.oc_id, i.producto_id;
