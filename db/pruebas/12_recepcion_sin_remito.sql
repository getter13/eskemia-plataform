-- Eskemia · Recibir sobre una orden no pide remito; sin orden, sí (pgTAP). Portado de
-- supabase/tests/recepcion_sin_remito.sql (legado).
--
-- Qué verifica: con OC el checklist no exige cantidades de remito y lo recibido de menos
-- pide motivo; dos lotes del mismo producto suman contra lo pedido; sin OC el remito es
-- obligatorio.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- Pide y recibe la titular (Admin), como en el legado.

select pruebas.escenario();
create temp table ids (clave text primary key, id uuid);
grant select, insert on ids to authenticated;
select * from no_plan();

create function pg_temp.foto_al_abrir()
returns trigger language plpgsql security definer as $$
begin
  insert into recepcion.adjuntos (organizacion_id, sede_id, recepcion_id, tipo, storage_path, client_uuid, usuario_id)
  select new.organizacion_id, new.sede_id, new.id, t.tipo::recepcion.tipo_adjunto, 'test/' || gen_random_uuid(), gen_random_uuid(), new.usuario_id
  from (values ('REMITO'), ('FIRMA_RECEPTOR'), ('FIRMA_TRANSPORTISTA')) as t (tipo);
  return null;
end;
$$;
create trigger foto_al_abrir after insert on recepcion.recepciones
  for each row execute function pg_temp.foto_al_abrir();

do $$
declare
  o uuid := pruebas.id('org');
begin
  insert into compras.productos (id, organizacion_id, nombre, tipo_medida, requiere_lote) values
    ('e0000000-0000-4000-e000-0000000000b1', o, 'Leche test', 'UNIDAD', false),
    ('e0000000-0000-4000-e000-0000000000b2', o, 'Queso con lote test', 'UNIDAD', true),
    ('e0000000-0000-4000-e000-0000000000b3', o, 'Coincide test', 'UNIDAD', false);
  insert into compras.proveedores (id, organizacion_id, nombre, cuit)
  values ('e0000000-0000-4000-e000-0000000000d1', o, 'Prov test', '30999999991');
  insert into compras.producto_proveedor (organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  select o, pr.producto_id, 'e0000000-0000-4000-e000-0000000000d1', pr.id, 100
  from compras.presentaciones pr where pr.organizacion_id = o;
end;
$$;

select pruebas.como('e0000000-0000-4000-8000-000000000001');
do $$
declare
  o uuid := pruebas.id('org');
  s uuid := pruebas.id('sede');
  prov constant uuid := 'e0000000-0000-4000-e000-0000000000d1';
  leche constant uuid := 'e0000000-0000-4000-e000-0000000000b1';
  queso constant uuid := 'e0000000-0000-4000-e000-0000000000b2';
  igual constant uuid := 'e0000000-0000-4000-e000-0000000000b3';
  r jsonb;
  c jsonb;
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
  v_sin uuid := gen_random_uuid();
begin
  r := api.confirmar_pedido(gen_random_uuid(), s, (
    select jsonb_agg(jsonb_build_object('oferta_id', pp.id, 'cantidad', 10))
    from api.producto_proveedor pp where pp.proveedor_id = prov));
  v_oc := (r -> 'ordenes' -> 0 ->> 'id')::uuid;
  perform api.abrir_recepcion(o, v_rec, prov, 'R-1', s, null, null, v_oc);
  insert into ids values ('rec', v_rec), ('oc', v_oc);

  -- Menos de lo esperado, sin remito cargado; el queso en dos lotes.
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', leche, 6, 'X');
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', igual, 10, 'X');
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', queso, 4, 'X', 'L1');
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', queso, 6, 'X', 'L2');
  perform api.iniciar_control(v_rec);

  c := api.checklist_recepcion(v_rec);
  perform pruebas.no('1: con orden no pide remito', not (c ->> 'cantidades_remito')::boolean);
  perform pruebas.no('2: recibir de menos exige motivo', (c ->> 'motivos_diferencias')::boolean);
  perform api.fijar_control_item(v_rec, leche, null, 'FALTANTE', 'Vino menos');
  c := api.checklist_recepcion(v_rec);
  perform pruebas.no('3: con el motivo queda completo', not (c ->> 'motivos_diferencias')::boolean);
  perform pruebas.no('4: no guarda un remito inventado',
    (select i.cant_remito from api.recepcion_items i where i.recepcion_id = v_rec and i.producto_id = leche) is not null);

  -- Sin orden de compra, el remito sigue siendo obligatorio.
  perform api.abrir_recepcion(o, v_sin, prov, 'R-2', s);
  perform api.registrar_lectura(gen_random_uuid(), v_sin, 'ESCANEO', leche, 3, 'X');
  perform api.iniciar_control(v_sin);
  c := api.checklist_recepcion(v_sin);
  perform pruebas.no('5: sin orden pide el remito', (c ->> 'cantidades_remito')::boolean);
  perform pruebas.falla('6: sin orden no acepta un control sin remito', 'PRECONDICION',
    format('select api.fijar_control_item(%L, %L, null)', v_sin, leche));
  perform api.fijar_control_item(v_sin, leche, 3);
  c := api.checklist_recepcion(v_sin);
  perform pruebas.no('7: con el remito queda completo', not (c ->> 'cantidades_remito')::boolean);

  perform pruebas.no('8: cierra con diferencias', api.cerrar_recepcion(v_rec) <> 'CERRADA_CON_DIFERENCIAS');
  perform pruebas.no('9: la orden queda recibida en parte',
    (select o2.estado <> 'RECIBIDA_PARCIAL' from api.ordenes_compra o2 where o2.id = v_oc));
  perform pruebas.no('10: los dos lotes cubren lo pedido',
    (select s2.cant_pedida - s2.cant_recibida from api.oc_saldos s2 where s2.oc_id = v_oc and s2.producto_nombre = 'Queso con lote test') <> 0);
  perform pruebas.no('11: solo la leche tiene diferencia',
    (select b.items_con_diferencia from api.recepciones_bandeja b where b.id = v_rec) <> 1);
end;
$$;
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
