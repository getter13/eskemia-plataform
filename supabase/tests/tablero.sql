-- Eskemia · Tests de anular y cerrar saldo. No deja rastro: todo termina en ROLLBACK.
-- Uso: npx supabase db query --remote --yes -f supabase/tests/tablero.sql
-- Cualquier falla aborta con el error; si llega al final, pasó.
-- Emite el admin de prueba; recibe el operario de prueba.

begin;

-- Las órdenes demo no cuentan: esto también se deshace con el ROLLBACK.
update public.recepciones set oc_id = null where oc_id is not null;
delete from public.oc_items;
delete from public.ordenes_compra;
delete from public.pedido_items;
delete from public.pedidos_compra;

create function pg_temp.rol_de(p_user uuid, p_rol text)
returns void language plpgsql as $$
begin
  delete from public.usuario_roles where user_id = p_user;
  insert into public.usuario_roles (tenant_id, user_id, rol_id, sede_id)
  select r.tenant_id, p_user, r.id, '00000000-0000-4000-8000-000000000002' from public.roles r
  where r.tenant_id = '00000000-0000-4000-8000-000000000001' and r.nombre = p_rol;
end;
$$;

create temp table ids (clave text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

do $$
declare
  t constant uuid := '00000000-0000-4000-8000-000000000001';
  v_pre uuid;
begin
  insert into public.productos (id, tenant_id, nombre, tipo_medida)
  values ('00000000-0000-4000-e000-0000000000b1', t, 'Leche test', 'UNIDAD');
  insert into public.proveedores (id, tenant_id, nombre, cuit)
  values ('00000000-0000-4000-e000-0000000000d1', t, 'Prov test', '30999999991');
  select id into v_pre from public.presentaciones where producto_id = '00000000-0000-4000-e000-0000000000b1';
  insert into public.producto_proveedor (id, tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual)
  values ('00000000-0000-4000-e000-0000000000f1', t, '00000000-0000-4000-e000-0000000000b1', '00000000-0000-4000-e000-0000000000d1', v_pre, 100);
  perform pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Comprador');
end;
$$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  r jsonb;
  i int;
begin
  for i in 1 .. 4 loop
    r := public.confirmar_pedido(gen_random_uuid(), s, jsonb_build_array(
      jsonb_build_object('oferta_id', '00000000-0000-4000-e000-0000000000f1', 'cantidad', 10)));
    insert into ids values ('oc' || i, (r -> 'ordenes' -> 0 ->> 'id')::uuid);
  end loop;

  -- El comprador no anula ni cierra.
  begin
    perform public.anular_oc((select id from ids where clave = 'oc1'), 'x');
    raise exception 'TEST 1: el comprador anuló' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.cerrar_saldo_oc((select id from ids where clave = 'oc1'), 'x');
    raise exception 'TEST 2: el comprador cerró el saldo' using errcode = 'ZZ001';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- El operario recibe parte de oc2, y deja oc3 con una recepción en curso.
reset role;
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
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  prov constant uuid := '00000000-0000-4000-e000-0000000000d1';
  prod constant uuid := '00000000-0000-4000-e000-0000000000b1';
  v_rec uuid := gen_random_uuid();
  v_curso uuid := gen_random_uuid();
begin
  perform public.abrir_recepcion(v_rec, prov, 'R-1', s, null, null, (select id from ids where clave = 'oc2'));
  perform public.registrar_lectura(gen_random_uuid(), v_rec, 'ESCANEO', prod, 4, 'X');
  perform public.iniciar_control(v_rec, null);
  perform public.fijar_control_item(v_rec, prod, 4, 'FALTANTE', 'Vino menos');
  perform public.cerrar_recepcion(v_rec);

  perform public.abrir_recepcion(v_curso, prov, 'R-2', s, null, null, (select id from ids where clave = 'oc3'));
  insert into ids values ('curso', v_curso);
end;
$$;

-- Gerente: anula y cierra.
reset role;
select pg_temp.rol_de('00000000-0000-4000-c000-000000000002', 'Gerente');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  s constant uuid := '00000000-0000-4000-8000-000000000002';
  v_anular uuid := (select id from ids where clave = 'oc1');
  v_parcial uuid := (select id from ids where clave = 'oc2');
  v_curso uuid := (select id from ids where clave = 'oc3');
  v_enviada uuid := (select id from ids where clave = 'oc4');
begin
  begin
    perform public.anular_oc(v_anular, '  ');
    raise exception 'TEST 3: anuló sin motivo' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  if public.anular_oc(v_anular, 'Ya no hace falta') <> 'ANULADA' then raise exception 'TEST 4: no anuló'; end if;
  if public.anular_oc(v_anular, 'Ya no hace falta') <> 'ANULADA' then raise exception 'TEST 5: reintento'; end if;
  if (select o.motivo_cierre <> 'Ya no hace falta' from public.ordenes_compra o where o.id = v_anular) then
    raise exception 'TEST 6: no guardó el motivo';
  end if;
  if (select o.estado <> 'ANULADA' from public.ordenes_compra o where o.id = v_anular) then
    raise exception 'TEST 7: la anulada cambió de estado';
  end if;

  perform public.marcar_oc_enviada(v_enviada);
  if public.anular_oc(v_enviada, 'Se canceló') <> 'ANULADA' then raise exception 'TEST 8: no anuló una enviada'; end if;

  begin
    perform public.anular_oc(v_parcial, 'x');
    raise exception 'TEST 9: anuló una orden con recepciones' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.anular_oc(v_curso, 'x');
    raise exception 'TEST 10: anuló con una recepción en curso' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  begin
    perform public.cerrar_saldo_oc(v_curso, 'x');
    raise exception 'TEST 11: cerró el saldo de una orden sin recibir' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
  begin
    perform public.cerrar_saldo_oc(v_parcial, '');
    raise exception 'TEST 12: cerró el saldo sin motivo' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;

  if public.cerrar_saldo_oc(v_parcial, 'El proveedor no tiene stock') <> 'CERRADA' then
    raise exception 'TEST 13: no cerró el saldo';
  end if;
  if public.cerrar_saldo_oc(v_parcial, 'El proveedor no tiene stock') <> 'CERRADA' then
    raise exception 'TEST 14: reintento';
  end if;
  if (select o.estado <> 'CERRADA' from public.ordenes_compra o where o.id = v_parcial) then
    raise exception 'TEST 15: con el saldo cerrado sigue pendiente';
  end if;
  -- Queda el dato para administración.
  if (select s2.cant_recibida from public.v_oc_saldos s2 where s2.oc_id = v_parcial) <> 4 then
    raise exception 'TEST 16: el saldo no refleja lo recibido';
  end if;
  if not (select count(*) = 4 from public.ordenes_compra) then
    raise exception 'TEST 17: el gerente debería ver todas';
  end if;
end;
$$;

-- Recepción en curso sobre una orden parcial: no se cierra el saldo.
reset role;
update public.ordenes_compra set estado = 'RECIBIDA_PARCIAL' where id = (select id from ids where clave = 'oc3');
set local role authenticated;
do $$
begin
  begin
    perform public.cerrar_saldo_oc((select id from ids where clave = 'oc3'), 'x');
    raise exception 'TEST 18: cerró con una recepción en curso' using errcode = 'ZZ001';
  exception when raise_exception then
    if sqlerrm like 'TEST%' then raise; end if;
  end;
end;
$$;

reset role;
do $$
begin
  if not exists (select 1 from public.eventos where entidad = 'orden_compra' and accion = 'estado:ANULADA')
     or not exists (select 1 from public.eventos where entidad = 'orden_compra' and accion = 'estado:CERRADA') then
    raise exception 'TEST 19: faltan eventos';
  end if;
end;
$$;

select 'tablero: todos los tests pasaron' as resultado;
rollback;
