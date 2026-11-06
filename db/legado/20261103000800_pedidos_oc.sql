-- Eskemia · Pedidos y órdenes de compra (plan de Compras, etapa 6).
-- Un pedido se confirma de una vez: el carrito vive en el dispositivo y llega entero acá,
-- que lo separa por proveedor y genera una orden por cada uno.

create type public.estado_pedido as enum ('BORRADOR', 'CONFIRMADO', 'DESCARTADO');
create type public.estado_oc as enum (
  'PENDIENTE_APROBACION', 'APROBADA', 'RECHAZADA', 'ENVIADA',
  'RECIBIDA_PARCIAL', 'RECIBIDA', 'CERRADA', 'ANULADA'
);
create type public.tipo_aprobacion as enum ('AUTOMATICA', 'AUTOAPROBADA', 'MANUAL');

-- Identifica la sede en los números de orden: OC-CAS-2026-000123.
alter table public.sedes
  add column codigo text check (codigo ~ '^[A-Z0-9]{2,8}$'),
  add unique (tenant_id, codigo);

update public.sedes s set codigo = d.codigo
from (
  select id,
    upper(left(regexp_replace(translate(nombre, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'), '[^A-Za-z0-9]', '', 'g'), 3))
      || case when row_number() over w > 1 then (row_number() over w)::text else '' end as codigo
  from public.sedes
  window w as (
    partition by tenant_id,
      upper(left(regexp_replace(translate(nombre, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'), '[^A-Za-z0-9]', '', 'g'), 3))
    order by creado_en, id
  )
) d
where s.id = d.id and length(d.codigo) >= 2;

create table public.pedidos_compra (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null,
  sede_id       uuid not null,
  estado        public.estado_pedido not null default 'BORRADOR',
  usuario_id    uuid not null references auth.users (id),
  sector_id     uuid,
  request_uuid  uuid not null,
  creado_en     timestamptz not null default now(),
  confirmado_en timestamptz,
  unique (tenant_id, id),
  unique (tenant_id, request_uuid),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id),
  foreign key (tenant_id, sector_id) references public.sectores (tenant_id, id)
);
create index pedidos_compra_usuario_idx on public.pedidos_compra (usuario_id, creado_en desc);

create table public.pedido_items (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null,
  pedido_id             uuid not null,
  producto_proveedor_id uuid not null,
  presentacion_id       uuid not null references public.presentaciones (id),
  cantidad              numeric(14, 3) not null check (cantidad > 0),
  unique (pedido_id, producto_proveedor_id),
  foreign key (tenant_id, pedido_id) references public.pedidos_compra (tenant_id, id),
  foreign key (tenant_id, producto_proveedor_id) references public.producto_proveedor (tenant_id, id)
);

create table public.secuencias (
  tenant_id     uuid not null references public.tenants (id),
  sede_id       uuid not null,
  tipo          text not null,
  anio          int not null,
  ultimo_numero bigint not null,
  primary key (tenant_id, sede_id, tipo, anio),
  foreign key (tenant_id, sede_id) references public.sedes (tenant_id, id)
);

-- Las dos tablas estaban vacías desde Recepción: se pueden agregar columnas obligatorias.
alter table public.ordenes_compra
  add column pedido_id uuid,
  add column estado public.estado_oc not null,
  add column usuario_id uuid not null references auth.users (id),
  add column requiere_aprobacion boolean not null,
  add column nivel_requerido int not null default 0,
  add column tipo_aprobacion public.tipo_aprobacion,
  add column aprobada_por uuid references auth.users (id),
  add column aprobada_en timestamptz,
  add column motivo_rechazo text,
  add column reglas_aplicadas jsonb not null default '{}'::jsonb,
  add column fecha_entrega_estimada date,
  add column total_estimado numeric(14, 2) not null default 0,
  add column enviada_en timestamptz,
  add column canal_envio public.canal_envio,
  add unique (tenant_id, numero),
  add foreign key (tenant_id, pedido_id) references public.pedidos_compra (tenant_id, id);

create index ordenes_compra_usuario_idx on public.ordenes_compra (usuario_id, creado_en desc);
create index ordenes_compra_sede_idx on public.ordenes_compra (tenant_id, sede_id, estado);

-- Snapshot: lo que se pidió no cambia si después cambian el precio o el catálogo.
-- cantidad va en presentaciones; cant_pedida, en unidades de stock.
alter table public.oc_items
  add column producto_proveedor_id uuid,
  add column presentacion_id uuid references public.presentaciones (id),
  add column producto_nombre text not null,
  add column sku text,
  add column presentacion_nombre text not null,
  add column factor numeric(14, 3) not null check (factor > 0),
  add column cant_pedida numeric(17, 3) generated always as (cantidad * factor) stored,
  add column precio_unitario numeric(14, 2),
  add column subtotal numeric(14, 2) not null default 0,
  add column disparo_aprobacion boolean not null default false,
  add unique (tenant_id, id),
  add foreign key (tenant_id, producto_proveedor_id) references public.producto_proveedor (tenant_id, id);

create index oc_items_oc_idx on public.oc_items (oc_id);

-- ---------------------------------------------------------------------------
-- Auxiliares internas
-- ---------------------------------------------------------------------------

-- El upsert bloquea la fila hasta el fin de la transacción: dos pedidos no comparten número.
create function app_private.siguiente_numero_oc(p_tenant_id uuid, p_sede_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anio int := extract(year from now() at time zone 'America/Argentina/Buenos_Aires');
  v_numero bigint;
  v_codigo text;
begin
  insert into public.secuencias (tenant_id, sede_id, tipo, anio, ultimo_numero)
  values (p_tenant_id, p_sede_id, 'OC', v_anio, 1)
  on conflict (tenant_id, sede_id, tipo, anio) do update
    set ultimo_numero = public.secuencias.ultimo_numero + 1
  returning ultimo_numero into v_numero;

  select coalesce(s.codigo, 'S' || upper(left(s.id::text, 4))) into v_codigo
  from public.sedes s where s.id = p_sede_id;

  return 'OC-' || v_codigo || '-' || v_anio || '-' || lpad(v_numero::text, 6, '0');
end;
$$;

-- Único lugar donde cambia el estado de una orden: valida la transición y deja el evento.
create function app_private.cambiar_estado_oc(
  p_oc public.ordenes_compra,
  p_nuevo public.estado_oc,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    (p_oc.estado = 'PENDIENTE_APROBACION' and p_nuevo in ('APROBADA', 'RECHAZADA'))
    or (p_oc.estado = 'APROBADA' and p_nuevo in ('ENVIADA', 'ANULADA'))
    or (p_oc.estado = 'ENVIADA' and p_nuevo in ('RECIBIDA_PARCIAL', 'RECIBIDA', 'ANULADA'))
    or (p_oc.estado = 'RECIBIDA_PARCIAL' and p_nuevo in ('RECIBIDA', 'CERRADA'))
    or (p_oc.estado = 'RECIBIDA' and p_nuevo = 'CERRADA')
  ) then
    raise exception 'PRECONDICION: transición inválida de % a %', p_oc.estado, p_nuevo
      using errcode = 'P0001';
  end if;

  update public.ordenes_compra set estado = p_nuevo where id = p_oc.id;

  perform app_private.registrar_evento(
    p_oc.tenant_id, p_oc.sede_id, 'orden_compra', p_oc.id, 'estado:' || p_nuevo::text,
    jsonb_build_object('desde', p_oc.estado, 'hasta', p_nuevo, 'numero', p_oc.numero) || p_payload
  );
end;
$$;

create function app_private.resumen_pedido(p_pedido_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'pedido_id', p_pedido_id,
    'ordenes', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', o.id, 'numero', o.numero, 'estado', o.estado,
        'proveedor', pr.nombre, 'total_estimado', o.total_estimado
      ) order by o.numero
    ), '[]'::jsonb)
  )
  from public.ordenes_compra o
  join public.proveedores pr on pr.id = o.proveedor_id
  where o.pedido_id = p_pedido_id;
$$;

-- ---------------------------------------------------------------------------
-- RPC
-- ---------------------------------------------------------------------------

-- Una transacción: o se crean todas las órdenes o ninguna. p_items: [{oferta_id, cantidad}].
-- Idempotente por request_uuid: un doble toque o un reintento de la cola devuelve lo ya creado.
create function public.confirmar_pedido(p_request_uuid uuid, p_sede_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.pedido.crear', p_sede_id);
  v_pedido uuid;
  v_lineas jsonb;
  v_proveedor record;
  v_del_proveedor jsonb;
  v_evaluacion jsonb;
  v_oc uuid;
  v_numero text;
  v_estado public.estado_oc;
  v_total numeric;
  v_no_disponible text;
begin
  if p_request_uuid is null then
    raise exception 'PRECONDICION: falta el identificador del pedido' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.sedes s where s.id = p_sede_id and s.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;

  insert into public.pedidos_compra (tenant_id, sede_id, usuario_id, request_uuid)
  values (v_perfil.tenant_id, p_sede_id, v_perfil.user_id, p_request_uuid)
  on conflict (tenant_id, request_uuid) do nothing
  returning id into v_pedido;

  if v_pedido is null then
    select p.id into v_pedido from public.pedidos_compra p
    where p.tenant_id = v_perfil.tenant_id and p.request_uuid = p_request_uuid;
    return app_private.resumen_pedido(v_pedido) || jsonb_build_object('duplicada', true);
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'PRECONDICION: el pedido no tiene ítems' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where (i ->> 'cantidad') is null or (i ->> 'cantidad')::numeric <= 0
  ) then
    raise exception 'PRECONDICION: hay un ítem con una cantidad no válida' using errcode = 'P0001';
  end if;

  -- Un pedido hecho sin señal pudo quedar viejo: el catálogo se revisa al confirmar.
  select coalesce(pr.nombre, 'un producto') into v_no_disponible
  from jsonb_array_elements(p_items) i
  left join public.producto_proveedor pp
    on pp.id = (i ->> 'oferta_id')::uuid and pp.tenant_id = v_perfil.tenant_id
  left join public.productos pr on pr.id = pp.producto_id
  left join public.proveedores prov on prov.id = pp.proveedor_id
  left join public.presentaciones pre on pre.id = pp.presentacion_id
  where pp.id is null or not (pp.activo and pr.activo and prov.activo and pre.activa)
  limit 1;
  if found then
    raise exception 'PRECONDICION: % ya no está disponible. Revisá el pedido', v_no_disponible
      using errcode = 'P0001';
  end if;

  select jsonb_agg(jsonb_build_object(
    'oferta_id', pp.id, 'cantidad', i.cantidad, 'producto_id', pr.id, 'proveedor_id', pp.proveedor_id,
    'presentacion_id', pre.id, 'presentacion', pre.nombre, 'factor', pre.factor,
    'precio', pp.precio_actual, 'nombre', pr.nombre, 'sku', pr.sku,
    'subtotal', round(coalesce(pp.precio_actual, 0) * i.cantidad, 2)
  ))
  into v_lineas
  from (
    select (e ->> 'oferta_id')::uuid as oferta_id, sum((e ->> 'cantidad')::numeric) as cantidad
    from jsonb_array_elements(p_items) e
    group by 1
  ) i
  join public.producto_proveedor pp on pp.id = i.oferta_id
  join public.productos pr on pr.id = pp.producto_id
  join public.presentaciones pre on pre.id = pp.presentacion_id;

  insert into public.pedido_items (tenant_id, pedido_id, producto_proveedor_id, presentacion_id, cantidad)
  select v_perfil.tenant_id, v_pedido, (l ->> 'oferta_id')::uuid, (l ->> 'presentacion_id')::uuid,
    (l ->> 'cantidad')::numeric
  from jsonb_array_elements(v_lineas) l;

  for v_proveedor in
    select distinct pr.id, pr.nombre, pr.plazo_entrega_dias
    from jsonb_array_elements(v_lineas) l
    join public.proveedores pr on pr.id = (l ->> 'proveedor_id')::uuid
    order by pr.nombre
  loop
    select jsonb_agg(l), sum((l ->> 'subtotal')::numeric)
    into v_del_proveedor, v_total
    from jsonb_array_elements(v_lineas) l
    where (l ->> 'proveedor_id')::uuid = v_proveedor.id;

    v_evaluacion := app_private.evaluar_aprobacion(
      v_perfil.tenant_id, v_perfil.user_id, p_sede_id,
      (select jsonb_agg(jsonb_build_object('producto_id', l -> 'producto_id', 'subtotal', l -> 'subtotal'))
       from jsonb_array_elements(v_del_proveedor) l)
    );
    v_estado := (v_evaluacion ->> 'estado')::public.estado_oc;
    v_numero := app_private.siguiente_numero_oc(v_perfil.tenant_id, p_sede_id);

    insert into public.ordenes_compra (
      tenant_id, sede_id, proveedor_id, numero, pedido_id, estado, usuario_id,
      requiere_aprobacion, nivel_requerido, tipo_aprobacion, aprobada_por, aprobada_en,
      reglas_aplicadas, fecha_entrega_estimada, total_estimado
    ) values (
      v_perfil.tenant_id, p_sede_id, v_proveedor.id, v_numero, v_pedido, v_estado, v_perfil.user_id,
      (v_evaluacion ->> 'requiere_aprobacion')::boolean,
      (v_evaluacion ->> 'nivel_requerido')::int,
      (v_evaluacion ->> 'tipo_aprobacion')::public.tipo_aprobacion,
      case when v_evaluacion ->> 'tipo_aprobacion' = 'AUTOAPROBADA' then v_perfil.user_id end,
      case when v_estado = 'APROBADA' then now() end,
      v_evaluacion,
      (now() at time zone 'America/Argentina/Buenos_Aires')::date + v_proveedor.plazo_entrega_dias,
      v_total
    )
    returning id into v_oc;

    insert into public.oc_items (
      tenant_id, sede_id, oc_id, producto_id, cantidad, producto_proveedor_id, presentacion_id,
      producto_nombre, sku, presentacion_nombre, factor, precio_unitario, subtotal, disparo_aprobacion
    )
    select
      v_perfil.tenant_id, p_sede_id, v_oc, (l ->> 'producto_id')::uuid, (l ->> 'cantidad')::numeric,
      (l ->> 'oferta_id')::uuid, (l ->> 'presentacion_id')::uuid, l ->> 'nombre', l ->> 'sku',
      l ->> 'presentacion', (l ->> 'factor')::numeric, (l ->> 'precio')::numeric,
      (l ->> 'subtotal')::numeric, (v_evaluacion -> 'productos_disparadores') ? (l ->> 'producto_id')
    from jsonb_array_elements(v_del_proveedor) l;

    perform app_private.registrar_evento(
      v_perfil.tenant_id, p_sede_id, 'orden_compra', v_oc, 'creada',
      jsonb_build_object(
        'numero', v_numero, 'pedido_id', v_pedido, 'proveedor_id', v_proveedor.id, 'total', v_total,
        'estado', v_estado, 'tipo_aprobacion', v_evaluacion ->> 'tipo_aprobacion',
        'nivel_requerido', v_evaluacion -> 'nivel_requerido'
      )
    );
  end loop;

  update public.pedidos_compra set estado = 'CONFIRMADO', confirmado_en = now() where id = v_pedido;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, p_sede_id, 'pedido', v_pedido, 'confirmado',
    jsonb_build_object('request_uuid', p_request_uuid)
  );

  return app_private.resumen_pedido(v_pedido) || jsonb_build_object('duplicada', false);
end;
$$;

-- APROBADA -> ENVIADA. Puede marcarla quien la emitió o quien ve todas las órdenes.
create function public.marcar_oc_enviada(p_oc_id uuid, p_canal public.canal_envio default 'MANUAL')
returns public.estado_oc
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.perfil_activo();
  v_oc public.ordenes_compra;
begin
  select * into v_oc from public.ordenes_compra o
  where o.id = p_oc_id and o.tenant_id = v_perfil.tenant_id
  for update;

  if not found or not (
    app_private.tiene_permiso('compras.oc.ver_todas', v_oc.sede_id)
    or (v_oc.usuario_id = v_perfil.user_id and app_private.tiene_permiso('compras.pedido.crear', v_oc.sede_id))
  ) then
    raise exception 'NO_ENCONTRADO: orden de compra inexistente' using errcode = 'P0002';
  end if;

  if v_oc.estado in ('ENVIADA', 'RECIBIDA_PARCIAL', 'RECIBIDA', 'CERRADA') then
    return v_oc.estado;  -- reintento
  end if;

  perform app_private.cambiar_estado_oc(v_oc, 'ENVIADA', jsonb_build_object('canal', p_canal));
  update public.ordenes_compra set enviada_en = now(), canal_envio = p_canal where id = p_oc_id;
  return 'ENVIADA';
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS y privilegios
-- ---------------------------------------------------------------------------

revoke all on public.pedidos_compra, public.pedido_items, public.secuencias
  from public, anon, authenticated, service_role;
grant select on public.pedidos_compra, public.pedido_items to authenticated, service_role;

alter table public.pedidos_compra enable row level security;
alter table public.pedido_items   enable row level security;
alter table public.secuencias     enable row level security;

create policy pedidos_compra_select on public.pedidos_compra
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      usuario_id = (select auth.uid())
      or app_private.tiene_permiso('compras.oc.ver_todas', sede_id)
    )
  );

create policy pedido_items_select on public.pedido_items
  for select to authenticated
  using (exists (select 1 from public.pedidos_compra p where p.id = pedido_id));

-- Las órdenes llevan precios: ya no alcanza con estar en la sede.
drop policy ordenes_compra_select on public.ordenes_compra;
create policy ordenes_compra_select on public.ordenes_compra
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      usuario_id = (select auth.uid())
      or app_private.tiene_permiso('compras.oc.ver_todas', sede_id)
      or app_private.tiene_permiso('compras.oc.aprobar', sede_id)
    )
  );

drop policy oc_items_select on public.oc_items;
create policy oc_items_select on public.oc_items
  for select to authenticated
  using (exists (select 1 from public.ordenes_compra o where o.id = oc_id));

-- Tiempo real para el seguimiento. RLS también filtra lo que recibe cada usuario.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.ordenes_compra;
  end if;
end;
$$;

revoke all on function app_private.siguiente_numero_oc(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function app_private.cambiar_estado_oc(public.ordenes_compra, public.estado_oc, jsonb) from public, anon, authenticated, service_role;
revoke all on function app_private.resumen_pedido(uuid) from public, anon, authenticated, service_role;
revoke all on function public.confirmar_pedido(uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.marcar_oc_enviada(uuid, public.canal_envio) from public, anon, authenticated, service_role;
grant execute on function public.confirmar_pedido(uuid, uuid, jsonb) to authenticated;
grant execute on function public.marcar_oc_enviada(uuid, public.canal_envio) to authenticated;
