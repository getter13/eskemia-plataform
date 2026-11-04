-- Eskemia · Reglas de aprobación (plan de Compras, etapa 4).
-- Por ítem manda la regla activa más específica: producto > categoría > rubro > empresa.
-- Sin ninguna regla, el ítem no requiere aprobación.

create type public.alcance_regla as enum ('EMPRESA', 'RUBRO', 'CATEGORIA', 'PRODUCTO');
create type public.modo_regla as enum ('NUNCA', 'SIEMPRE', 'POR_MONTO');

-- alcance_id apunta a rubro, categoría o producto según el alcance: lo valida la RPC.
create table public.reglas_aprobacion (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.tenants (id),
  alcance         public.alcance_regla not null,
  alcance_id      uuid,
  modo            public.modo_regla not null,
  monto_umbral    numeric(14, 2) check (monto_umbral >= 0),
  nivel_requerido int not null default 0,
  activa          boolean not null default true,
  creado_en       timestamptz not null default now(),
  unique nulls not distinct (tenant_id, alcance, alcance_id),
  check ((alcance = 'EMPRESA') = (alcance_id is null)),
  check ((modo = 'POR_MONTO') = (monto_umbral is not null)),
  check ((modo = 'NUNCA' and nivel_requerido = 0) or (modo <> 'NUNCA' and nivel_requerido >= 1))
);

-- Núcleo de la evaluación: no escribe nada. La usan la vista previa del carrito y confirmar_pedido.
-- p_items: [{producto_id, subtotal}] de una sola orden de compra.
-- POR_MONTO compara el subtotal de los ítems de la orden que resolvieron a esa misma regla.
create function app_private.evaluar_aprobacion(
  p_tenant_id uuid,
  p_user_id uuid,
  p_sede_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total numeric;
  v_reglas jsonb;
  v_nivel int;
  v_disparadores jsonb;
  v_algun_sin_limite boolean;
  v_limite numeric;
  v_excede_limite boolean := false;
  v_nivel_usuario int;
  v_autoaprobacion boolean;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'PRECONDICION: la orden no tiene ítems' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where (i ->> 'subtotal') is null or (i ->> 'subtotal')::numeric < 0
  ) then
    raise exception 'PRECONDICION: hay un ítem sin subtotal válido' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where not exists (
      select 1 from public.productos p
      where p.id = (i ->> 'producto_id')::uuid and p.tenant_id = p_tenant_id
    )
  ) then
    raise exception 'NO_ENCONTRADO: producto inexistente' using errcode = 'P0002';
  end if;

  select sum((i ->> 'subtotal')::numeric) into v_total from jsonb_array_elements(p_items) i;

  with items as (
    select (i ->> 'producto_id')::uuid as producto_id, (i ->> 'subtotal')::numeric as subtotal
    from jsonb_array_elements(p_items) i
  ),
  resueltos as (
    select i.producto_id, i.subtotal, r.id as regla_id, r.alcance, r.alcance_id, r.modo,
           r.monto_umbral, r.nivel_requerido
    from items i
    join public.productos p on p.id = i.producto_id
    left join public.categorias c on c.id = p.categoria_id
    left join lateral (
      select * from public.reglas_aprobacion ra
      where ra.tenant_id = p_tenant_id
        and ra.activa
        and (
          (ra.alcance = 'PRODUCTO' and ra.alcance_id = p.id)
          or (ra.alcance = 'CATEGORIA' and ra.alcance_id = c.id)
          or (ra.alcance = 'RUBRO' and ra.alcance_id = c.rubro_id)
          or ra.alcance = 'EMPRESA'
        )
      order by case ra.alcance
        when 'PRODUCTO' then 1 when 'CATEGORIA' then 2 when 'RUBRO' then 3 else 4
      end
      limit 1
    ) r on true
    where r.id is not null
  ),
  grupos as (
    select regla_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido,
           sum(subtotal) as subtotal, jsonb_agg(distinct producto_id) as productos
    from resueltos
    group by regla_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido
  ),
  disparadas as (
    select * from grupos g
    where g.modo = 'SIEMPRE' or (g.modo = 'POR_MONTO' and g.subtotal > g.monto_umbral)
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'regla_id', d.regla_id, 'alcance', d.alcance, 'alcance_id', d.alcance_id, 'modo', d.modo,
      'monto_umbral', d.monto_umbral, 'nivel_requerido', d.nivel_requerido,
      'subtotal', d.subtotal, 'productos', d.productos
    )), '[]'::jsonb),
    coalesce(max(d.nivel_requerido), 0),
    coalesce((select jsonb_agg(distinct x) from disparadas d2, jsonb_array_elements(d2.productos) x), '[]'::jsonb)
  into v_reglas, v_nivel, v_disparadores
  from disparadas d;

  -- Límite del perfil: solo cuentan los roles con los que puede pedir en esa sede. Vale el más
  -- permisivo, y un rol sin límite propio no le impone ninguno.
  select bool_or(r.limite_monto_sin_aprobacion is null), max(r.limite_monto_sin_aprobacion)
  into v_algun_sin_limite, v_limite
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.pedido.crear'
  where ur.user_id = p_user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);

  if v_algun_sin_limite is false and v_total > v_limite then
    v_excede_limite := true;
    v_nivel := greatest(v_nivel, 1);
  end if;

  select coalesce(max(r.nivel_aprobacion), 0) into v_nivel_usuario
  from public.usuario_roles ur
  join public.roles r on r.id = ur.rol_id and r.activo
  join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
  where ur.user_id = p_user_id and (ur.sede_id is null or ur.sede_id = p_sede_id);

  select coalesce(
    (select ce.permitir_autoaprobacion from public.configuracion_empresa ce where ce.tenant_id = p_tenant_id),
    true
  ) into v_autoaprobacion;

  return jsonb_build_object(
    'total', v_total,
    'requiere_aprobacion', v_nivel > 0,
    'nivel_requerido', v_nivel,
    'estado', case
      when v_nivel = 0 then 'APROBADA'
      when v_autoaprobacion and v_nivel_usuario >= v_nivel then 'APROBADA'
      else 'PENDIENTE_APROBACION'
    end,
    'tipo_aprobacion', case
      when v_nivel = 0 then 'AUTOMATICA'
      when v_autoaprobacion and v_nivel_usuario >= v_nivel then 'AUTOAPROBADA'
    end,
    'nivel_usuario', v_nivel_usuario,
    'excede_limite_rol', v_excede_limite,
    'limite_rol', case when v_excede_limite then v_limite end,
    'productos_disparadores', v_disparadores,
    'reglas_aplicadas', v_reglas
  );
end;
$$;

create function public.evaluar_aprobacion(p_sede_id uuid, p_items jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.pedido.crear', p_sede_id);
begin
  if not exists (
    select 1 from public.sedes s where s.id = p_sede_id and s.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: sede inexistente' using errcode = 'P0002';
  end if;
  return app_private.evaluar_aprobacion(v_perfil.tenant_id, v_perfil.user_id, p_sede_id, p_items);
end;
$$;

-- Una regla por alcance. Desactivarla hace que el ítem vuelva a la regla del nivel superior.
create function public.guardar_regla_aprobacion(
  p_alcance public.alcance_regla,
  p_alcance_id uuid,
  p_modo public.modo_regla,
  p_monto_umbral numeric default null,
  p_nivel_requerido int default 1,
  p_activa boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.aprobacion.configurar');
  v_umbral numeric := case when p_modo = 'POR_MONTO' then p_monto_umbral end;
  v_nivel int := case when p_modo = 'NUNCA' then 0 else p_nivel_requerido end;
  v_id uuid;
begin
  if p_alcance = 'EMPRESA' and p_alcance_id is not null then
    raise exception 'PRECONDICION: la regla de empresa no apunta a un rubro, categoría o producto'
      using errcode = 'P0001';
  end if;
  if p_alcance <> 'EMPRESA' and not exists (
    select 1 from public.rubros x
    where p_alcance = 'RUBRO' and x.id = p_alcance_id and x.tenant_id = v_perfil.tenant_id
    union all
    select 1 from public.categorias x
    where p_alcance = 'CATEGORIA' and x.id = p_alcance_id and x.tenant_id = v_perfil.tenant_id
    union all
    select 1 from public.productos x
    where p_alcance = 'PRODUCTO' and x.id = p_alcance_id and x.tenant_id = v_perfil.tenant_id
  ) then
    raise exception 'NO_ENCONTRADO: no existe a qué aplicar la regla' using errcode = 'P0002';
  end if;
  if p_modo = 'POR_MONTO' and (v_umbral is null or v_umbral < 0) then
    raise exception 'PRECONDICION: la regla por monto necesita un monto válido' using errcode = 'P0001';
  end if;
  if p_modo <> 'NUNCA' then
    if coalesce(v_nivel, 0) < 1 then
      raise exception 'PRECONDICION: la regla necesita un nivel de aprobación' using errcode = 'P0001';
    end if;
    -- Sin esto, las órdenes quedarían esperando a un aprobador que no existe.
    if p_activa and not exists (
      select 1 from public.roles r
      join public.rol_permisos rp on rp.rol_id = r.id and rp.permiso_codigo = 'compras.oc.aprobar'
      where r.tenant_id = v_perfil.tenant_id and r.activo and r.nivel_aprobacion >= v_nivel
    ) then
      raise exception 'PRECONDICION: ningún rol puede aprobar en el nivel %', v_nivel using errcode = 'P0001';
    end if;
  end if;

  insert into public.reglas_aprobacion
    (tenant_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido, activa)
  values
    (v_perfil.tenant_id, p_alcance, p_alcance_id, p_modo, v_umbral, v_nivel, p_activa)
  on conflict (tenant_id, alcance, alcance_id) do update
    set modo = excluded.modo,
        monto_umbral = excluded.monto_umbral,
        nivel_requerido = excluded.nivel_requerido,
        activa = excluded.activa
  returning id into v_id;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'regla_aprobacion', v_id, 'guardada',
    jsonb_build_object(
      'alcance', p_alcance, 'alcance_id', p_alcance_id, 'modo', p_modo,
      'monto_umbral', v_umbral, 'nivel_requerido', v_nivel, 'activa', p_activa
    )
  );
  return v_id;
end;
$$;

create function public.fijar_autoaprobacion(p_permitir boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.aprobacion.configurar');
begin
  insert into public.configuracion_empresa (tenant_id, permitir_autoaprobacion)
  values (v_perfil.tenant_id, p_permitir)
  on conflict (tenant_id) do update
    set permitir_autoaprobacion = excluded.permitir_autoaprobacion, actualizado_en = now();

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'configuracion_empresa', v_perfil.tenant_id, 'autoaprobacion',
    jsonb_build_object('permitir', p_permitir)
  );
end;
$$;

-- p_limite nulo: el rol no tiene límite propio.
create function public.fijar_limite_rol(p_rol_id uuid, p_limite numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfiles := app_private.exigir_permiso('compras.aprobacion.configurar');
begin
  if p_limite < 0 then
    raise exception 'PRECONDICION: el límite no puede ser negativo' using errcode = 'P0001';
  end if;
  update public.roles r set limite_monto_sin_aprobacion = p_limite
  where r.id = p_rol_id and r.tenant_id = v_perfil.tenant_id;
  if not found then
    raise exception 'NO_ENCONTRADO: rol inexistente' using errcode = 'P0002';
  end if;

  perform app_private.registrar_evento(
    v_perfil.tenant_id, null, 'rol', p_rol_id, 'limite_monto',
    jsonb_build_object('limite', p_limite)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS y privilegios
-- ---------------------------------------------------------------------------

revoke all on public.reglas_aprobacion from public, anon, authenticated, service_role;
grant select on public.reglas_aprobacion to authenticated, service_role;
alter table public.reglas_aprobacion enable row level security;

create policy reglas_aprobacion_select on public.reglas_aprobacion
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      app_private.tiene_permiso('compras.aprobacion.configurar')
      or app_private.tiene_permiso('compras.oc.aprobar')
    )
  );

-- Quien configura la aprobación necesita ver los roles para fijarles el límite.
drop policy roles_select on public.roles;
create policy roles_select on public.roles
  for select to authenticated
  using (
    tenant_id = app_private.tenant_actual()
    and (
      app_private.tiene_permiso('admin.usuarios.gestionar')
      or app_private.tiene_permiso('compras.aprobacion.configurar')
    )
  );

revoke all on function app_private.evaluar_aprobacion(uuid, uuid, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.evaluar_aprobacion(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.guardar_regla_aprobacion(public.alcance_regla, uuid, public.modo_regla, numeric, int, boolean) from public, anon, authenticated, service_role;
revoke all on function public.fijar_autoaprobacion(boolean) from public, anon, authenticated, service_role;
revoke all on function public.fijar_limite_rol(uuid, numeric) from public, anon, authenticated, service_role;

grant execute on function public.evaluar_aprobacion(uuid, jsonb) to authenticated;
grant execute on function public.guardar_regla_aprobacion(public.alcance_regla, uuid, public.modo_regla, numeric, int, boolean) to authenticated;
grant execute on function public.fijar_autoaprobacion(boolean) to authenticated;
grant execute on function public.fijar_limite_rol(uuid, numeric) to authenticated;
