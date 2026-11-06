-- Eskemia · Tests del catálogo de tarjetas del Inicio (pgTAP).
--
-- Qué verifica: guardar_inicio acepta solo tarjetas elegibles (módulo habilitado y
-- permiso), tarjetas_disponibles ofrece exactamente esas, y mi_inicio oculta sin error
-- las que se pierden al deshabilitar un módulo o retirar un rol, y las devuelve al
-- restituirlos.
-- Dónde encaja: db/pruebas, corre con db/scripts/pruebas.sh (local y CI). CLAUDE.md, "Inicio".

select pruebas.escenario();
select * from no_plan();

-- Operario de recepción (en la sede principal) ------------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000002');
do $$
declare
  o uuid := pruebas.id('org');
begin
  perform pruebas.no('el operario dispone de las tarjetas de su rol y de Salas',
    (select string_agg(codigo, ',' order by codigo) from api.tarjetas_disponibles where organizacion_id = o)
    is distinct from 'colab.salas,recepcion.hoy,recepcion.pendientes');
  perform api.guardar_inicio(o, '[{"codigo": "recepcion.hoy"}, {"codigo": "colab.salas"}]');
  perform pruebas.no('guarda tarjetas elegibles', (select count(*) from api.mi_inicio) <> 2);
  perform pruebas.falla('rechaza una tarjeta sin permiso', 'PRECONDICION: estas tarjetas no están disponibles para vos: compras.pendientes',
    format('select api.guardar_inicio(%L, %L)', o, '[{"codigo": "recepcion.hoy"}, {"codigo": "compras.pendientes"}]'));
  perform pruebas.falla('rechaza una tarjeta inexistente', 'PRECONDICION: estas tarjetas no están disponibles',
    format('select api.guardar_inicio(%L, %L)', o, '[{"codigo": "compras.inventada"}]'));
  perform pruebas.no('un rechazo no toca lo guardado', (select count(*) from api.mi_inicio) <> 2);
end;
$$;
reset role;

-- Titular (Admin) ---------------------------------------------------------------------
select pruebas.como('e0000000-0000-4000-8000-000000000001');
select api.guardar_inicio(pruebas.id('org'),
  '[{"codigo": "compras.pendientes"}, {"codigo": "recepcion.hoy"}, {"codigo": "nucleo.usuarios"}]');
reset role;

-- Se deshabilita Compras: Recepción depende de Compras, así que caen las dos.
delete from nucleo.modulos_habilitados where organizacion_id = pruebas.id('org') and modulo_codigo = 'compras';
select pruebas.como('e0000000-0000-4000-8000-000000000001');
select pruebas.no('sin Compras, el Inicio muestra solo lo del núcleo',
  (select string_agg(tarjeta_codigo, ',' order by orden) from api.mi_inicio) is distinct from 'nucleo.usuarios');
select pruebas.no('y Compras deja de estar disponible',
  exists (select 1 from api.tarjetas_disponibles where modulo in ('compras', 'recepcion')));
reset role;

insert into nucleo.modulos_habilitados (organizacion_id, modulo_codigo) values (pruebas.id('org'), 'compras');
select pruebas.como('e0000000-0000-4000-8000-000000000001');
select pruebas.no('al rehabilitarlo, las tarjetas vuelven en su orden',
  (select string_agg(tarjeta_codigo, ',' order by orden) from api.mi_inicio)
  is distinct from 'compras.pendientes,recepcion.hoy,nucleo.usuarios');
reset role;

-- Al operario le retiran el rol: su Inicio queda solo con Salas, sin errores.
select pruebas.rol_de('e0000000-0000-4000-8000-000000000002', null);
select pruebas.como('e0000000-0000-4000-8000-000000000002');
select pruebas.no('sin rol, el operario conserva solo Salas',
  (select string_agg(tarjeta_codigo, ',') from api.mi_inicio) is distinct from 'colab.salas');
reset role;

select ok(ok, nombre) from chequeos order by n;
select * from finish();
