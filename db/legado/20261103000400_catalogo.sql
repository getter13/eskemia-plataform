-- Eskemia · Catálogo de Compras (plan de Compras, etapa 2).
-- Orden: Rubro -> Categoría -> Producto -> Proveedor. El rubro del producto se deriva de su categoría.
-- El kiosco sigue con tipo_medida y gtin hasta la etapa 8.

create type public.unidad_stock as enum ('UN', 'KG', 'LT');
create type public.tipo_codigo as enum ('EAN13', 'EAN8', 'DUN14', 'GS1_128', 'UPC', 'INTERNO');
create type public.canal_envio as enum ('MANUAL', 'WHATSAPP', 'EMAIL');

create table public.rubros (
  id        uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id),
  nombre    text not null check (btrim(nombre) <> ''),
  orden     int not null default 0,
  activo    boolean not null default true,
  creado_en timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, nombre)
);

-- Qué rubros ve cada sector en el marketplace. Sin filas: el sector ve todos.
create table public.sector_rubros (
  tenant_id uuid not null,
  sector_id uuid not null,
  rubro_id  uuid not null,
  primary key (sector_id, rubro_id),
  foreign key (tenant_id, sector_id) references public.sectores (tenant_id, id),
  foreign key (tenant_id, rubro_id) references public.rubros (tenant_id, id)
);

-- Rubro nulo: categoría anterior a esta migración, todavía sin clasificar.
alter table public.categorias
  add column rubro_id uuid,
  add column activo boolean not null default true,
  add foreign key (tenant_id, rubro_id) references public.rubros (tenant_id, id),
  drop constraint categorias_tenant_id_nombre_key,
  add unique nulls not distinct (tenant_id, rubro_id, nombre);

create index categorias_rubro_idx on public.categorias (tenant_id, rubro_id);

alter table public.productos
  add column unidad_stock public.unidad_stock,
  add column activo boolean not null default true;

update public.productos
set unidad_stock = case tipo_medida when 'PESO' then 'KG'::public.unidad_stock else 'UN'::public.unidad_stock end;

alter table public.productos alter column unidad_stock set not null;

-- factor: cuántas unidades de stock trae la presentación.
create table public.presentaciones (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null,
  producto_id uuid not null,
  nombre      text not null check (btrim(nombre) <> ''),
  factor      numeric(14, 3) not null check (factor > 0),
  activa      boolean not null default true,
  creado_en   timestamptz not null default now(),
  unique (tenant_id, producto_id, id),
  unique (producto_id, nombre),
  foreign key (tenant_id, producto_id) references public.productos (tenant_id, id)
);

-- codigo_busqueda iguala un mismo GTIN escrito con 8, 12, 13 o 14 dígitos, como hace el kiosco.
create table public.producto_codigos (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  producto_id     uuid not null,
  presentacion_id uuid not null,
  codigo          text not null check (btrim(codigo) <> ''),
  tipo            public.tipo_codigo not null,
  codigo_busqueda text generated always as (
    case when tipo in ('EAN13', 'EAN8', 'DUN14', 'UPC') then lpad(codigo, 14, '0') else codigo end
  ) stored,
  creado_en       timestamptz not null default now(),
  unique (tenant_id, codigo_busqueda),
  check (tipo not in ('EAN13', 'EAN8', 'DUN14', 'UPC') or app_private.gtin_valido(codigo)),
  foreign key (tenant_id, producto_id, presentacion_id)
    references public.presentaciones (tenant_id, producto_id, id)
);
create index producto_codigos_producto_idx on public.producto_codigos (producto_id);

alter table public.proveedores
  add column contacto text,
  add column telefono_whatsapp text,
  add column email text,
  add column canal_envio public.canal_envio not null default 'MANUAL',
  add column plazo_entrega_dias int check (plazo_entrega_dias >= 0),
  add column dias_pedido int[] check (dias_pedido <@ array[0, 1, 2, 3, 4, 5, 6]),
  add column monto_minimo numeric(14, 2) check (monto_minimo >= 0),
  add column activo boolean not null default true;

create table public.producto_proveedor (
  id               uuid primary key default gen_random_uuid(),
  tenant_id        uuid not null,
  producto_id      uuid not null,
  proveedor_id     uuid not null,
  presentacion_id  uuid not null,
  codigo_proveedor text,
  precio_actual    numeric(14, 2) check (precio_actual >= 0),
  preferido        boolean not null default false,
  activo           boolean not null default true,
  creado_en        timestamptz not null default now(),
  unique (tenant_id, id),
  unique (producto_id, proveedor_id, presentacion_id),
  foreign key (tenant_id, proveedor_id) references public.proveedores (tenant_id, id),
  foreign key (tenant_id, producto_id, presentacion_id)
    references public.presentaciones (tenant_id, producto_id, id)
);
create unique index producto_proveedor_preferido_idx on public.producto_proveedor (producto_id)
  where preferido and activo;
create index producto_proveedor_proveedor_idx on public.producto_proveedor (proveedor_id);

create table public.precios_historial (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  producto_proveedor_id uuid not null,
  precio                numeric(14, 2) not null check (precio >= 0),
  vigente_desde         timestamptz not null default now(),
  usuario_id            uuid references auth.users (id),
  foreign key (tenant_id, producto_proveedor_id) references public.producto_proveedor (tenant_id, id)
);
create index precios_historial_idx on public.precios_historial (producto_proveedor_id, vigente_desde desc);

-- ---------------------------------------------------------------------------
-- Productos existentes y altas rápidas del kiosco
-- ---------------------------------------------------------------------------

create function app_private.nombre_presentacion_base(p_unidad public.unidad_stock)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_unidad when 'KG' then 'Kilo' when 'LT' then 'Litro' else 'Unidad' end;
$$;

create function app_private.tipo_gtin(p_gtin text)
returns public.tipo_codigo
language sql
immutable
set search_path = ''
as $$
  select (case length(p_gtin)
    when 8 then 'EAN8' when 12 then 'UPC' when 13 then 'EAN13' else 'DUN14'
  end)::public.tipo_codigo;
$$;

insert into public.presentaciones (tenant_id, producto_id, nombre, factor)
select p.tenant_id, p.id, app_private.nombre_presentacion_base(p.unidad_stock), 1
from public.productos p;

insert into public.producto_codigos (tenant_id, producto_id, presentacion_id, codigo, tipo)
select p.tenant_id, p.id, pr.id, p.gtin, app_private.tipo_gtin(p.gtin)
from public.productos p
join public.presentaciones pr on pr.producto_id = p.id
where p.gtin is not null;

-- La RPC de alta rápida solo conoce tipo_medida.
create function app_private.productos_unidad_stock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.unidad_stock := coalesce(
    new.unidad_stock,
    case new.tipo_medida when 'PESO' then 'KG'::public.unidad_stock else 'UN'::public.unidad_stock end
  );
  return new;
end;
$$;

create trigger productos_unidad_stock
  before insert on public.productos
  for each row execute function app_private.productos_unidad_stock();

-- Todo producto nace con su presentación base, y con su código si trae GTIN.
create function app_private.productos_presentacion_base()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_presentacion uuid;
begin
  insert into public.presentaciones (tenant_id, producto_id, nombre, factor)
  values (new.tenant_id, new.id, app_private.nombre_presentacion_base(new.unidad_stock), 1)
  returning id into v_presentacion;

  if new.gtin is not null then
    insert into public.producto_codigos (tenant_id, producto_id, presentacion_id, codigo, tipo)
    values (new.tenant_id, new.id, v_presentacion, new.gtin, app_private.tipo_gtin(new.gtin));
  end if;
  return null;
end;
$$;

create trigger productos_presentacion_base
  after insert on public.productos
  for each row execute function app_private.productos_presentacion_base();

-- ---------------------------------------------------------------------------
-- Escritura del catálogo. Las usarán la importación CSV y el módulo de Administración.
-- Son idempotentes por id: reintentarlas deja el mismo resultado.
-- ---------------------------------------------------------------------------

create function public.guardar_rubro(
  p_id uuid,
  p_nombre text,
  p_orden int default 0,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
begin
  insert into public.rubros (id, tenant_id, nombre, orden, activo)
  values (p_id, v_perfil.tenant_id, btrim(p_nombre), p_orden, p_activo)
  on conflict (id) do update
    set nombre = excluded.nombre, orden = excluded.orden, activo = excluded.activo
    where public.rubros.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: rubro inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'rubro', p_id, 'guardado',
    jsonb_build_object('nombre', btrim(p_nombre), 'orden', p_orden, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ya existe un rubro con ese nombre' using errcode = 'P0001';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre del rubro' using errcode = 'P0001';
end;
$$;

create function public.guardar_categoria(
  p_id uuid,
  p_rubro_id uuid,
  p_nombre text,
  p_orden int default 0,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
begin
  if p_rubro_id is null then
    raise exception 'PRECONDICION: la categoría necesita un rubro' using errcode = 'P0001';
  end if;

  insert into public.categorias (id, tenant_id, rubro_id, nombre, orden, activo)
  values (p_id, v_perfil.tenant_id, p_rubro_id, btrim(p_nombre), p_orden, p_activo)
  on conflict (id) do update
    set rubro_id = excluded.rubro_id, nombre = excluded.nombre,
        orden = excluded.orden, activo = excluded.activo
    where public.categorias.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: categoría inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'categoria', p_id, 'guardada',
    jsonb_build_object('rubro_id', p_rubro_id, 'nombre', btrim(p_nombre), 'orden', p_orden, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese rubro ya tiene una categoría con ese nombre' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: rubro inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre de la categoría' using errcode = 'P0001';
end;
$$;

-- Guardarlo lo da por validado: deja de estar pendiente aunque venga de una alta rápida.
create function public.guardar_producto(
  p_id uuid,
  p_categoria_id uuid,
  p_nombre text,
  p_unidad_stock public.unidad_stock default 'UN',
  p_requiere_lote boolean default false,
  p_requiere_vencimiento boolean default false,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
  v_medida public.tipo_medida :=
    case when p_unidad_stock = 'UN' then 'UNIDAD'::public.tipo_medida else 'PESO'::public.tipo_medida end;
begin
  if p_categoria_id is null then
    raise exception 'PRECONDICION: el producto necesita una categoría' using errcode = 'P0001';
  end if;

  insert into public.productos
    (id, tenant_id, categoria_id, nombre, unidad_stock, tipo_medida,
     requiere_lote, requiere_vencimiento, activo)
  values
    (p_id, v_perfil.tenant_id, p_categoria_id, btrim(p_nombre), p_unidad_stock, v_medida,
     p_requiere_lote, p_requiere_vencimiento, p_activo)
  on conflict (id) do update
    set categoria_id = excluded.categoria_id,
        nombre = excluded.nombre,
        unidad_stock = excluded.unidad_stock,
        tipo_medida = excluded.tipo_medida,
        requiere_lote = excluded.requiere_lote,
        requiere_vencimiento = excluded.requiere_vencimiento,
        activo = excluded.activo,
        pendiente_validacion = false
    where public.productos.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'producto', p_id, 'guardado',
    jsonb_build_object(
      'categoria_id', p_categoria_id, 'nombre', btrim(p_nombre), 'unidad_stock', p_unidad_stock,
      'activo', p_activo
    )
  );
  return p_id;
exception
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: categoría inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: falta el nombre del producto' using errcode = 'P0001';
end;
$$;

create function public.guardar_presentacion(
  p_id uuid,
  p_producto_id uuid,
  p_nombre text,
  p_factor numeric,
  p_activa boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
begin
  insert into public.presentaciones (id, tenant_id, producto_id, nombre, factor, activa)
  values (p_id, v_perfil.tenant_id, p_producto_id, btrim(p_nombre), p_factor, p_activa)
  on conflict (id) do update
    set nombre = excluded.nombre, factor = excluded.factor, activa = excluded.activa
    where public.presentaciones.tenant_id = excluded.tenant_id
      and public.presentaciones.producto_id = excluded.producto_id;
  if not found then
    raise exception 'NO_ENCONTRADO: presentación inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'presentacion', p_id, 'guardada',
    jsonb_build_object('producto_id', p_producto_id, 'nombre', btrim(p_nombre), 'factor', p_factor, 'activa', p_activa)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: el producto ya tiene una presentación con ese nombre' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: la presentación necesita nombre y un factor mayor a cero' using errcode = 'P0001';
end;
$$;

create function public.guardar_codigo(
  p_id uuid,
  p_producto_id uuid,
  p_presentacion_id uuid,
  p_codigo text,
  p_tipo public.tipo_codigo
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
begin
  insert into public.producto_codigos (id, tenant_id, producto_id, presentacion_id, codigo, tipo)
  values (p_id, v_perfil.tenant_id, p_producto_id, p_presentacion_id, btrim(p_codigo), p_tipo)
  on conflict (id) do update
    set producto_id = excluded.producto_id,
        presentacion_id = excluded.presentacion_id,
        codigo = excluded.codigo,
        tipo = excluded.tipo
    where public.producto_codigos.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: código inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'producto_codigo', p_id, 'guardado',
    jsonb_build_object(
      'producto_id', p_producto_id, 'presentacion_id', p_presentacion_id,
      'codigo', btrim(p_codigo), 'tipo', p_tipo
    )
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese código ya está asignado a un producto' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: la presentación no corresponde al producto' using errcode = 'P0002';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: el código no es válido para ese tipo' using errcode = 'P0001';
end;
$$;

create function public.guardar_proveedor(
  p_id uuid,
  p_nombre text,
  p_cuit text,
  p_contacto text default null,
  p_telefono_whatsapp text default null,
  p_email text default null,
  p_canal_envio public.canal_envio default 'MANUAL',
  p_plazo_entrega_dias int default null,
  p_dias_pedido int[] default null,
  p_monto_minimo numeric default null,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
  v_cuit text := regexp_replace(coalesce(p_cuit, ''), '[^0-9]', '', 'g');
begin
  if v_cuit !~ '^[0-9]{11}$' then
    raise exception 'PRECONDICION: el CUIT debe tener 11 dígitos' using errcode = 'P0001';
  end if;

  insert into public.proveedores
    (id, tenant_id, nombre, cuit, contacto, telefono_whatsapp, email, canal_envio,
     plazo_entrega_dias, dias_pedido, monto_minimo, activo)
  values
    (p_id, v_perfil.tenant_id, btrim(p_nombre), v_cuit, p_contacto, p_telefono_whatsapp, p_email,
     p_canal_envio, p_plazo_entrega_dias, p_dias_pedido, p_monto_minimo, p_activo)
  on conflict (id) do update
    set nombre = excluded.nombre,
        cuit = excluded.cuit,
        contacto = excluded.contacto,
        telefono_whatsapp = excluded.telefono_whatsapp,
        email = excluded.email,
        canal_envio = excluded.canal_envio,
        plazo_entrega_dias = excluded.plazo_entrega_dias,
        dias_pedido = excluded.dias_pedido,
        monto_minimo = excluded.monto_minimo,
        activo = excluded.activo
    where public.proveedores.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: proveedor inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'proveedor', p_id, 'guardado',
    jsonb_build_object('nombre', btrim(p_nombre), 'cuit', v_cuit, 'canal_envio', p_canal_envio, 'activo', p_activo)
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ya existe un proveedor con ese CUIT' using errcode = 'P0001';
  when not_null_violation or check_violation then
    raise exception 'PRECONDICION: revisá el nombre, el plazo, los días de pedido y el monto mínimo'
      using errcode = 'P0001';
end;
$$;

-- Un cambio de precio queda en el historial. Solo puede haber un proveedor preferido por producto.
create function public.guardar_producto_proveedor(
  p_id uuid,
  p_producto_id uuid,
  p_proveedor_id uuid,
  p_presentacion_id uuid,
  p_precio numeric default null,
  p_codigo_proveedor text default null,
  p_preferido boolean default false,
  p_activo boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.catalogo.gestionar');
  v_previo numeric;
begin
  select pp.precio_actual into v_previo from public.producto_proveedor pp
  where pp.id = p_id and pp.tenant_id = v_perfil.tenant_id;

  if p_preferido and p_activo then
    update public.producto_proveedor pp set preferido = false
    where pp.producto_id = p_producto_id and pp.id <> p_id and pp.preferido;
  end if;

  insert into public.producto_proveedor
    (id, tenant_id, producto_id, proveedor_id, presentacion_id, codigo_proveedor,
     precio_actual, preferido, activo)
  values
    (p_id, v_perfil.tenant_id, p_producto_id, p_proveedor_id, p_presentacion_id, p_codigo_proveedor,
     p_precio, p_preferido, p_activo)
  on conflict (id) do update
    set producto_id = excluded.producto_id,
        proveedor_id = excluded.proveedor_id,
        presentacion_id = excluded.presentacion_id,
        codigo_proveedor = excluded.codigo_proveedor,
        precio_actual = excluded.precio_actual,
        preferido = excluded.preferido,
        activo = excluded.activo
    where public.producto_proveedor.tenant_id = excluded.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: relación inexistente' using errcode = 'P0002';
  end if;

  if p_precio is not null and p_precio is distinct from v_previo then
    insert into public.precios_historial (tenant_id, producto_proveedor_id, precio, usuario_id)
    values (v_perfil.tenant_id, p_id, p_precio, auth.uid());
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'producto_proveedor', p_id, 'guardado',
    jsonb_build_object(
      'producto_id', p_producto_id, 'proveedor_id', p_proveedor_id,
      'presentacion_id', p_presentacion_id, 'precio', p_precio,
      'precio_anterior', v_previo, 'preferido', p_preferido, 'activo', p_activo
    )
  );
  return p_id;
exception
  when unique_violation then
    raise exception 'PRECONDICION: ese proveedor ya tiene cargada esa presentación' using errcode = 'P0001';
  when foreign_key_violation then
    raise exception 'NO_ENCONTRADO: producto, proveedor o presentación inexistente' using errcode = 'P0002';
  when check_violation then
    raise exception 'PRECONDICION: el precio no es válido' using errcode = 'P0001';
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS y privilegios
-- ---------------------------------------------------------------------------

revoke all on public.rubros, public.sector_rubros, public.presentaciones, public.producto_codigos,
  public.producto_proveedor, public.precios_historial
  from public, anon, authenticated, service_role;
grant select on public.rubros, public.sector_rubros, public.presentaciones, public.producto_codigos,
  public.producto_proveedor, public.precios_historial
  to authenticated, service_role;

alter table public.rubros             enable row level security;
alter table public.sector_rubros      enable row level security;
alter table public.presentaciones     enable row level security;
alter table public.producto_codigos   enable row level security;
alter table public.producto_proveedor enable row level security;
alter table public.precios_historial  enable row level security;

create policy rubros_select on public.rubros
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

create policy sector_rubros_select on public.sector_rubros
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

create policy presentaciones_select on public.presentaciones
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

create policy producto_codigos_select on public.producto_codigos
  for select to authenticated
  using (tenant_id = app_private.tenant_actual());

-- Los precios no los ve cualquiera: el operario recibe sin ellos.
create policy producto_proveedor_select on public.producto_proveedor
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      app_private.tiene_permiso('compras.catalogo.ver')
      or app_private.tiene_permiso('compras.catalogo.gestionar')
      or app_private.tiene_permiso('recepcion.precios.ver')
    )
  );

create policy precios_historial_select on public.precios_historial
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      app_private.tiene_permiso('compras.catalogo.gestionar')
      or app_private.tiene_permiso('recepcion.precios.ver')
    )
  );

revoke all on function app_private.nombre_presentacion_base(public.unidad_stock) from public, anon, authenticated, service_role;
revoke all on function app_private.tipo_gtin(text) from public, anon, authenticated, service_role;
revoke all on function app_private.productos_unidad_stock() from public, anon, authenticated, service_role;
revoke all on function app_private.productos_presentacion_base() from public, anon, authenticated, service_role;

revoke all on function public.guardar_rubro(uuid, text, int, boolean) from public, anon, authenticated, service_role;
revoke all on function public.guardar_categoria(uuid, uuid, text, int, boolean) from public, anon, authenticated, service_role;
revoke all on function public.guardar_producto(uuid, uuid, text, public.unidad_stock, boolean, boolean, boolean) from public, anon, authenticated, service_role;
revoke all on function public.guardar_presentacion(uuid, uuid, text, numeric, boolean) from public, anon, authenticated, service_role;
revoke all on function public.guardar_codigo(uuid, uuid, uuid, text, public.tipo_codigo) from public, anon, authenticated, service_role;
revoke all on function public.guardar_proveedor(uuid, text, text, text, text, text, public.canal_envio, int, int[], numeric, boolean) from public, anon, authenticated, service_role;
revoke all on function public.guardar_producto_proveedor(uuid, uuid, uuid, uuid, numeric, text, boolean, boolean) from public, anon, authenticated, service_role;

grant execute on function public.guardar_rubro(uuid, text, int, boolean) to authenticated;
grant execute on function public.guardar_categoria(uuid, uuid, text, int, boolean) to authenticated;
grant execute on function public.guardar_producto(uuid, uuid, text, public.unidad_stock, boolean, boolean, boolean) to authenticated;
grant execute on function public.guardar_presentacion(uuid, uuid, text, numeric, boolean) to authenticated;
grant execute on function public.guardar_codigo(uuid, uuid, uuid, text, public.tipo_codigo) to authenticated;
grant execute on function public.guardar_proveedor(uuid, text, text, text, text, text, public.canal_envio, int, int[], numeric, boolean) to authenticated;
grant execute on function public.guardar_producto_proveedor(uuid, uuid, uuid, uuid, numeric, text, boolean, boolean) to authenticated;
