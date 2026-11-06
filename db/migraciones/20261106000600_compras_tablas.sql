-- Eskemia · Línea base v1 · 06: tipos y tablas de Compras.
--
-- Qué hace: catálogo (rubros, categorías, productos, presentaciones, códigos, proveedores,
-- relación producto–proveedor e historial de precios), pedidos, órdenes de compra,
-- reglas de aprobación, numeración y configuración.
-- Dónde encaja: port fiel del estado final de db/legado/ (19 migraciones), con
-- tenant_id → organizacion_id y configuracion_empresa → compras.configuracion.
-- El catálogo vive acá y Recepción lo usa (Recepción requiere Compras habilitado).

create type compras.tipo_medida as enum ('UNIDAD', 'PESO');
create type compras.unidad_stock as enum ('UN', 'KG', 'LT');
create type compras.tipo_codigo as enum ('EAN13', 'EAN8', 'DUN14', 'GS1_128', 'UPC', 'INTERNO');
create type compras.canal_envio as enum ('MANUAL', 'WHATSAPP', 'EMAIL');
create type compras.estado_pedido as enum ('BORRADOR', 'CONFIRMADO', 'DESCARTADO');
create type compras.estado_oc as enum (
  'PENDIENTE_APROBACION', 'APROBADA', 'RECHAZADA', 'ENVIADA',
  'RECIBIDA_PARCIAL', 'RECIBIDA', 'CERRADA', 'ANULADA'
);
create type compras.tipo_aprobacion as enum ('AUTOMATICA', 'AUTOAPROBADA', 'MANUAL');
create type compras.alcance_regla as enum ('EMPRESA', 'RUBRO', 'CATEGORIA', 'PRODUCTO');
create type compras.modo_regla as enum ('NUNCA', 'SIEMPRE', 'POR_MONTO');

/** Valida longitud y dígito verificador de GTIN-8/12/13/14. */
create function compras.gtin_valido(p_gtin text)
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

create table compras.rubros (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  nombre          text not null check (btrim(nombre) <> ''),
  orden           int not null default 0,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, nombre)
);

-- Un sector solo ve los rubros que tiene asignados (si tiene alguno).
create table compras.sector_rubros (
  organizacion_id uuid not null,
  sector_id       uuid not null,
  rubro_id        uuid not null,
  primary key (sector_id, rubro_id),
  foreign key (organizacion_id, sector_id) references nucleo.sectores (organizacion_id, id),
  foreign key (organizacion_id, rubro_id) references compras.rubros (organizacion_id, id)
);

-- sede_id nulo: compartido por todas las sedes.
create table compras.categorias (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  sede_id         uuid,
  rubro_id        uuid,
  nombre          text not null check (btrim(nombre) <> ''),
  orden           int not null default 0,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  unique (organizacion_id, id),
  unique nulls not distinct (organizacion_id, rubro_id, nombre),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, rubro_id) references compras.rubros (organizacion_id, id)
);
create index categorias_rubro_idx on compras.categorias (organizacion_id, rubro_id);

create table compras.proveedores (
  id                 uuid primary key default gen_random_uuid(),
  organizacion_id    uuid not null references nucleo.organizaciones (id),
  sede_id            uuid,
  nombre             text not null check (btrim(nombre) <> ''),
  cuit               text not null check (cuit ~ '^[0-9]{11}$'),
  codigo             text check (btrim(codigo) <> ''),
  contacto           text,
  telefono_whatsapp  text,
  email              text,
  canal_envio        compras.canal_envio not null default 'MANUAL',
  plazo_entrega_dias int check (plazo_entrega_dias >= 0),
  dias_pedido        int[] check (dias_pedido <@ array[0, 1, 2, 3, 4, 5, 6]),
  monto_minimo       numeric(14, 2) check (monto_minimo >= 0),
  activo             boolean not null default true,
  creado_en          timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, cuit),
  unique (organizacion_id, codigo),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id)
);

create table compras.productos (
  id                   uuid primary key default gen_random_uuid(),
  organizacion_id      uuid not null references nucleo.organizaciones (id),
  sede_id              uuid,
  categoria_id         uuid,
  gtin                 text check (gtin is null or compras.gtin_valido(gtin)),
  sku                  text check (btrim(sku) <> ''),
  nombre               text not null check (btrim(nombre) <> ''),
  tipo_medida          compras.tipo_medida not null default 'UNIDAD',
  unidad_stock         compras.unidad_stock not null,
  requiere_lote        boolean not null default false,
  requiere_vencimiento boolean not null default false,
  pendiente_validacion boolean not null default false,
  activo               boolean not null default true,
  creado_en            timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, gtin),
  unique (organizacion_id, sku),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, categoria_id) references compras.categorias (organizacion_id, id)
);
create index productos_categoria_idx on compras.productos (organizacion_id, categoria_id);

create table compras.presentaciones (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  producto_id     uuid not null,
  nombre          text not null check (btrim(nombre) <> ''),
  factor          numeric(14, 3) not null check (factor > 0),
  activa          boolean not null default true,
  creado_en       timestamptz not null default now(),
  unique (producto_id, nombre),
  unique (organizacion_id, producto_id, id),
  foreign key (organizacion_id, producto_id) references compras.productos (organizacion_id, id)
);

create table compras.producto_codigos (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  producto_id     uuid not null,
  presentacion_id uuid not null,
  codigo          text not null check (btrim(codigo) <> ''),
  tipo            compras.tipo_codigo not null,
  codigo_busqueda text generated always as (
    case when tipo in ('EAN13', 'EAN8', 'DUN14', 'UPC') then lpad(codigo, 14, '0') else codigo end
  ) stored,
  creado_en       timestamptz not null default now(),
  check (tipo not in ('EAN13', 'EAN8', 'DUN14', 'UPC') or compras.gtin_valido(codigo)),
  unique (organizacion_id, codigo_busqueda),
  foreign key (organizacion_id, producto_id, presentacion_id)
    references compras.presentaciones (organizacion_id, producto_id, id)
);
create index producto_codigos_producto_idx on compras.producto_codigos (producto_id);

create table compras.producto_proveedor (
  id               uuid primary key default gen_random_uuid(),
  organizacion_id  uuid not null,
  producto_id      uuid not null,
  proveedor_id     uuid not null,
  presentacion_id  uuid not null,
  codigo_proveedor text,
  precio_actual    numeric(14, 2) check (precio_actual >= 0),
  preferido        boolean not null default false,
  activo           boolean not null default true,
  creado_en        timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (producto_id, proveedor_id, presentacion_id),
  foreign key (organizacion_id, producto_id, presentacion_id)
    references compras.presentaciones (organizacion_id, producto_id, id),
  foreign key (organizacion_id, proveedor_id) references compras.proveedores (organizacion_id, id)
);
create unique index producto_proveedor_preferido_idx on compras.producto_proveedor (producto_id)
  where preferido and activo;
create index producto_proveedor_proveedor_idx on compras.producto_proveedor (proveedor_id);

create table compras.precios_historial (
  id                    uuid primary key default gen_random_uuid(),
  organizacion_id       uuid not null,
  producto_proveedor_id uuid not null,
  precio                numeric(14, 2) not null check (precio >= 0),
  vigente_desde         timestamptz not null default now(),
  usuario_id            uuid references auth.users (id),
  foreign key (organizacion_id, producto_proveedor_id)
    references compras.producto_proveedor (organizacion_id, id)
);
create index precios_historial_idx on compras.precios_historial (producto_proveedor_id, vigente_desde desc);

create table compras.pedidos_compra (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  sede_id         uuid not null,
  estado          compras.estado_pedido not null default 'BORRADOR',
  usuario_id      uuid not null references auth.users (id),
  sector_id       uuid,
  request_uuid    uuid not null,
  creado_en       timestamptz not null default now(),
  confirmado_en   timestamptz,
  unique (organizacion_id, id),
  unique (organizacion_id, request_uuid),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, sector_id) references nucleo.sectores (organizacion_id, id)
);
create index pedidos_compra_usuario_idx on compras.pedidos_compra (usuario_id, creado_en desc);

create table compras.pedido_items (
  id                    uuid primary key default gen_random_uuid(),
  organizacion_id       uuid not null,
  pedido_id             uuid not null,
  producto_proveedor_id uuid not null,
  presentacion_id       uuid not null references compras.presentaciones (id),
  cantidad              numeric(14, 3) not null check (cantidad > 0),
  unique (pedido_id, producto_proveedor_id),
  foreign key (organizacion_id, pedido_id) references compras.pedidos_compra (organizacion_id, id),
  foreign key (organizacion_id, producto_proveedor_id)
    references compras.producto_proveedor (organizacion_id, id)
);

create table compras.ordenes_compra (
  id                     uuid primary key default gen_random_uuid(),
  organizacion_id        uuid not null,
  sede_id                uuid not null,
  proveedor_id           uuid not null,
  pedido_id              uuid,
  numero                 text not null,
  estado                 compras.estado_oc not null,
  usuario_id             uuid not null references auth.users (id),
  requiere_aprobacion    boolean not null,
  nivel_requerido        int not null default 0,
  tipo_aprobacion        compras.tipo_aprobacion,
  aprobada_por           uuid references auth.users (id),
  aprobada_en            timestamptz,
  motivo_rechazo         text,
  reglas_aplicadas       jsonb not null default '{}'::jsonb,
  fecha_entrega_estimada date,
  total_estimado         numeric(14, 2) not null default 0,
  enviada_en             timestamptz,
  canal_envio            compras.canal_envio,
  motivo_cierre          text,
  creado_en              timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, numero),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, proveedor_id) references compras.proveedores (organizacion_id, id),
  foreign key (organizacion_id, pedido_id) references compras.pedidos_compra (organizacion_id, id)
);
create index ordenes_compra_sede_idx on compras.ordenes_compra (organizacion_id, sede_id, estado);
create index ordenes_compra_usuario_idx on compras.ordenes_compra (usuario_id, creado_en desc);

-- cant_pedida está en unidad de stock: cantidad de presentaciones × factor.
create table compras.oc_items (
  id                    uuid primary key default gen_random_uuid(),
  organizacion_id       uuid not null,
  sede_id               uuid not null,
  oc_id                 uuid not null,
  producto_id           uuid not null,
  cantidad              numeric(14, 3) not null check (cantidad > 0),
  producto_proveedor_id uuid,
  presentacion_id       uuid references compras.presentaciones (id),
  producto_nombre       text not null,
  sku                   text,
  presentacion_nombre   text not null,
  factor                numeric(14, 3) not null check (factor > 0),
  cant_pedida           numeric(17, 3) generated always as (cantidad * factor) stored,
  precio_unitario       numeric(14, 2),
  subtotal              numeric(14, 2) not null default 0,
  disparo_aprobacion    boolean not null default false,
  unique (organizacion_id, id),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, oc_id) references compras.ordenes_compra (organizacion_id, id),
  foreign key (organizacion_id, producto_id) references compras.productos (organizacion_id, id),
  foreign key (organizacion_id, producto_proveedor_id) references compras.producto_proveedor (organizacion_id, id)
);
create index oc_items_oc_idx on compras.oc_items (oc_id);

create table compras.reglas_aprobacion (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  alcance         compras.alcance_regla not null,
  alcance_id      uuid,
  modo            compras.modo_regla not null,
  monto_umbral    numeric(14, 2) check (monto_umbral >= 0),
  nivel_requerido int not null default 0,
  activa          boolean not null default true,
  creado_en       timestamptz not null default now(),
  check ((alcance = 'EMPRESA') = (alcance_id is null)),
  check ((modo = 'POR_MONTO') = (monto_umbral is not null)),
  check ((modo = 'NUNCA' and nivel_requerido = 0) or (modo <> 'NUNCA' and nivel_requerido >= 1)),
  unique nulls not distinct (organizacion_id, alcance, alcance_id)
);

create table compras.secuencias (
  organizacion_id uuid not null references nucleo.organizaciones (id),
  sede_id         uuid not null,
  tipo            text not null,
  anio            int not null,
  ultimo_numero   bigint not null,
  primary key (organizacion_id, sede_id, tipo, anio),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id)
);

-- Sin fila = valores por defecto (permitir_autoaprobacion = true), como en el legado.
create table compras.configuracion (
  organizacion_id         uuid primary key references nucleo.organizaciones (id),
  permitir_autoaprobacion boolean not null default true,
  actualizado_en          timestamptz not null default now()
);

-- Triggers de productos: unidad de stock por defecto y presentación base.

/** Trigger: completa unidad_stock según tipo_medida si no vino. */
create function compras.productos_unidad_stock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.unidad_stock := coalesce(
    new.unidad_stock,
    case new.tipo_medida when 'PESO' then 'KG'::compras.unidad_stock else 'UN'::compras.unidad_stock end
  );
  return new;
end;
$$;

/** Nombre de la presentación base según la unidad de stock. */
create function compras.nombre_presentacion_base(p_unidad compras.unidad_stock)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_unidad when 'KG' then 'Kilo' when 'LT' then 'Litro' else 'Unidad' end;
$$;

/** Tipo de código según el largo del GTIN. */
create function compras.tipo_gtin(p_gtin text)
returns compras.tipo_codigo
language sql
immutable
set search_path = ''
as $$
  select (case length(p_gtin)
    when 8 then 'EAN8' when 12 then 'UPC' when 13 then 'EAN13' else 'DUN14'
  end)::compras.tipo_codigo;
$$;

/** Trigger: todo producto nace con su presentación base (factor 1) y, si trae GTIN,
 *  con su código. */
create function compras.productos_presentacion_base()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_presentacion uuid;
begin
  insert into compras.presentaciones (organizacion_id, producto_id, nombre, factor)
  values (new.organizacion_id, new.id, compras.nombre_presentacion_base(new.unidad_stock), 1)
  returning id into v_presentacion;

  if new.gtin is not null then
    insert into compras.producto_codigos (organizacion_id, producto_id, presentacion_id, codigo, tipo)
    values (new.organizacion_id, new.id, v_presentacion, new.gtin, compras.tipo_gtin(new.gtin));
  end if;
  return null;
end;
$$;

create trigger productos_unidad_stock before insert on compras.productos
  for each row execute function compras.productos_unidad_stock();
create trigger productos_presentacion_base after insert on compras.productos
  for each row execute function compras.productos_presentacion_base();
