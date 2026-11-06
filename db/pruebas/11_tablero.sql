-- Eskemia · Tests de anular y cerrar saldo de órdenes (pgTAP). Portado de
-- supabase/tests/tablero.sql (legado).
--
-- Qué verifica: solo quien tiene permiso anula o cierra saldo; anular exige motivo, es
-- idempotente y no aplica con recepciones; cerrar saldo exige algo recibido, motivo y
-- ninguna recepción en curso; quedan los eventos.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI).
-- Emite la cuenta "persona"; recibe el operario del escenario.

select pruebas.escenario();
create temp table ids (clave text primary key, id uuid);
grant select, insert on ids to authenticated;
select * from no_plan();

do $$
declare
  o uuid := pruebas.id('org');
  v_pre uuid;
begin
  insert into compras.productos (id, organizacion_id, nombre, tipo_medida)
  values ('e0000000-0000-4000-e000-0000000000b1', o, 'Leche test', 'UNIDAD');
  insert into compras.proveedores (id, organizacion_id, nombre, cuit)
  values ('e0000000-0000-4000-e000-0000000000d1', o, 'Prov test', '30999999991');
  select id into v_pre from compras.presentaciones where producto_id = 'e0000000-0000-4000-e000-0000000000b1';
  insert into compras.producto_proveedor (id, organizacion_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  values ('e0000000-0000-4000-e000-0000000000f1', o, 'e0000000-0000-4000-e000-0000000000b1', 'e0000000-0000-4000-e000-0000000000d1', v_pre, 100);
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Comprador', pruebas.id('sede'));
end;
$$;

select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  r jsonb;
  i int;
begin
  for i in 1 .. 4 loop
    r := api.confirmar_pedido(gen_random_uuid(), pruebas.id('sede'), jsonb_build_array(
      jsonb_build_object('oferta_id', 'e0000000-0000-4000-e000-0000000000f1', 'cantidad', 10)));
    insert into ids values ('oc' || i, (r -> 'ordenes' -> 0 ->> 'id')::uuid);
  end loop;
  perform pruebas.falla('1: el comprador no anula', 'SIN_PERMISO',
    format('select api.anular_oc(%L, %L)', (select id from ids where clave = 'oc1'), 'x'));
  perform pruebas.falla('2: el comprador no cierra saldo', 'SIN_PERMISO',
    format('select api.cerrar_saldo_oc(%L, %L)', (select id from ids where clave = 'oc1'), 'x'));
end;
$$;
reset role;

-- El operario recibe parte de oc2 y deja oc3 con una recepción en curso.
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

select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  o uuid := pruebas.id('org');
  s uuid := pruebas.id('sede');
  prov constant uuid := 'e0000000-0000-4000-e000-0000000000d1';
  prod constant uuid := 'e0000000-0000-4000-e000-0000000000b1';
  v_rec uuid := gen_random_uuid();
begin
  perform api.abrir_recepcion(o, v_rec, prov, 'R-1', s, null, null, (select id from ids where clave = 'oc2'));
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 4, 'X');
  perform api.iniciar_control(v_rec);
  perform api.fijar_control_item(v_rec, prod, 4, 'FALTANTE', 'Vino menos');
  perform api.cerrar_recepcion(v_rec);
  perform api.abrir_recepcion(o, gen_random_uuid(), prov, 'R-2', s, null, null, (select id from ids where clave = 'oc3'));
end;
$$;
reset role;

-- Gerente: anula y cierra.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000003', 'Gerente', pruebas.id('sede'));
select pruebas.como('e0000000-0000-4000-8000-000000000003');
do $$
declare
  v_anular uuid := (select id from ids where clave = 'oc1');
  v_parcial uuid := (select id from ids where clave = 'oc2');
  v_curso uuid := (select id from ids where clave = 'oc3');
  v_enviada uuid := (select id from ids where clave = 'oc4');
begin
  perform pruebas.falla('3: no anula sin motivo', 'PRECONDICION', format('select api.anular_oc(%L, %L)', v_anular, '  '));
  perform pruebas.no('4: anula', api.anular_oc(v_anular, 'Ya no hace falta') <> 'ANULADA');
  perform pruebas.no('5: el reintento responde igual', api.anular_oc(v_anular, 'Ya no hace falta') <> 'ANULADA');
  perform pruebas.no('6: guarda el motivo', (select o.motivo_cierre <> 'Ya no hace falta' from api.ordenes_compra o where o.id = v_anular));
  perform pruebas.no('7: queda anulada', (select o.estado <> 'ANULADA' from api.ordenes_compra o where o.id = v_anular));

  perform api.marcar_oc_enviada(v_enviada);
  perform pruebas.no('8: anula una enviada', api.anular_oc(v_enviada, 'Se canceló') <> 'ANULADA');
  perform pruebas.falla('9: no anula una orden con recepciones', 'PRECONDICION', format('select api.anular_oc(%L, %L)', v_parcial, 'x'));
  perform pruebas.falla('10: no anula con una recepción en curso', 'PRECONDICION', format('select api.anular_oc(%L, %L)', v_curso, 'x'));

  perform pruebas.falla('11: no cierra el saldo de una orden sin recibir', 'PRECONDICION', format('select api.cerrar_saldo_oc(%L, %L)', v_curso, 'x'));
  perform pruebas.falla('12: no cierra el saldo sin motivo', 'PRECONDICION', format('select api.cerrar_saldo_oc(%L, %L)', v_parcial, ''));
  perform pruebas.no('13: cierra el saldo', api.cerrar_saldo_oc(v_parcial, 'El proveedor no tiene stock') <> 'CERRADA');
  perform pruebas.no('14: el reintento responde igual', api.cerrar_saldo_oc(v_parcial, 'El proveedor no tiene stock') <> 'CERRADA');
  perform pruebas.no('15: queda cerrada', (select o.estado <> 'CERRADA' from api.ordenes_compra o where o.id = v_parcial));
  perform pruebas.no('16: el saldo refleja lo recibido', (select s2.cant_recibida from api.oc_saldos s2 where s2.oc_id = v_parcial) <> 4);
  perform pruebas.no('17: el gerente ve todas', (select count(*) from api.ordenes_compra) <> 4);
end;
$$;
reset role;

-- Recepción en curso sobre una orden parcial: no se cierra el saldo.
update compras.ordenes_compra set estado = 'RECIBIDA_PARCIAL' where id = (select id from ids where clave = 'oc3');
select pruebas.como('e0000000-0000-4000-8000-000000000003');
select pruebas.falla('18: no cierra con una recepción en curso', 'PRECONDICION',
  format('select api.cerrar_saldo_oc(%L, %L)', (select id from ids where clave = 'oc3'), 'x'));
reset role;

select pruebas.no('19: quedan los eventos de anular y cerrar',
  not exists (select 1 from nucleo.eventos where entidad = 'orden_compra' and accion = 'estado:ANULADA')
  or not exists (select 1 from nucleo.eventos where entidad = 'orden_compra' and accion = 'estado:CERRADA'));

select ok(ok, nombre) from chequeos order by n;
select * from finish();
