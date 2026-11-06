-- Eskemia · Test estructural de la línea base (pgTAP).
--
-- Qué verifica, para TODA tabla de nucleo, compras, recepcion y colab:
--   - RLS habilitado y FORZADO;
--   - organizacion_id NOT NULL, salvo los catálogos globales listados abajo;
--   - toda política de lectura usa nucleo.es_miembro (salvo las listadas);
--   - authenticated no puede insertar, actualizar ni borrar; anon no lee nada.
-- Y para el esquema api: vistas security_invoker; anon no ejecuta ninguna RPC.
-- Dónde encaja: CLAUDE.md, "Reglas no negociables". Una tabla nueva que no cumpla
-- hace fallar el CI. Para sumar una excepción hay que agregarla acá, a la vista.

-- Excepciones explícitas -------------------------------------------------------
create temp table sin_organizacion (tabla text primary key, motivo text);
insert into sin_organizacion values
  ('nucleo.cuentas', 'identidad global de la persona'),
  ('nucleo.organizaciones', 'su id es la organización'),
  ('nucleo.permisos', 'catálogo global'),
  ('nucleo.modulos', 'catálogo global'),
  ('nucleo.puestos', 'catálogo global en las filas con organizacion_id nulo');

create temp table politicas_sin_es_miembro (politica text primary key, motivo text);
insert into politicas_sin_es_miembro values
  ('nucleo.cuentas.cuentas_select', 'propia o de alguien que comparte organización'),
  ('nucleo.permisos.permisos_select', 'catálogo global'),
  ('nucleo.modulos.modulos_select', 'catálogo global');

create temp view tablas as
  select n.nspname || '.' || c.relname as tabla, c.oid, c.relrowsecurity, c.relforcerowsecurity
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('nucleo', 'compras', 'recepcion', 'colab') and c.relkind = 'r';

select * from no_plan();

select ok((select count(*) from tablas) >= 40, 'hay al menos 40 tablas en los esquemas de Eskemia');

select is(
  (select array_agg(tabla order by tabla) from tablas where not (relrowsecurity and relforcerowsecurity)),
  null,
  'todas las tablas tienen RLS habilitado y forzado'
);

select is(
  (select array_agg(t.tabla order by t.tabla)
   from tablas t
   where t.tabla not in (select tabla from sin_organizacion)
     and not exists (
       select 1 from pg_attribute a
       where a.attrelid = t.oid and a.attname = 'organizacion_id' and a.attnotnull and not a.attisdropped
     )),
  null,
  'toda tabla con datos de organización tiene organizacion_id NOT NULL'
);

select is(
  (select array_agg(p.schemaname || '.' || p.tablename || '.' || p.policyname order by 1)
   from pg_policies p
   where p.schemaname in ('nucleo', 'compras', 'recepcion', 'colab')
     and p.schemaname || '.' || p.tablename || '.' || p.policyname not in (select politica from politicas_sin_es_miembro)
     and coalesce(p.qual, '') not like '%es_miembro(%'),
  null,
  'toda política usa nucleo.es_miembro (salvo las excepciones listadas)'
);

select is(
  (select array_agg(tabla order by tabla) from tablas
   where has_table_privilege('authenticated', oid, 'insert')
      or has_table_privilege('authenticated', oid, 'update')
      or has_table_privilege('authenticated', oid, 'delete')),
  null,
  'authenticated no escribe directo en ninguna tabla (todo por RPC)'
);

select is(
  (select array_agg(tabla order by tabla) from tablas where has_table_privilege('anon', oid, 'select')),
  null,
  'anon no lee ninguna tabla'
);

select is(
  (select array_agg(c.relname order by c.relname)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'api' and c.relkind = 'v'
     and not coalesce(c.reloptions @> array['security_invoker=true'], false)),
  null,
  'todas las vistas de api son security_invoker'
);

select is(
  (select array_agg(c.relname order by c.relname)
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'api' and c.relkind in ('r', 'm', 'f', 'p')),
  null,
  'api no tiene tablas: solo vistas y funciones'
);

select is(
  (select array_agg(p.proname order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'api' and has_function_privilege('anon', p.oid, 'execute')),
  null,
  'anon no ejecuta ninguna RPC de api'
);

select is(
  (select array_agg(n.nspname || '.' || p.proname order by 1)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('nucleo', 'compras', 'recepcion', 'colab', 'api')
     and p.prosecdef
     and not coalesce(p.proconfig @> array['search_path=""'], false)),
  null,
  'toda función SECURITY DEFINER fija search_path vacío'
);

select is(
  (select count(*)::int from nucleo.permisos), 18, 'el catálogo tiene 18 permisos'
);

select set_eq(
  'select codigo from nucleo.modulos', array['compras', 'recepcion', 'colab'],
  'módulos registrados: compras, recepcion y colab'
);

select ok(
  not has_table_privilege('authenticated', 'pgmq.q_emails', 'select'),
  'authenticated no lee la cola de emails'
);

select * from finish();
