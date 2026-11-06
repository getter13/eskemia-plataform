-- Eskemia · Test de aislamiento A/B entre organizaciones (pgTAP).
--
-- Qué verifica: con datos cargados en TODAS las tablas para dos organizaciones (A y B),
-- la titular de A no ve ninguna fila de B, ni en las tablas privadas ni en las vistas
-- de api, y no puede operar sobre entidades de B por RPC.
-- Dónde encaja: regla "Tests de aislamiento A/B para toda tabla nueva". El test recorre
-- el catálogo: una tabla nueva queda cubierta sola, y si no se le cargan datos de B el
-- test falla avisando que falta poblarla.

select pruebas.usuario('a0000000-0000-4000-8000-000000000001', 'ana@eskemia.test', 'Ana');
select pruebas.usuario('b0000000-0000-4000-8000-000000000001', 'beto@eskemia.test', 'Beto');

/** Puebla una organización completa por RPC actuando como su titular. */
create function pruebas.poblar(p_nombre text, p_cuit text)
returns uuid
language plpgsql
as $$
declare
  v_org uuid := (api.crear_organizacion(p_nombre) ->> 'id')::uuid;
  v_sede uuid := (select s.id from api.sedes s where s.organizacion_id = v_org);
  v_rubro uuid := api.guardar_rubro(v_org, gen_random_uuid(), 'Almacén');
  v_cat uuid := api.guardar_categoria(v_org, gen_random_uuid(), v_rubro, 'Secos');
  v_prod uuid := api.guardar_producto(v_org, gen_random_uuid(), v_cat, 'Yerba', 'UN');
  v_prov uuid := api.guardar_proveedor(v_org, gen_random_uuid(), 'Proveedor ' || p_nombre, p_cuit);
  v_pres uuid := (select p.id from api.presentaciones p where p.producto_id = v_prod);
  v_oferta uuid;
  v_oc uuid;
  v_rec uuid := gen_random_uuid();
begin
  perform api.guardar_codigo(v_org, gen_random_uuid(), v_prod, v_pres, '7799000000013', 'EAN13');
  v_oferta := api.guardar_producto_proveedor(v_org, gen_random_uuid(), v_prod, v_prov, v_pres, 100, null, true);
  perform api.guardar_regla_aprobacion(v_org, 'EMPRESA', null, 'NUNCA', null, 0);
  perform api.fijar_autoaprobacion(v_org, true);
  perform api.confirmar_pedido(gen_random_uuid(), v_sede,
    jsonb_build_array(jsonb_build_object('oferta_id', v_oferta, 'cantidad', 2)));
  v_oc := (select o.id from api.ordenes_compra o where o.organizacion_id = v_org);
  perform api.registrar_dispositivo(v_org, gen_random_uuid(), 'Kiosco', v_sede);
  perform api.abrir_recepcion(v_org, v_rec, v_prov, 'R-0001', v_sede, null, null, v_oc);
  perform api.registrar_lectura(gen_random_uuid(), v_rec, 'MANUAL', v_prod, 1, null, null, null, 'conteo');
  perform api.invitar(v_org, 'invitado@eskemia.test', null,
    (select r.id from api.roles r where r.organizacion_id = v_org and r.nombre = 'Comprador'));
  perform api.crear_rol(v_org, 'Rol extra');
  perform api.guardar_inicio(v_org, '[{"codigo": "compras.pendientes"}, {"codigo": "recepcion.hoy"}]');
  return v_org;
end;
$$;
grant execute on function pruebas.poblar(text, text) to authenticated;

select pruebas.como('a0000000-0000-4000-8000-000000000001');
create temp table orgs as select 'A'::text as cual, pruebas.poblar('Alfa', '30900000010') as id;
reset role;
grant select, insert on orgs to authenticated;
select pruebas.como('b0000000-0000-4000-8000-000000000001');
insert into orgs select 'B', pruebas.poblar('Beta', '30900001017');
reset role;

-- Tablas que todavía no tienen RPC (sectores, puestos propios, colab) o necesitan Storage (adjuntos):
-- se cargan directo, como postgres.
insert into nucleo.sectores (organizacion_id, nombre) select id, 'Cocina' from orgs;
insert into nucleo.puestos (organizacion_id, nombre) select id, 'Puesto propio' from orgs;
insert into compras.sector_rubros (organizacion_id, sector_id, rubro_id)
  select o.id, s.id, r.id from orgs o
  join nucleo.sectores s on s.organizacion_id = o.id
  join compras.rubros r on r.organizacion_id = o.id;
insert into recepcion.adjuntos (organizacion_id, sede_id, recepcion_id, tipo, storage_path, client_uuid, usuario_id)
  select r.organizacion_id, r.sede_id, r.id, 'REMITO',
         r.organizacion_id || '/' || r.sede_id || '/' || r.id || '/remito.jpg', gen_random_uuid(), r.usuario_id
  from recepcion.recepciones r;
insert into colab.salas (organizacion_id, nombre, privada, creada_por)
  select o.id, 'General', false, org.titular_id from orgs o join nucleo.organizaciones org on org.id = o.id;
insert into colab.sala_miembros (organizacion_id, sala_id, cuenta_id)
  select s.organizacion_id, s.id, s.creada_por from colab.salas s;
insert into colab.sala_lecturas (organizacion_id, sala_id, cuenta_id)
  select s.organizacion_id, s.id, s.creada_por from colab.salas s;
insert into colab.mensajes (organizacion_id, sala_id, cuenta_id, texto)
  select s.organizacion_id, s.id, s.creada_por, 'Hola' from colab.salas s;

-- Relaciones a revisar: toda tabla y vista con organizacion_id.
create temp table relaciones as
  select n.nspname || '.' || c.relname as relacion, c.relkind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attname = 'organizacion_id' and not a.attisdropped
  where (n.nspname in ('nucleo', 'compras', 'recepcion', 'colab') and c.relkind = 'r')
     or (n.nspname = 'api' and c.relkind = 'v');

create temp table conteos (relacion text, de_b_como_postgres bigint, de_b_como_a bigint, propias_como_a bigint);
insert into conteos (relacion, de_b_como_postgres)
  select r.relacion, pruebas.filas_de(r.relacion, (select id from orgs where cual = 'B'))
  from relaciones r where r.relkind = 'r';
grant select, insert, update on conteos to authenticated;
grant select on relaciones to authenticated;

select pruebas.como('a0000000-0000-4000-8000-000000000001');
insert into conteos (relacion) select r.relacion from relaciones r where r.relkind = 'v';
update conteos c set
  de_b_como_a = pruebas.filas_de(c.relacion, (select id from orgs where cual = 'B')),
  propias_como_a = pruebas.filas_de(c.relacion, (select id from orgs where cual = 'A'))
where c.relacion not in ('compras.secuencias');  -- sin política: nadie la lee fuera de las RPC

-- Intentos de operar sobre B desde A.
create temp table intentos (rpc text, error text);
grant insert on intentos to authenticated;
do $$
declare
  v_b uuid := (select id from orgs where cual = 'B');
  v_oc uuid := (select o.id from compras.ordenes_compra o where o.organizacion_id = v_b);
  v_rec uuid := (select r.id from recepcion.recepciones r where r.organizacion_id = v_b);
  v_prod uuid := (select p.id from compras.productos p where p.organizacion_id = v_b);
begin
  begin perform api.guardar_rubro(v_b, gen_random_uuid(), 'Intruso');
  exception when others then insert into intentos values ('guardar_rubro', sqlerrm); end;
  begin perform api.anular_oc(v_oc, 'intruso');
  exception when others then insert into intentos values ('anular_oc', sqlerrm); end;
  begin perform api.validar_recepcion(v_rec);
  exception when others then insert into intentos values ('validar_recepcion', sqlerrm); end;
  begin perform api.fijar_sku_producto(v_prod, 'X');
  exception when others then insert into intentos values ('fijar_sku_producto', sqlerrm); end;
  begin perform api.invitar(v_b, 'x@eskemia.test', null, null);
  exception when others then insert into intentos values ('invitar', sqlerrm); end;
end;
$$;
reset role;

select * from no_plan();

select is(
  (select array_agg(relacion order by relacion) from conteos
   where relacion not like 'api.%' and coalesce(de_b_como_postgres, 0) = 0),
  null,
  'B tiene datos en todas las tablas (si falla, poblar la tabla nueva en este test)'
);

select is(
  (select array_agg(relacion order by relacion) from conteos where de_b_como_a > 0),
  null,
  'A no ve ninguna fila de B en tablas ni vistas'
);

select ok(
  (select propias_como_a from conteos where relacion = 'api.ordenes_compra') > 0
  and (select propias_como_a from conteos where relacion = 'api.recepciones') > 0
  and (select propias_como_a from conteos where relacion = 'nucleo.eventos') > 0,
  'A sí ve sus propias órdenes, recepciones y eventos (el test no pasa por ver todo vacío)'
);

select is(
  (select count(*)::int from intentos where error ~ '^(SIN_PERMISO|NO_ENCONTRADO)'),
  5,
  'las RPC sobre B responden SIN_PERMISO o NO_ENCONTRADO'
);

select is(
  (select count(*)::int from relaciones where relkind = 'r'),
  (select count(*)::int from conteos where de_b_como_postgres is not null),
  'se revisaron todas las tablas con organizacion_id'
);

-- Tablas sin organizacion_id: organizaciones y cuentas.
select pruebas.como('a0000000-0000-4000-8000-000000000001');
create temp table globales as select
  (select count(*) from nucleo.organizaciones where id = (select id from orgs where cual = 'B')) as org_b,
  (select count(*) from nucleo.cuentas where id = 'b0000000-0000-4000-8000-000000000001') as cuenta_b,
  (select count(*) from api.mis_organizaciones) as mis_orgs;
reset role;

select is((select org_b from globales), 0::bigint, 'A no ve la organización B');
select is((select cuenta_b from globales), 0::bigint, 'A no ve la cuenta de Beto (no comparten organización)');
select is((select mis_orgs from globales), 1::bigint, 'mis_organizaciones de A tiene solo la suya');

select * from finish();
