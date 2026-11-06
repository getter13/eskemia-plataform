-- Eskemia · Tests de evaluar_aprobacion. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/aprobacion.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.
--
-- Usa al operario de prueba como emisor, cambiándole los roles dentro de la transacción.

begin;

create function pg_temp.item(p_producto uuid, p_subtotal numeric)
returns jsonb language sql as $$ select jsonb_build_object('producto_id', p_producto, 'subtotal', p_subtotal) $$;

-- Emisor con un único rol, en todas las sedes.
create function pg_temp.emisor(p_rol text)
returns void language plpgsql as $$
begin
  delete from public.usuario_roles where user_id = '00000000-0000-4000-c000-000000000001';
  insert into public.usuario_roles (tenant_id, user_id, rol_id)
  select r.tenant_id, '00000000-0000-4000-c000-000000000001', r.id
  from public.roles r
  where r.tenant_id = '00000000-0000-4000-8000-000000000001' and r.nombre = p_rol;
end;
$$;

create function pg_temp.evaluar(p_items jsonb)
returns jsonb language sql stable as $$
  select app_private.evaluar_aprobacion(
    '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-c000-000000000001',
    '00000000-0000-4000-8000-000000000002', p_items
  )
$$;

create function pg_temp.regla(p_alcance public.alcance_regla, p_id uuid, p_modo public.modo_regla, p_umbral numeric, p_nivel int)
returns void language sql as $$
  insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido)
  values ('00000000-0000-4000-8000-000000000001', p_alcance, p_id, p_modo, p_umbral, p_nivel)
  on conflict (tenant_id, alcance, alcance_id) do update
    set modo = excluded.modo, monto_umbral = excluded.monto_umbral,
        nivel_requerido = excluded.nivel_requerido, activa = true
$$;

-- Las reglas demo no cuentan: esto también se deshace con el ROLLBACK.
delete from public.reglas_aprobacion;

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  v_comida uuid := gen_random_uuid();
  v_limpieza uuid := gen_random_uuid();
  v_lacteos uuid := gen_random_uuid();
  v_proteinas uuid := gen_random_uuid();
  v_lavandinas uuid := gen_random_uuid();
  v_leche uuid := gen_random_uuid();
  v_queso uuid := gen_random_uuid();
  v_carne uuid := gen_random_uuid();
  v_lavandina uuid := gen_random_uuid();
  r jsonb;
begin
  if exists (select 1 from public.reglas_aprobacion) then
    raise exception 'TEST: se esperaba arrancar sin reglas';
  end if;

  insert into public.rubros (id, tenant_id, nombre) values
    (v_comida, t, 'Comida test'), (v_limpieza, t, 'Limpieza test');
  insert into public.categorias (id, tenant_id, rubro_id, nombre) values
    (v_lacteos, t, v_comida, 'Lácteos test'),
    (v_proteinas, t, v_comida, 'Proteínas test'),
    (v_lavandinas, t, v_limpieza, 'Lavandinas test');
  insert into public.productos (id, tenant_id, categoria_id, nombre, tipo_medida) values
    (v_leche, t, v_lacteos, 'Leche test', 'UNIDAD'),
    (v_queso, t, v_lacteos, 'Queso test', 'UNIDAD'),
    (v_carne, t, v_proteinas, 'Carne test', 'PESO'),
    (v_lavandina, t, v_lavandinas, 'Lavandina test', 'UNIDAD');

  perform pg_temp.emisor('Comprador');

  -- Sin reglas: aprobación automática.
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  if (r ->> 'estado') <> 'APROBADA' or (r ->> 'tipo_aprobacion') <> 'AUTOMATICA'
     or (r ->> 'requiere_aprobacion')::boolean or (r ->> 'total')::numeric <> 100 then
    raise exception 'TEST 1: %', r;
  end if;

  -- Regla de rubro: alcanza a sus categorías, no a otro rubro.
  perform pg_temp.regla('RUBRO', v_comida, 'SIEMPRE', null, 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' or (r ->> 'tipo_aprobacion') is not null
     or (r ->> 'nivel_requerido')::int <> 1 then
    raise exception 'TEST 2: %', r;
  end if;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 100)));
  if (r ->> 'estado') <> 'APROBADA' then raise exception 'TEST 3: %', r; end if;

  -- La categoría le gana al rubro.
  perform pg_temp.regla('CATEGORIA', v_lacteos, 'NUNCA', null, 0);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  if (r ->> 'estado') <> 'APROBADA' then raise exception 'TEST 4: %', r; end if;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 100)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' then raise exception 'TEST 5: %', r; end if;

  -- El producto le gana a la categoría.
  perform pg_temp.regla('PRODUCTO', v_queso, 'SIEMPRE', null, 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_queso, 100)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION'
     or (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'PRODUCTO' then
    raise exception 'TEST 6: %', r;
  end if;

  -- Solo el ítem que dispara queda marcado, y una regla inactiva vuelve al nivel superior.
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_queso, 100), pg_temp.item(v_leche, 100)));
  if r -> 'productos_disparadores' <> jsonb_build_array(v_queso) then raise exception 'TEST 7: %', r; end if;

  update public.reglas_aprobacion set activa = false where alcance = 'CATEGORIA' and alcance_id = v_lacteos;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  if (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO' then raise exception 'TEST 8: %', r; end if;
  update public.reglas_aprobacion set activa = true where alcance = 'CATEGORIA' and alcance_id = v_lacteos;

  -- POR_MONTO: suma los ítems de la misma regla; igualar el umbral no dispara.
  perform pg_temp.regla('RUBRO', v_limpieza, 'POR_MONTO', 1000, 2);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 1000)));
  if (r ->> 'estado') <> 'APROBADA' then raise exception 'TEST 9: %', r; end if;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 600), pg_temp.item(v_lavandina, 400.01)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' or (r ->> 'nivel_requerido')::int <> 2
     or (r -> 'reglas_aplicadas' -> 0 ->> 'subtotal')::numeric <> 1000.01 then
    raise exception 'TEST 10: %', r;
  end if;

  -- El nivel de la orden es el máximo de lo que dispara.
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 10), pg_temp.item(v_lavandina, 5000)));
  if (r ->> 'nivel_requerido')::int <> 2 or jsonb_array_length(r -> 'reglas_aplicadas') <> 2 then
    raise exception 'TEST 11: %', r;
  end if;

  -- Regla de empresa: cubre lo que no tiene otra regla.
  perform pg_temp.regla('EMPRESA', null, 'SIEMPRE', null, 1);
  insert into public.productos (id, tenant_id, nombre) values ('00000000-0000-4000-b000-0000000000f1', t, 'Sin categoría test');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item('00000000-0000-4000-b000-0000000000f1', 1)));
  if (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'EMPRESA' then raise exception 'TEST 12: %', r; end if;
  delete from public.reglas_aprobacion where alcance = 'EMPRESA';

  -- Límite del rol: exceder pide al menos nivel 1 aunque ninguna regla dispare.
  update public.roles set limite_monto_sin_aprobacion = 500 where tenant_id = t and nombre = 'Comprador';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 500)));
  if (r ->> 'estado') <> 'APROBADA' or (r ->> 'excede_limite_rol')::boolean then raise exception 'TEST 13: %', r; end if;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 500.01)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' or (r ->> 'nivel_requerido')::int <> 1
     or not (r ->> 'excede_limite_rol')::boolean then
    raise exception 'TEST 14: %', r;
  end if;

  -- Un rol ajeno a pedir no le levanta el límite; uno que puede pedir sin límite, sí.
  insert into public.usuario_roles (tenant_id, user_id, rol_id)
  select t, '00000000-0000-4000-c000-000000000001', r2.id from public.roles r2
  where r2.tenant_id = t and r2.nombre = 'Operario de recepción';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 600)));
  if not (r ->> 'excede_limite_rol')::boolean then raise exception 'TEST 15: %', r; end if;
  insert into public.usuario_roles (tenant_id, user_id, rol_id)
  select t, '00000000-0000-4000-c000-000000000001', r2.id from public.roles r2
  where r2.tenant_id = t and r2.nombre = 'Gerente';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 600)));
  if (r ->> 'excede_limite_rol')::boolean then raise exception 'TEST 16: %', r; end if;
  update public.roles set limite_monto_sin_aprobacion = null where tenant_id = t and nombre = 'Comprador';

  -- Autoaprobación: alcanza con su nivel; si no llega, queda pendiente.
  perform pg_temp.emisor('Encargado de compras');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 10)));
  if (r ->> 'estado') <> 'APROBADA' or (r ->> 'tipo_aprobacion') <> 'AUTOAPROBADA' then raise exception 'TEST 17: %', r; end if;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' then raise exception 'TEST 18: %', r; end if;
  perform pg_temp.emisor('Gerente');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  if (r ->> 'tipo_aprobacion') <> 'AUTOAPROBADA' then raise exception 'TEST 19: %', r; end if;

  -- Con la autoaprobación apagada, nadie aprueba lo propio.
  update public.configuracion_empresa set permitir_autoaprobacion = false where tenant_id = t;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  if (r ->> 'estado') <> 'PENDIENTE_APROBACION' then raise exception 'TEST 20: %', r; end if;
  update public.configuracion_empresa set permitir_autoaprobacion = true where tenant_id = t;

  begin
    perform pg_temp.evaluar('[]');
    raise exception 'TEST 21: aceptó una orden sin ítems' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform pg_temp.evaluar(jsonb_build_array(pg_temp.item(gen_random_uuid(), 1)));
    raise exception 'TEST 22: aceptó un producto inexistente' using errcode = 'ZZ001';
  exception when no_data_found then null;
  end;

  perform pg_temp.emisor('Comprador');
end;
$$;

-- ---------------------------------------------------------------------------
-- Como cliente de la API: el comprador evalúa pero no configura
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_leche uuid;
  r jsonb;
begin
  select p.id into v_leche from public.productos p where p.nombre = 'Leche test';
  r := public.evaluar_aprobacion('00000000-0000-4000-8000-000000000002',
    jsonb_build_array(jsonb_build_object('producto_id', v_leche, 'subtotal', 10)));
  if (r ->> 'estado') <> 'APROBADA' then raise exception 'TEST 23: %', r; end if;

  if exists (select 1 from public.reglas_aprobacion) then
    raise exception 'TEST 24: el comprador no debería leer las reglas';
  end if;

  begin
    perform public.guardar_regla_aprobacion('EMPRESA', null, 'NUNCA');
    raise exception 'TEST 25: el comprador configuró una regla' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.fijar_autoaprobacion(false);
    raise exception 'TEST 26: el comprador cambió la autoaprobación' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Admin configura.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_leche uuid;
  v_id uuid;
  v_id2 uuid;
  v_rol uuid;
begin
  select p.id into v_leche from public.productos p where p.nombre = 'Leche test';

  v_id := public.guardar_regla_aprobacion('PRODUCTO', v_leche, 'POR_MONTO', 100, 1);
  v_id2 := public.guardar_regla_aprobacion('PRODUCTO', v_leche, 'SIEMPRE', 100, 2);
  if v_id <> v_id2 then raise exception 'TEST 27: debería haber una regla por alcance'; end if;
  if (select r.monto_umbral from public.reglas_aprobacion r where r.id = v_id) is not null then
    raise exception 'TEST 28: SIEMPRE no debería conservar el umbral';
  end if;

  begin
    perform public.guardar_regla_aprobacion('PRODUCTO', v_leche, 'SIEMPRE', null, 9);
    raise exception 'TEST 29: aceptó un nivel sin aprobadores' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.guardar_regla_aprobacion('PRODUCTO', v_leche, 'POR_MONTO', null, 1);
    raise exception 'TEST 30: aceptó una regla por monto sin monto' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.guardar_regla_aprobacion('RUBRO', v_leche, 'SIEMPRE', null, 1);
    raise exception 'TEST 31: aceptó un id de otro alcance' using errcode = 'ZZ001';
  exception when no_data_found then null;
  end;

  perform public.fijar_autoaprobacion(false);
  if (select c.permitir_autoaprobacion from public.configuracion_empresa c) then
    raise exception 'TEST 32: no guardó la autoaprobación';
  end if;

  select r.id into v_rol from public.roles r where r.nombre = 'Comprador';
  perform public.fijar_limite_rol(v_rol, 1000);
  if (select r.limite_monto_sin_aprobacion from public.roles r where r.id = v_rol) <> 1000 then
    raise exception 'TEST 33: no guardó el límite';
  end if;

  if not (public.verificar_cadena_eventos() ->> 'ok')::boolean then
    raise exception 'TEST 34: la cadena de eventos se rompió';
  end if;
end;
$$;

reset role;
select 'aprobacion: todos los tests pasaron' as resultado;
rollback;
