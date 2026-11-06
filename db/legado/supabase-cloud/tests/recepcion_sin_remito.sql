-- Eskemia · Recibir sobre una orden no pide remito; sin orden, sí.
-- No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/recepcion_sin_remito.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.

begin;

-- Las órdenes demo no cuentan: esto también se deshace con el ROLLBACK.
update public.recepciones set oc_id = null where oc_id is not null;
delete from public.oc_items;
delete from public.ordenes_compra;
delete from public.pedido_items;
delete from public.pedidos_compra;

create function pg_temp.foto_al_abrir()
returns trigger language plpgsql security definer as $$
begin
  insert into public.adjuntos (tenant_id, sede_id, recepcion_id, tipo, storage_path, client_uuid, usuario_id)
  select new.tenant_id, new.sede_id, new.id, t.tipo::public.tipo_adjunto, 'test/' || gen_random_uuid(), gen_random_uuid(), new.usuario_id
  from (values ('REMITO'), ('FIRMA_RECEPTOR'), ('FIRMA_TRANSPORTISTA')) as t (tipo);
  return null;
end;
$$;
create trigger foto_al_abrir after insert on public.recepciones
  for each row execute function pg_temp.foto_al_abrir();

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  v_pre uuid;
begin
  insert into public.productos (id, tenant_id, nombre, tipo_medida, requiere_lote) values
    ('00000000-0000-4000-e000-0000000000b1', t, 'Leche test', 'UNIDAD', false),
    ('00000000-0000-4000-e000-0000000000b2', t, 'Queso con lote test', 'UNIDAD', true),
    ('00000000-0000-4000-e000-0000000000b3', t, 'Coincide test', 'UNIDAD', false);
  insert into public.proveedores (id, tenant_id, nombre, cuit)
  values ('00000000-0000-4000-e000-0000000000d1', t, 'Prov test', '30999999991');
  insert into public.producto_proveedor (tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select t, pr.producto_id, '00000000-0000-4000-e000-0000000000d1', pr.id, 100
  from public.presentaciones pr
  where pr.producto_id in ('00000000-0000-4000-e000-0000000000b1', '00000000-0000-4000-e000-0000000000b2', '00000000-0000-4000-e000-0000000000b3');
end;
$$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

create temp table ids (clave text primary key, id uuid) on commit drop;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  prov constant uuid := '00000000-0000-4000-e000-0000000000d1';
  leche constant uuid := '00000000-0000-4000-e000-0000000000b1';
  queso constant uuid := '00000000-0000-4000-e000-0000000000b2';
  igual constant uuid := '00000000-0000-4000-e000-0000000000b3';
  r jsonb;
  c jsonb;
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
begin
  r := public.confirmar_pedido(gen_random_uuid(), s, (
    select jsonb_agg(jsonb_build_object('oferta_id', pp.id, 'cantidad', 10))
    from public.producto_proveedor pp where pp.proveedor_id = prov
  ));
  v_oc := (r -> 'ordenes' -> 0 ->> 'id')::uuid;

  perform public.abrir_recepcion(v_rec, prov, 'R-1', s, null, null, v_oc);
  insert into ids values ('rec', v_rec), ('oc', v_oc);

  -- Menos de lo esperado, y sin haber cargado ningún remito.
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', leche, 6, 'X');
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', igual, 10, 'X');
  -- Mismo producto en dos lotes: suman contra lo pedido.
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', queso, 4, 'X', 'L1');
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', queso, 6, 'X', 'L2');
  perform public.iniciar_control(v_rec, null);

  c := public.checklist_recepcion(v_rec);
  if not (c ->> 'cantidades_remito')::boolean then
    raise exception 'TEST 1: con orden no debería pedir remito: %', c;
  end if;
  if (c ->> 'motivos_diferencias')::boolean then
    raise exception 'TEST 2: recibir de menos debería exigir motivo: %', c;
  end if;

  perform public.fijar_control_item(v_rec, leche, null, 'FALTANTE', 'Vino menos');
  c := public.checklist_recepcion(v_rec);
  if not (c ->> 'motivos_diferencias')::boolean then
    raise exception 'TEST 3: con el motivo debería quedar completo: %', c;
  end if;
  if (select i.cant_remito from public.recepcion_items i where i.recepcion_id = v_rec and i.producto_id = leche) is not null then
    raise exception 'TEST 4: no debería guardar un remito inventado';
  end if;
end;
$$;

-- Sin orden de compra, el remito sigue siendo obligatorio.
do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  prov constant uuid := '00000000-0000-4000-e000-0000000000d1';
  leche constant uuid := '00000000-0000-4000-e000-0000000000b1';
  v_sin uuid := gen_random_uuid();
  c jsonb;
begin
  perform public.abrir_recepcion(v_sin, prov, 'R-2', s);
  perform public.registrar_lectura(gen_random_uuid(), v_sin, 'ESCANEO', leche, 3, 'X');
  perform public.iniciar_control(v_sin, null);
  c := public.checklist_recepcion(v_sin);
  if (c ->> 'cantidades_remito')::boolean then
    raise exception 'TEST 5: sin orden debería pedir el remito: %', c;
  end if;
  begin
    perform public.fijar_control_item(v_sin, leche, null);
    raise exception 'TEST 6: sin orden aceptó un control sin remito' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  perform public.fijar_control_item(v_sin, leche, 3);
  c := public.checklist_recepcion(v_sin);
  if not (c ->> 'cantidades_remito')::boolean then
    raise exception 'TEST 7: %', c;
  end if;
end;
$$;

do $$
declare
  v_rec uuid := (select id from ids where clave = 'rec');
  v_oc uuid := (select id from ids where clave = 'oc');
begin
  if public.cerrar_recepcion(v_rec) <> 'CERRADA_CON_DIFERENCIAS' then
    raise exception 'TEST 8: debería cerrar con diferencias';
  end if;
  if (select o.estado <> 'RECIBIDA_PARCIAL' from public.ordenes_compra o where o.id = v_oc) then
    raise exception 'TEST 9: la orden debería quedar recibida en parte';
  end if;
  if (select s2.cant_pedida - s2.cant_recibida from public.v_oc_saldos s2 where s2.oc_id = v_oc and s2.producto_nombre = 'Queso con lote test') <> 0 then
    raise exception 'TEST 10: los dos lotes deberían cubrir lo pedido';
  end if;
  if (select b.items_con_diferencia from public.v_recepciones_bandeja b where b.id = v_rec) <> 1 then
    raise exception 'TEST 11: solo la leche tiene diferencia';
  end if;
end;
$$;

reset role;
select 'recepcion_sin_remito: todos los tests pasaron' as resultado;
rollback;
