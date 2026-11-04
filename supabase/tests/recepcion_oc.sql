-- Eskemia · Flujo completo Compras -> Recepción, con los usuarios reales del proyecto.
-- No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/recepcion_oc.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.
--
-- Sigue el criterio de salida del MVP: pedido a 3 proveedores, una orden en aprobación por regla de
-- rubro, otra aprobada sola; se reciben una completa escaneando cajas y otra parcial; los saldos y
-- estados se actualizan; todo queda en eventos.
--
-- comprador: el admin de prueba, con rol Comprador. Recibe: el operario de prueba.

begin;

create function pg_temp.rol_de(p_user uuid, p_rol text)
returns void language plpgsql as $$
begin
  delete from public.usuario_roles where user_id = p_user;
  insert into public.usuario_roles (tenant_id, user_id, rol_id, sede_id)
  select r.tenant_id, p_user, r.id, '00000000-0000-4000-8000-000000000002' from public.roles r
  where r.tenant_id = '00000000-0000-4000-8000-000000000001' and r.nombre = p_rol;
end;
$$;

-- Lo que el kiosco sube a Storage: acá se registra directo, porque el test no sube archivos.
create function pg_temp.adjuntos_completos(p_rec uuid)
returns void language sql as $$
  insert into public.adjuntos (tenant_id, sede_id, recepcion_id, tipo, storage_path, client_uuid, usuario_id)
  select r.tenant_id, r.sede_id, r.id, t.tipo::public.tipo_adjunto, 'test/' || gen_random_uuid(), gen_random_uuid(), r.usuario_id
  from public.recepciones r
  cross join (values ('REMITO'), ('FIRMA_RECEPTOR'), ('FIRMA_TRANSPORTISTA')) as t (tipo)
  where r.id = p_rec
    and not exists (select 1 from public.adjuntos a where a.recepcion_id = r.id and a.tipo = t.tipo::public.tipo_adjunto and a.anulado_en is null)
$$;

-- El operario no inserta adjuntos: el trigger hace de la subida que el kiosco hace al abrir.
create function pg_temp.foto_al_abrir()
returns trigger language plpgsql security definer as $$
begin
  perform pg_temp.adjuntos_completos(new.id);
  return null;
end;
$$;
create trigger foto_al_abrir after insert on public.recepciones
  for each row execute function pg_temp.foto_al_abrir();

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  v_comida uuid := gen_random_uuid();
  v_cat uuid := gen_random_uuid();
  v_limpieza uuid := gen_random_uuid();
  v_cat2 uuid := gen_random_uuid();
  v_prov uuid;
  v_pre uuid;
begin
  insert into public.rubros (id, tenant_id, nombre) values (v_comida, t, 'Comida test'), (v_limpieza, t, 'Limpieza test');
  insert into public.categorias (id, tenant_id, rubro_id, nombre) values (v_cat, t, v_comida, 'Carnes test'), (v_cat2, t, v_limpieza, 'Hogar test');
  insert into public.productos (id, tenant_id, categoria_id, nombre, tipo_medida, gtin) values
    ('00000000-0000-4000-e000-0000000000b1', t, v_cat, 'Carne test', 'UNIDAD', null),
    ('00000000-0000-4000-e000-0000000000b2', t, v_cat2, 'Lavandina test', 'UNIDAD', null),
    ('00000000-0000-4000-e000-0000000000b3', t, v_cat2, 'Detergente test', 'UNIDAD', null),
    ('00000000-0000-4000-e000-0000000000b4', t, v_cat2, 'No pedido test', 'UNIDAD', null);
  insert into public.proveedores (id, tenant_id, nombre, cuit) values
    ('00000000-0000-4000-e000-0000000000d1', t, 'Prov Carne test', '30999999991'),
    ('00000000-0000-4000-e000-0000000000d2', t, 'Prov Lavandina test', '30999999992'),
    ('00000000-0000-4000-e000-0000000000d3', t, 'Prov Detergente test', '30999999993');

  -- Caja x 12: escanear una caja suma 12 unidades contra la orden.
  insert into public.presentaciones (id, tenant_id, producto_id, nombre, factor) values
    ('00000000-0000-4000-e000-0000000000e2', t, '00000000-0000-4000-e000-0000000000b2', 'Caja x 12', 12);
  select id into v_pre from public.presentaciones where producto_id = '00000000-0000-4000-e000-0000000000b1';
  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('00000000-0000-4000-e000-0000000000f1', t, '00000000-0000-4000-e000-0000000000b1', '00000000-0000-4000-e000-0000000000d1', v_pre, 1000),
    ('00000000-0000-4000-e000-0000000000f2', t, '00000000-0000-4000-e000-0000000000b2', '00000000-0000-4000-e000-0000000000d2', '00000000-0000-4000-e000-0000000000e2', 500);
  select id into v_pre from public.presentaciones where producto_id = '00000000-0000-4000-e000-0000000000b3' and factor = 1;
  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual) values
    ('00000000-0000-4000-e000-0000000000f3', t, '00000000-0000-4000-e000-0000000000b3', '00000000-0000-4000-e000-0000000000d3', v_pre, 10);

  insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, nivel_requerido)
  values (t, 'RUBRO', v_comida, 'SIEMPRE', 1);

  perform pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Comprador');
end;
$$;

-- 1. El comprador pide a 3 proveedores.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare r jsonb;
begin
  r := public.confirmar_pedido(gen_random_uuid(), '00000000-0000-4000-8000-000000000002', jsonb_build_array(
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 5),
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f2', 'cantidad', 2),
    jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f3', 'cantidad', 10)
  ));
  if jsonb_array_length(r -> 'ordenes') <> 3 then raise exception 'TEST 1: %', r; end if;
  if (select count(*) from public.ordenes_compra where estado = 'PENDIENTE_APROBACION') <> 1
     or (select count(*) from public.ordenes_compra where estado = 'APROBADA') <> 2 then
    raise exception 'TEST 2: se esperaba una orden en aprobación y dos aprobadas';
  end if;
end;
$$;

-- 2. El operario ve solo lo aprobado, sin precios.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  f record;
begin
  if (select count(*) from public.pendientes_recepcion(s)) <> 2 then
    raise exception 'TEST 3: el operario debería ver 2 pendientes';
  end if;
  if exists (select 1 from public.pendientes_recepcion(s) p where p.proveedor = 'Prov Carne test') then
    raise exception 'TEST 4: el operario vio una orden en aprobación';
  end if;
  select * into f from public.pendientes_recepcion(s) p where p.proveedor = 'Prov Lavandina test';
  if f.total_estimado is not null or (f.items -> 0) ? 'precio_unitario' or (f.items -> 0) ? 'subtotal' then
    raise exception 'TEST 5: el operario vio precios: %', f;
  end if;
  if not f.no_enviada or f.atrasada or not f.se_puede_recibir then
    raise exception 'TEST 6: %', f;
  end if;
  -- 2 cajas x 12: se espera en unidades de stock.
  if (f.items -> 0 ->> 'cant_pedida')::numeric <> 24 or (f.items -> 0 ->> 'saldo')::numeric <> 24 then
    raise exception 'TEST 7: %', f.items;
  end if;
  if exists (select 1 from public.ordenes_compra) then
    raise exception 'TEST 8: el operario lee ordenes_compra directo, con precios';
  end if;
end;
$$;

-- 3. Una vez aprobada por el encargado, aparece.
reset role;
select pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Encargado de compras');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  perform public.aprobar_oc((select b.id from public.bandeja_aprobacion() b where b.proveedor = 'Prov Carne test'));
end;
$$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

-- 4. Recepción completa escaneando cajas: coincide todo, sin diferencias.
create temp table ids (clave text primary key, id uuid) on commit drop;
reset role;
grant all on ids to authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
  prod constant uuid := '00000000-0000-4000-e000-0000000000b2';
begin
  if (select count(*) from public.pendientes_recepcion(s)) <> 3 then
    raise exception 'TEST 9: la orden aprobada no apareció como pendiente';
  end if;
  select p.id into v_oc from public.pendientes_recepcion(s) p where p.proveedor = 'Prov Lavandina test';
  insert into ids values ('oc_completa', v_oc), ('rec_completa', v_rec);

  -- No se puede abrir con otro proveedor.
  begin
    perform public.abrir_recepcion(gen_random_uuid(), '00000000-0000-4000-e000-0000000000d3', 'R-X', s, null, null, v_oc);
    raise exception 'TEST 10: abrió una orden con otro proveedor' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  perform public.abrir_recepcion(v_rec, '00000000-0000-4000-e000-0000000000d2', 'R-1', s, null, null, v_oc);
  -- Reintento de la cola: no duplica la precarga.
  perform public.abrir_recepcion(v_rec, '00000000-0000-4000-e000-0000000000d2', 'R-1', s, null, null, v_oc);

  if (select count(*) from public.recepcion_items i where i.recepcion_id = v_rec) <> 1
     or (select i.cant_pedida from public.recepcion_items i where i.recepcion_id = v_rec) <> 24 then
    raise exception 'TEST 11: no precargó lo pedido';
  end if;
  if (select r.oc_numero from public.recepciones r where r.id = v_rec) is null then
    raise exception 'TEST 12: no guardó el número de orden';
  end if;

  -- Dos cajas escaneadas: 12 + 12.
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 12, 'CAJA');
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 12, 'CAJA');
  perform public.iniciar_control(v_rec, null);
  perform public.fijar_control_item(v_rec, prod, 24);
end;
$$;

reset role;
select pg_temp.adjuntos_completos((select id from ids where clave = 'rec_completa'));
set local role authenticated;

do $$
declare
  v_rec uuid := (select id from ids where clave = 'rec_completa');
  v_oc uuid := (select id from ids where clave = 'oc_completa');
begin
  if public.cerrar_recepcion(v_rec) <> 'CERRADA_OK' then
    raise exception 'TEST 13: una recepción exacta debería cerrar OK';
  end if;
  if exists (select 1 from public.pendientes_recepcion('00000000-0000-4000-8000-000000000002') p where p.id = v_oc) then
    raise exception 'TEST 14: la orden completa sigue pendiente';
  end if;
end;
$$;

-- 5. Recepción parcial con diferencias: lo detecta sin que nadie compare a mano.
do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
  prod constant uuid := '00000000-0000-4000-e000-0000000000b3';
  no_pedido constant uuid := '00000000-0000-4000-e000-0000000000b4';
  c jsonb;
begin
  select p.id into v_oc from public.pendientes_recepcion(s) p where p.proveedor = 'Prov Detergente test';
  insert into ids values ('oc_parcial', v_oc), ('rec_parcial', v_rec);
  perform public.abrir_recepcion(v_rec, '00000000-0000-4000-e000-0000000000d3', 'R-2', s, null, null, v_oc);

  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 6, 'X');
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', no_pedido, 3, 'Y');
  perform public.iniciar_control(v_rec, null);

  -- El remito coincide con lo recibido: igual falta justificar contra lo pedido.
  perform public.fijar_control_item(v_rec, prod, 6);
  perform public.fijar_control_item(v_rec, no_pedido, 3);
  c := public.checklist_recepcion(v_rec);
  if (c ->> 'motivos_diferencias')::boolean then
    raise exception 'TEST 15: no detectó lo pedido contra lo recibido: %', c;
  end if;

  perform public.fijar_control_item(v_rec, prod, 6, 'FALTANTE', 'Vino menos de lo pedido');
  c := public.checklist_recepcion(v_rec);
  if (c ->> 'motivos_diferencias')::boolean then
    raise exception 'TEST 16: no detectó el producto no pedido: %', c;
  end if;
  perform public.fijar_control_item(v_rec, no_pedido, 3, 'NO_PEDIDO', 'Enviaron sin pedirlo');
  c := public.checklist_recepcion(v_rec);
  if not (c ->> 'motivos_diferencias')::boolean then
    raise exception 'TEST 17: con motivos debería estar completo: %', c;
  end if;
end;
$$;

reset role;
select pg_temp.adjuntos_completos((select id from ids where clave = 'rec_parcial'));
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  v_rec uuid := (select id from ids where clave = 'rec_parcial');
  v_oc uuid := (select id from ids where clave = 'oc_parcial');
  f record;
  v_seg uuid := gen_random_uuid();
begin
  if public.cerrar_recepcion(v_rec) <> 'CERRADA_CON_DIFERENCIAS' then
    raise exception 'TEST 18: debería cerrar con diferencias aunque el remito coincida';
  end if;
  select * into f from public.pendientes_recepcion(s) p where p.id = v_oc;
  if not found or f.estado <> 'RECIBIDA_PARCIAL' or (f.items -> 0 ->> 'saldo')::numeric <> 4 then
    raise exception 'TEST 19: saldo parcial %', f;
  end if;

  -- La segunda entrega precarga solo el saldo.
  perform public.abrir_recepcion(v_seg, '00000000-0000-4000-e000-0000000000d3', 'R-3', s, null, null, v_oc);
  if (select i.cant_pedida from public.recepcion_items i where i.recepcion_id = v_seg) <> 4 then
    raise exception 'TEST 20: no precargó el saldo';
  end if;
  insert into ids values ('rec_segunda', v_seg);
  perform public.registrar_lectura(gen_random_uuid(), v_seg, 'ESCANEO', '00000000-0000-4000-e000-0000000000b3', 4, 'X');
  perform public.iniciar_control(v_seg, null);
  perform public.fijar_control_item(v_seg, '00000000-0000-4000-e000-0000000000b3', 4);
end;
$$;

reset role;
select pg_temp.adjuntos_completos((select id from ids where clave = 'rec_segunda'));
set local role authenticated;

do $$
declare
  v_seg uuid := (select id from ids where clave = 'rec_segunda');
  v_oc uuid := (select id from ids where clave = 'oc_parcial');
begin
  if public.cerrar_recepcion(v_seg) <> 'CERRADA_OK' then
    raise exception 'TEST 21: la segunda entrega cubre el saldo';
  end if;
  if exists (select 1 from public.pendientes_recepcion('00000000-0000-4000-8000-000000000002') p where p.id = v_oc) then
    raise exception 'TEST 22: con el saldo cubierto no debería seguir pendiente';
  end if;
end;
$$;

-- 6. Una recepción rechazada deja de contar: la orden vuelve a pendiente.
reset role;
select pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Supervisor de recepción');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_oc uuid := (select id from ids where clave = 'oc_completa');
  v_rec uuid := (select id from ids where clave = 'rec_completa');
  f record;
begin
  perform public.rechazar_recepcion(v_rec, 'Mal contado');
  select * into f from public.pendientes_recepcion('00000000-0000-4000-8000-000000000002') p where p.id = v_oc;
  if not found or f.estado <> 'APROBADA' or (f.items -> 0 ->> 'saldo')::numeric <> 24 then
    raise exception 'TEST 23: rechazar debería devolver el saldo: %', f;
  end if;

  if (select b.items_con_diferencia from public.v_recepciones_bandeja b where b.id = (select id from ids where clave = 'rec_parcial')) <> 2
     or (select b.semaforo from public.v_recepciones_bandeja b where b.id = (select id from ids where clave = 'rec_parcial')) <> 'CON_DIFERENCIAS'
     or (select b.oc_numero from public.v_recepciones_bandeja b where b.id = (select id from ids where clave = 'rec_parcial')) is null then
    raise exception 'TEST 24: el semáforo del back no ve lo pedido';
  end if;
  -- El supervisor ve las pendientes en aprobación, solo para consulta: ya no hay ninguna.
  if exists (select 1 from public.pendientes_recepcion('00000000-0000-4000-8000-000000000002') p where not p.se_puede_recibir) then
    raise exception 'TEST 25: quedó una en aprobación';
  end if;
end;
$$;

-- 7. Una orden en aprobación no se recibe, y sin orden todo sigue igual que antes.
reset role;
update public.ordenes_compra set estado = 'PENDIENTE_APROBACION' where id = (select id from ids where clave = 'oc_completa');
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  f record;
  v_sin uuid := gen_random_uuid();
begin
  select * into f from public.pendientes_recepcion(s) p where p.id = (select id from ids where clave = 'oc_completa');
  if not found or f.se_puede_recibir then
    raise exception 'TEST 26: debería verse, pero sin poder recibirla: %', f;
  end if;
  begin
    perform public.abrir_recepcion(gen_random_uuid(), f.proveedor_id, 'R-4', s, null, null, f.id);
    raise exception 'TEST 27: recibió una orden en aprobación' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  perform public.abrir_recepcion(v_sin, f.proveedor_id, 'R-5', s);
  if exists (select 1 from public.recepcion_items i where i.recepcion_id = v_sin)
     or (select r.oc_id from public.recepciones r where r.id = v_sin) is not null then
    raise exception 'TEST 28: una recepción sin orden no debería precargar nada';
  end if;
end;
$$;

-- 8. Sin permiso de pendientes no hay lista, y la cadena de eventos sigue entera.
reset role;
delete from public.usuario_roles where user_id = '00000000-0000-4000-c000-000000000001';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  perform * from public.pendientes_recepcion('00000000-0000-4000-8000-000000000002');
  raise exception 'TEST 29: vio pendientes sin permiso' using errcode = 'ZZ001';
exception when insufficient_privilege then null;
end;
$$;

reset role;
do $$
declare
  e public.eventos;
  v_prev text := null;
begin
  for e in select * from public.eventos ev where ev.tenant_id = '00000000-0000-4000-8000-000000000001' order by ev.secuencia loop
    if e.hash_prev is distinct from v_prev or e.hash <> app_private.hash_evento(e) then
      raise exception 'TEST 30: cadena de eventos rota en %', e.secuencia;
    end if;
    v_prev := e.hash;
  end loop;
  if not exists (select 1 from public.eventos where entidad = 'orden_compra' and accion = 'estado:RECIBIDA_PARCIAL')
     or not exists (select 1 from public.eventos where entidad = 'orden_compra' and accion = 'estado:RECIBIDA') then
    raise exception 'TEST 31: faltan eventos del estado de la orden';
  end if;
end;
$$;

select 'recepcion_oc: todos los tests pasaron' as resultado;
rollback;
