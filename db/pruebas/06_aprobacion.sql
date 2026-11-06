-- Eskemia · Tests de evaluar_aprobacion y su configuración (pgTAP). Portado de
-- supabase/tests/aprobacion.sql (legado).
--
-- Qué verifica: precedencia producto > categoría > rubro > organización, reglas POR_MONTO
-- por suma, nivel máximo, límite de monto del rol, autoaprobación, y que solo quien
-- configura aprobaciones puede cambiar reglas y límites.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- El emisor es la cuenta "persona" del escenario, con roles que se cambian acá.

select pruebas.escenario();
select * from no_plan();

create function pg_temp.item(p_producto uuid, p_subtotal numeric)
returns jsonb language sql as $$ select jsonb_build_object('producto_id', p_producto, 'subtotal', p_subtotal) $$;

create function pg_temp.evaluar(p_items jsonb)
returns jsonb language sql as $$
  select compras.evaluar_aprobacion(pruebas.id('org'), 'e0000000-0000-4000-8000-000000000003', pruebas.id('sede'), p_items)
$$;

create function pg_temp.regla(p_alcance compras.alcance_regla, p_id uuid, p_modo compras.modo_regla, p_umbral numeric, p_nivel int)
returns void language sql as $$
  insert into compras.reglas_aprobacion (organizacion_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido)
  values (pruebas.id('org'), p_alcance, p_id, p_modo, p_umbral, p_nivel)
  on conflict (organizacion_id, alcance, alcance_id) do update
    set modo = excluded.modo, monto_umbral = excluded.monto_umbral,
        nivel_requerido = excluded.nivel_requerido, activa = true
$$;

do $$
declare
  o uuid := pruebas.id('org');
  e constant uuid := 'e0000000-0000-4000-8000-000000000003';
  v_comida uuid := gen_random_uuid();
  v_limpieza uuid := gen_random_uuid();
  v_lacteos uuid := gen_random_uuid();
  v_proteinas uuid := gen_random_uuid();
  v_lavandinas uuid := gen_random_uuid();
  v_leche uuid := 'e0000000-0000-4000-b000-000000000001';
  v_queso uuid := gen_random_uuid();
  v_carne uuid := gen_random_uuid();
  v_lavandina uuid := gen_random_uuid();
  v_sin_cat uuid := gen_random_uuid();
  r jsonb;
begin
  perform pruebas.no('arranca sin reglas', exists (select 1 from compras.reglas_aprobacion where organizacion_id = o));

  insert into compras.rubros (id, organizacion_id, nombre) values (v_comida, o, 'Comida test'), (v_limpieza, o, 'Limpieza test');
  insert into compras.categorias (id, organizacion_id, rubro_id, nombre) values
    (v_lacteos, o, v_comida, 'Lácteos test'), (v_proteinas, o, v_comida, 'Proteínas test'),
    (v_lavandinas, o, v_limpieza, 'Lavandinas test');
  insert into compras.productos (id, organizacion_id, categoria_id, nombre, tipo_medida) values
    (v_leche, o, v_lacteos, 'Leche test', 'UNIDAD'), (v_queso, o, v_lacteos, 'Queso test', 'UNIDAD'),
    (v_carne, o, v_proteinas, 'Carne test', 'PESO'), (v_lavandina, o, v_lavandinas, 'Lavandina test', 'UNIDAD'),
    (v_sin_cat, o, null, 'Sin categoría test', 'UNIDAD');

  perform pruebas.rol_de(e, 'Comprador');

  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  perform pruebas.no('1: sin reglas, aprobación automática', (r ->> 'estado') <> 'APROBADA' or (r ->> 'tipo_aprobacion') <> 'AUTOMATICA'
     or (r ->> 'requiere_aprobacion')::boolean or (r ->> 'total')::numeric <> 100);

  perform pg_temp.regla('RUBRO', v_comida, 'SIEMPRE', null, 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  perform pruebas.no('2: la regla de rubro alcanza a sus categorías', (r ->> 'estado') <> 'PENDIENTE_APROBACION'
     or (r ->> 'tipo_aprobacion') is not null or (r ->> 'nivel_requerido')::int <> 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 100)));
  perform pruebas.no('3: no alcanza a otro rubro', (r ->> 'estado') <> 'APROBADA');

  perform pg_temp.regla('CATEGORIA', v_lacteos, 'NUNCA', null, 0);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  perform pruebas.no('4: la categoría le gana al rubro', (r ->> 'estado') <> 'APROBADA');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 100)));
  perform pruebas.no('5: otra categoría del rubro sigue la regla del rubro', (r ->> 'estado') <> 'PENDIENTE_APROBACION');

  perform pg_temp.regla('PRODUCTO', v_queso, 'SIEMPRE', null, 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_queso, 100)));
  perform pruebas.no('6: el producto le gana a la categoría', (r ->> 'estado') <> 'PENDIENTE_APROBACION'
     or (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'PRODUCTO');

  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_queso, 100), pg_temp.item(v_leche, 100)));
  perform pruebas.no('7: solo se marca el ítem que dispara', r -> 'productos_disparadores' <> jsonb_build_array(v_queso));

  update compras.reglas_aprobacion set activa = false where alcance = 'CATEGORIA' and alcance_id = v_lacteos;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 100)));
  perform pruebas.no('8: una regla inactiva cede al nivel superior', (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'RUBRO');
  update compras.reglas_aprobacion set activa = true where alcance = 'CATEGORIA' and alcance_id = v_lacteos;

  perform pg_temp.regla('RUBRO', v_limpieza, 'POR_MONTO', 1000, 2);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 1000)));
  perform pruebas.no('9: igualar el umbral no dispara', (r ->> 'estado') <> 'APROBADA');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 600), pg_temp.item(v_lavandina, 400.01)));
  perform pruebas.no('10: POR_MONTO suma los ítems de la misma regla', (r ->> 'estado') <> 'PENDIENTE_APROBACION'
     or (r ->> 'nivel_requerido')::int <> 2 or (r -> 'reglas_aplicadas' -> 0 ->> 'subtotal')::numeric <> 1000.01);

  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 10), pg_temp.item(v_lavandina, 5000)));
  perform pruebas.no('11: el nivel es el máximo de lo que dispara',
    (r ->> 'nivel_requerido')::int <> 2 or jsonb_array_length(r -> 'reglas_aplicadas') <> 2);

  perform pg_temp.regla('EMPRESA', null, 'SIEMPRE', null, 1);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_sin_cat, 1)));
  perform pruebas.no('12: la regla de organización cubre lo que no tiene otra', (r -> 'reglas_aplicadas' -> 0 ->> 'alcance') <> 'EMPRESA');
  delete from compras.reglas_aprobacion where organizacion_id = o and alcance = 'EMPRESA';

  update nucleo.roles set limite_monto_sin_aprobacion = 500 where organizacion_id = o and nombre = 'Comprador';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 500)));
  perform pruebas.no('13: igualar el límite del rol no pide aprobación', (r ->> 'estado') <> 'APROBADA' or (r ->> 'excede_limite_rol')::boolean);
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 500.01)));
  perform pruebas.no('14: exceder el límite pide al menos nivel 1', (r ->> 'estado') <> 'PENDIENTE_APROBACION'
     or (r ->> 'nivel_requerido')::int <> 1 or not (r ->> 'excede_limite_rol')::boolean);

  -- Un rol ajeno a pedir no levanta el límite; uno que pide sin límite, sí.
  insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id)
  select o, m.id, r2.id from nucleo.membresias m, nucleo.roles r2
  where m.organizacion_id = o and m.cuenta_id = e and r2.organizacion_id = o and r2.nombre = 'Operario de recepción';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 600)));
  perform pruebas.no('15: un rol ajeno a pedir no levanta el límite', not (r ->> 'excede_limite_rol')::boolean);
  insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id)
  select o, m.id, r2.id from nucleo.membresias m, nucleo.roles r2
  where m.organizacion_id = o and m.cuenta_id = e and r2.organizacion_id = o and r2.nombre = 'Gerente';
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_leche, 600)));
  perform pruebas.no('16: un rol que pide sin límite lo levanta', (r ->> 'excede_limite_rol')::boolean);
  update nucleo.roles set limite_monto_sin_aprobacion = null where organizacion_id = o and nombre = 'Comprador';

  perform pruebas.rol_de(e, 'Encargado de compras');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_carne, 10)));
  perform pruebas.no('17: se autoaprueba con nivel suficiente', (r ->> 'estado') <> 'APROBADA' or (r ->> 'tipo_aprobacion') <> 'AUTOAPROBADA');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  perform pruebas.no('18: sin nivel suficiente queda pendiente', (r ->> 'estado') <> 'PENDIENTE_APROBACION');
  perform pruebas.rol_de(e, 'Gerente');
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  perform pruebas.no('19: el gerente se autoaprueba nivel 2', (r ->> 'tipo_aprobacion') <> 'AUTOAPROBADA');

  insert into compras.configuracion (organizacion_id, permitir_autoaprobacion) values (o, false)
  on conflict (organizacion_id) do update set permitir_autoaprobacion = false;
  r := pg_temp.evaluar(jsonb_build_array(pg_temp.item(v_lavandina, 5000)));
  perform pruebas.no('20: sin autoaprobación nadie aprueba lo propio', (r ->> 'estado') <> 'PENDIENTE_APROBACION');
  update compras.configuracion set permitir_autoaprobacion = true where organizacion_id = o;

  perform pruebas.falla('21: orden sin ítems rechazada', 'PRECONDICION', 'select pg_temp.evaluar(''[]'')');
  perform pruebas.falla('22: producto inexistente rechazado', 'NO_ENCONTRADO',
    format('select pg_temp.evaluar(%L)', jsonb_build_array(pg_temp.item(gen_random_uuid(), 1))));

  perform pruebas.rol_de(e, 'Comprador');
end;
$$;

-- Como cliente de la API: el comprador evalúa pero no configura -----------------------
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  o uuid := pruebas.id('org');
  r jsonb;
begin
  r := api.evaluar_aprobacion(pruebas.id('sede'), jsonb_build_array(
    jsonb_build_object('producto_id', 'e0000000-0000-4000-b000-000000000001', 'subtotal', 10)));
  perform pruebas.no('23: el comprador evalúa', (r ->> 'estado') <> 'APROBADA');
  perform pruebas.no('24: el comprador no lee las reglas', exists (select 1 from api.reglas_aprobacion));
  perform pruebas.falla('25: el comprador no configura reglas', 'SIN_PERMISO',
    format('select api.guardar_regla_aprobacion(%L, %L, null, %L)', o, 'EMPRESA', 'NUNCA'));
  perform pruebas.falla('26: el comprador no cambia la autoaprobación', 'SIN_PERMISO',
    format('select api.fijar_autoaprobacion(%L, false)', o));
end;
$$;
reset role;

-- Admin configura ---------------------------------------------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
declare
  o uuid := pruebas.id('org');
  v_leche uuid := 'e0000000-0000-4000-b000-000000000001';
  v_id uuid;
  v_id2 uuid;
  v_rol uuid;
begin
  v_id := api.guardar_regla_aprobacion(o, 'PRODUCTO', v_leche, 'POR_MONTO', 100, 1);
  v_id2 := api.guardar_regla_aprobacion(o, 'PRODUCTO', v_leche, 'SIEMPRE', 100, 2);
  perform pruebas.no('27: una regla por alcance', v_id <> v_id2);
  perform pruebas.no('28: SIEMPRE no conserva el umbral',
    (select r.monto_umbral from api.reglas_aprobacion r where r.id = v_id) is not null);
  perform pruebas.falla('29: nivel sin aprobadores rechazado', 'PRECONDICION',
    format('select api.guardar_regla_aprobacion(%L, %L, %L, %L, null, 9)', o, 'PRODUCTO', v_leche, 'SIEMPRE'));
  perform pruebas.falla('30: regla por monto sin monto rechazada', 'PRECONDICION',
    format('select api.guardar_regla_aprobacion(%L, %L, %L, %L, null, 1)', o, 'PRODUCTO', v_leche, 'POR_MONTO'));
  perform pruebas.falla('31: id de otro alcance rechazado', 'NO_ENCONTRADO',
    format('select api.guardar_regla_aprobacion(%L, %L, %L, %L, null, 1)', o, 'RUBRO', v_leche, 'SIEMPRE'));

  perform api.fijar_autoaprobacion(o, false);
  perform pruebas.no('32: guarda la autoaprobación',
    (select c.permitir_autoaprobacion from api.configuracion_compras c where c.organizacion_id = o));

  select r.id into v_rol from api.roles r where r.organizacion_id = o and r.nombre = 'Comprador';
  perform api.fijar_limite_rol(v_rol, 1000);
  perform pruebas.no('33: guarda el límite del rol',
    (select r.limite_monto_sin_aprobacion from api.roles r where r.id = v_rol) <> 1000);
  perform pruebas.no('34: la cadena de eventos verifica', not (api.verificar_cadena_eventos(o) ->> 'ok')::boolean);
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
