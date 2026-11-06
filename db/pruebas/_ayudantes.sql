-- Eskemia · Ayudantes de los tests SQL.
--
-- Qué hace: crea el esquema pruebas (se descarta con el ROLLBACK del test) con funciones
-- para dar de alta usuarios de Auth y actuar como una cuenta.
-- Dónde encaja: pruebas.sh lo antepone a cada db/pruebas/NN_*.sql, dentro de la misma
-- transacción. Uso en un test:
--   select pruebas.usuario('…uuid…', 'ana@eskemia.test');
--   select pruebas.como('…uuid…');   -- desde acá corre como authenticated
--   reset role;                      -- vuelve a postgres

create schema pruebas;
grant usage on schema pruebas to authenticated;

/** Alta de un usuario de Auth con email confirmado (el trigger crea su cuenta). */
create function pruebas.usuario(p_id uuid, p_email text, p_nombre text default null)
returns uuid
language sql
as $$
  insert into auth.users (id, email, aud, role, email_confirmed_at, raw_user_meta_data)
  values (p_id, p_email, 'authenticated', 'authenticated', now(),
          jsonb_build_object('nombre', coalesce(p_nombre, split_part(p_email, '@', 1))));
  select p_id;
$$;

/** Pasa a actuar como la cuenta dada (rol authenticated con su JWT) hasta reset role. */
create function pruebas.como(p_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;
grant execute on function pruebas.como(uuid) to authenticated;

/** Cantidad de filas de una tabla o vista que pertenecen a la organización dada, con
 *  los permisos de quien llama. */
create function pruebas.filas_de(p_relacion text, p_organizacion_id uuid)
returns bigint
language plpgsql
as $$
declare
  v_n bigint;
begin
  execute format('select count(*) from %s where organizacion_id = $1', p_relacion)
    into v_n using p_organizacion_id;
  return v_n;
end;
$$;
grant execute on function pruebas.filas_de(text, uuid) to authenticated;

/** Ejecuta una sentencia con los permisos de quien llama y devuelve su primer valor como
 *  texto, 'OK' si no devuelve nada (o es void), o 'ERROR: <mensaje>' si falla. Permite registrar
 *  resultados actuando como una cuenta y verificarlos después con pgTAP. */
create function pruebas.ejecutar(p_sql text)
returns text
language plpgsql
as $$
declare
  v_valor text;
begin
  execute p_sql into v_valor;
  -- Una función void devuelve texto vacío, no null: ambos cuentan como OK.
  return coalesce(nullif(v_valor, ''), 'OK');
exception when others then
  return 'ERROR: ' || sqlerrm;
end;
$$;
grant execute on function pruebas.ejecutar(text) to authenticated;

-- Resultados registrados durante el test: clave → valor.
create temp table r (clave text primary key, valor text);
grant select, insert, update on r to authenticated;

/** Registra en r el resultado de ejecutar p_sql como la cuenta actual. */
create function pruebas.anotar(p_clave text, p_sql text)
returns text
language sql
as $$
  insert into r values (p_clave, pruebas.ejecutar(p_sql))
  on conflict (clave) do update set valor = excluded.valor
  returning valor;
$$;
grant execute on function pruebas.anotar(text, text) to authenticated;

-- Escenario estándar de los tests de módulos -------------------------------------
-- Una organización "Pruebas" con dos sedes y tres cuentas fijas:
--   titular  e…01: crea la organización (Admin en todas las sedes, no se toca);
--   operario e…02: Operario de recepción en la sede principal;
--   persona  e…03: sin rol; cada test le asigna el que necesita con pruebas.rol_de.

create temp table esc (clave text primary key, id uuid);
grant select on esc to authenticated;

/** Id guardado por pruebas.escenario(): 'org', 'sede' (principal) o 'sede2'. */
create function pruebas.id(p_clave text)
returns uuid
language sql
stable
as $$ select id from esc where clave = p_clave $$;
grant execute on function pruebas.id(text) to authenticated;

/** Deja a la cuenta como miembro activo de la organización del escenario con un solo
 *  rol semilla (o ninguno si p_rol es null), en la sede dada o en todas. */
create function pruebas.rol_de(p_cuenta uuid, p_rol text, p_sede uuid default null)
returns void
language plpgsql
as $$
declare
  v_org uuid := pruebas.id('org');
  v_membresia uuid;
begin
  insert into nucleo.membresias (organizacion_id, cuenta_id, estado, unida_en)
  values (v_org, p_cuenta, 'ACTIVA', now())
  on conflict (organizacion_id, cuenta_id) do update set estado = 'ACTIVA'
  returning id into v_membresia;
  delete from nucleo.membresia_roles where membresia_id = v_membresia;
  if p_rol is not null then
    insert into nucleo.membresia_roles (organizacion_id, membresia_id, rol_id, sede_id)
    select v_org, v_membresia, r.id, p_sede
    from nucleo.roles r where r.organizacion_id = v_org and r.nombre = p_rol;
    if not found then
      raise exception 'pruebas.rol_de: rol % inexistente', p_rol;
    end if;
  end if;
end;
$$;

/** Crea el escenario estándar (ver arriba). Corre como postgres: la organización se crea
 *  por la RPC con el JWT de la titular, sin cambiar de rol. */
create function pruebas.escenario()
returns void
language plpgsql
as $$
declare
  v_org uuid;
begin
  perform pruebas.usuario('e0000000-0000-4000-8000-000000000001', 'titular@eskemia.test', 'Titular');
  perform pruebas.usuario('e0000000-0000-4000-8000-000000000002', 'operario@eskemia.test', 'Operario');
  perform pruebas.usuario('e0000000-0000-4000-8000-000000000003', 'persona@eskemia.test', 'Persona');
  perform set_config('request.jwt.claims',
    '{"sub": "e0000000-0000-4000-8000-000000000001", "role": "authenticated"}', true);
  v_org := (api.crear_organizacion('Pruebas') ->> 'id')::uuid;
  perform set_config('request.jwt.claims', '', true);

  insert into esc values ('org', v_org);
  insert into esc select 'sede', s.id from nucleo.sedes s where s.organizacion_id = v_org;
  insert into nucleo.sedes (organizacion_id, nombre, codigo) values (v_org, 'Sede 2', 'S2');
  insert into esc select 'sede2', s.id from nucleo.sedes s where s.organizacion_id = v_org and s.nombre = 'Sede 2';
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000002', 'Operario de recepción', pruebas.id('sede'));
  perform pruebas.rol_de('e0000000-0000-4000-8000-000000000003', null);
end;
$$;

-- Chequeos registrados desde bloques DO (actuando como cualquier cuenta) ------------
-- Al final del test, como postgres: select ok(ok, nombre) from chequeos order by n;
create temp table chequeos (n serial primary key, nombre text not null, ok boolean not null);
grant select, insert on chequeos to authenticated;
grant usage on sequence chequeos_n_seq to authenticated;

/** Registra un chequeo que pasa si p_falla NO se cumple (null cuenta como no cumplida).
 *  Uso: perform pruebas.no('1: el operario no valida', <condición de falla>); */
create function pruebas.no(p_nombre text, p_falla boolean)
returns void
language sql
as $$ insert into chequeos (nombre, ok) values (p_nombre, not coalesce(p_falla, false)) $$;
grant execute on function pruebas.no(text, boolean) to authenticated;

/** Registra un chequeo que pasa si p_sql falla con un mensaje que empieza con p_prefijo
 *  (SIN_PERMISO, PRECONDICION, NO_ENCONTRADO, MODULO_DESHABILITADO…). Corre como quien llama. */
create function pruebas.falla(p_nombre text, p_prefijo text, p_sql text)
returns void
language plpgsql
as $$
declare
  v_resultado text := pruebas.ejecutar(p_sql);
begin
  insert into chequeos (nombre, ok) values (p_nombre, v_resultado like 'ERROR: ' || p_prefijo || '%');
  if v_resultado not like 'ERROR: ' || p_prefijo || '%' then
    raise notice '%: se esperaba % y dio %', p_nombre, p_prefijo, v_resultado;
  end if;
end;
$$;
grant execute on function pruebas.falla(text, text, text) to authenticated;
