-- Eskemia · Línea base v1 · 12: tablas de Salas de reuniones (colab).
--
-- Qué hace: salas (públicas dentro de la organización o privadas con miembros y
-- contraseña opcional hasheada), sus miembros, lo leído por cada persona y los mensajes.
-- Dónde encaja: solo tablas y RLS; las RPC, permisos y Realtime llegan en la Etapa 10.
-- Sin RPC todavía nadie escribe acá.

create table colab.salas (
  id               uuid primary key default gen_random_uuid(),
  organizacion_id  uuid not null references nucleo.organizaciones (id),
  nombre           text not null check (btrim(nombre) <> ''),
  descripcion      text,
  privada          boolean not null default false,
  contrasena_hash  text,  -- crypt() de pgcrypto; nunca la contraseña
  enlace_llamada   text check (enlace_llamada ~ '^https://'),
  creada_por       uuid not null references nucleo.cuentas (id),
  archivada        boolean not null default false,
  creada_en        timestamptz not null default now(),
  check (contrasena_hash is null or privada),
  unique (organizacion_id, id)
);

create table colab.sala_miembros (
  organizacion_id uuid not null,
  sala_id         uuid not null,
  cuenta_id       uuid not null references nucleo.cuentas (id),
  agregado_en     timestamptz not null default now(),
  primary key (sala_id, cuenta_id),
  foreign key (organizacion_id, sala_id) references colab.salas (organizacion_id, id)
);

-- Hasta dónde leyó cada persona: base del indicador de no leídos.
create table colab.sala_lecturas (
  organizacion_id uuid not null,
  sala_id         uuid not null,
  cuenta_id       uuid not null references nucleo.cuentas (id),
  leido_hasta     timestamptz not null default now(),
  primary key (sala_id, cuenta_id),
  foreign key (organizacion_id, sala_id) references colab.salas (organizacion_id, id)
);

create table colab.mensajes (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  sala_id         uuid not null,
  cuenta_id       uuid not null references nucleo.cuentas (id),
  texto           text check (char_length(texto) between 1 and 4000),
  adjunto_path    text,
  creado_en       timestamptz not null default now(),
  editado_en      timestamptz,
  borrado_en      timestamptz,
  check (texto is not null or adjunto_path is not null),
  foreign key (organizacion_id, sala_id) references colab.salas (organizacion_id, id)
);
create index mensajes_sala_idx on colab.mensajes (sala_id, creado_en desc);

/** true si la cuenta actual puede ver la sala: miembro activo de la organización y, si
 *  es privada, miembro de la sala o quien la creó. */
create function colab.puede_ver_sala(p_sala_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from colab.salas s
    where s.id = p_sala_id
      and nucleo.es_miembro(s.organizacion_id)
      and (
        not s.privada
        or s.creada_por = (select auth.uid())
        or exists (
          select 1 from colab.sala_miembros sm
          where sm.sala_id = s.id and sm.cuenta_id = (select auth.uid())
        )
      )
  );
$$;

do $$
declare
  v_tabla text;
begin
  foreach v_tabla in array array['salas', 'sala_miembros', 'sala_lecturas', 'mensajes'] loop
    execute format('alter table colab.%I enable row level security', v_tabla);
    execute format('alter table colab.%I force row level security', v_tabla);
    execute format('revoke all on colab.%I from public, anon, authenticated', v_tabla);
    execute format('grant select on colab.%I to authenticated', v_tabla);
  end loop;
end;
$$;

create policy salas_select on colab.salas for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and colab.puede_ver_sala(id));

create policy sala_miembros_select on colab.sala_miembros for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and colab.puede_ver_sala(sala_id));

create policy sala_lecturas_select on colab.sala_lecturas for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and cuenta_id = (select auth.uid()));

create policy mensajes_select on colab.mensajes for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and colab.puede_ver_sala(sala_id));
