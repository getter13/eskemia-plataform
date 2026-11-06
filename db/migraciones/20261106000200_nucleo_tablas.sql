-- Eskemia · Línea base v1 · 02: tablas del núcleo.
--
-- Qué hace: crea las 16 tablas de nucleo (las 14 del plan + sectores + inicio_tarjetas).
-- Dónde encaja: sección "Modelo de datos del núcleo" de docs/planes/plan-ejecucion-esqueleto.md.
-- Toda tabla con datos de una organización lleva organizacion_id NOT NULL y, en 04, RLS
-- forzado. Las FK compuestas (organizacion_id, x_id) impiden mezclar datos de dos
-- organizaciones aunque un id se filtre.
-- Sin organizacion_id (listadas en el test de RLS): cuentas (identidad global),
-- organizaciones (su id ES la organización), permisos y modulos (catálogos globales).

-- Identidad global de una persona. La crea un trigger al registrarse (ver 03).
create table nucleo.cuentas (
  id             uuid primary key references auth.users (id) on delete cascade,
  nombre         text,
  apellido       text,
  alias          text unique check (alias ~ '^[a-z0-9_.]{3,30}$'),
  alias_visible  boolean not null default false,
  avatar_path    text,
  idioma         text not null default 'es-AR',
  zona_horaria   text not null default 'America/Argentina/Buenos_Aires',
  creada_en      timestamptz not null default now()
);

create table nucleo.organizaciones (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 60),
  nombre      text not null check (btrim(nombre) <> ''),
  descripcion text,
  rubro       text,
  logo_path   text,
  titular_id  uuid not null references nucleo.cuentas (id),
  modo        text not null default 'COMPARTIDO' check (modo in ('COMPARTIDO', 'DEDICADO', 'LOCAL')),
  creada_en   timestamptz not null default now()
);

-- Datos fiscales y de contacto. Todo opcional: se pide cuando un módulo lo necesita.
create table nucleo.perfil_organizacion (
  organizacion_id uuid primary key references nucleo.organizaciones (id),
  razon_social    text,
  cuit            text check (cuit ~ '^[0-9]{11}$'),
  domicilio       text,
  telefono        text,
  email           text,
  sitio_web       text,
  campos          jsonb not null default '{}'::jsonb,
  actualizado_en  timestamptz not null default now()
);

-- codigo: prefijo de la numeración de OC (OC-<codigo>-2026-000001).
create table nucleo.sedes (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  nombre          text not null check (btrim(nombre) <> ''),
  codigo          text check (codigo ~ '^[A-Z0-9]{2,8}$'),
  direccion       text,
  activa          boolean not null default true,
  creada_en       timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, codigo)
);

create table nucleo.sectores (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  nombre          text not null check (btrim(nombre) <> ''),
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, nombre)
);

-- organizacion_id nulo = catálogo global (semilla). rol_sugerido es el NOMBRE de un rol
-- semilla: los roles son por organización y un puesto global no puede apuntar a un id.
create table nucleo.puestos (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid references nucleo.organizaciones (id),
  nombre          text not null check (btrim(nombre) <> ''),
  rol_sugerido    text,
  orden           int not null default 0,
  activo          boolean not null default true,
  unique nulls not distinct (organizacion_id, nombre)
);

create table nucleo.membresias (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  cuenta_id       uuid not null references nucleo.cuentas (id),
  puesto_id       uuid references nucleo.puestos (id),
  estado          text not null default 'ACTIVA' check (estado in ('INVITADA', 'ACTIVA', 'SUSPENDIDA')),
  invitada_por    uuid references nucleo.cuentas (id),
  unida_en        timestamptz,
  creada_en       timestamptz not null default now(),
  unique (organizacion_id, cuenta_id),
  unique (organizacion_id, id)
);
-- es_miembro() corre en cada política: este índice la resuelve sin recorrer la tabla.
create index membresias_activas_idx on nucleo.membresias (cuenta_id, organizacion_id)
  where estado = 'ACTIVA';

create table nucleo.permisos (
  codigo      text primary key check (codigo ~ '^[a-z_]+(\.[a-z_]+)+$'),
  modulo      text not null,
  descripcion text not null
);

create table nucleo.roles (
  id                          uuid primary key default gen_random_uuid(),
  organizacion_id             uuid not null references nucleo.organizaciones (id),
  nombre                      text not null check (btrim(nombre) <> ''),
  tipo                        text not null default 'INTERNO' check (tipo in ('INTERNO', 'EXTERNO')),
  nivel_aprobacion            int not null default 0 check (nivel_aprobacion >= 0),
  limite_monto_sin_aprobacion numeric(14, 2) check (limite_monto_sin_aprobacion >= 0),
  activo                      boolean not null default true,
  es_sistema                  boolean not null default false,
  creado_en                   timestamptz not null default now(),
  unique (organizacion_id, id),
  unique (organizacion_id, nombre)
);

create table nucleo.rol_permisos (
  organizacion_id uuid not null,
  rol_id          uuid not null,
  permiso_codigo  text not null references nucleo.permisos (codigo),
  primary key (rol_id, permiso_codigo),
  foreign key (organizacion_id, rol_id) references nucleo.roles (organizacion_id, id)
);

-- Un rol se asigna con alcance: sede nula = todas las sedes; sector acota el catálogo.
create table nucleo.membresia_roles (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null,
  membresia_id    uuid not null,
  rol_id          uuid not null,
  sede_id         uuid,
  sector_id       uuid,
  creado_en       timestamptz not null default now(),
  unique nulls not distinct (membresia_id, rol_id, sede_id, sector_id),
  foreign key (organizacion_id, membresia_id) references nucleo.membresias (organizacion_id, id),
  foreign key (organizacion_id, rol_id) references nucleo.roles (organizacion_id, id),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id),
  foreign key (organizacion_id, sector_id) references nucleo.sectores (organizacion_id, id)
);
create index membresia_roles_membresia_idx on nucleo.membresia_roles (membresia_id);
create index membresia_roles_rol_idx on nucleo.membresia_roles (rol_id);

-- El token viaja solo en el email; acá se guarda su hash (sha256, hex).
create table nucleo.invitaciones (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  email           text not null check (email = lower(btrim(email)) and email like '%_@_%'),
  puesto_id       uuid references nucleo.puestos (id),
  rol_id          uuid not null,
  sede_id         uuid,
  token_hash      text not null unique,
  vence_en        timestamptz not null,
  estado          text not null default 'PENDIENTE'
                  check (estado in ('PENDIENTE', 'ACEPTADA', 'REVOCADA', 'VENCIDA')),
  creada_por      uuid not null references nucleo.cuentas (id),
  creada_en       timestamptz not null default now(),
  aceptada_por    uuid references nucleo.cuentas (id),
  aceptada_en     timestamptz,
  foreign key (organizacion_id, rol_id) references nucleo.roles (organizacion_id, id),
  foreign key (organizacion_id, sede_id) references nucleo.sedes (organizacion_id, id)
);
-- Una sola invitación pendiente por email y organización.
create unique index invitaciones_pendiente_idx on nucleo.invitaciones (organizacion_id, email)
  where estado = 'PENDIENTE';

-- requiere: módulos que tienen que estar habilitados para habilitar este.
create table nucleo.modulos (
  codigo      text primary key check (codigo ~ '^[a-z_]+$'),
  nombre      text not null,
  descripcion text not null,
  requiere    text[] not null default '{}'
);

create table nucleo.modulos_habilitados (
  organizacion_id uuid not null references nucleo.organizaciones (id),
  modulo_codigo   text not null references nucleo.modulos (codigo),
  habilitado_en   timestamptz not null default now(),
  primary key (organizacion_id, modulo_codigo)
);

-- Append-only con hash encadenado por organización. secuencia, hash_prev, hash y
-- creado_en los asigna un trigger (ver 03).
create table nucleo.eventos (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references nucleo.organizaciones (id),
  sede_id         uuid,
  secuencia       bigint not null,
  entidad         text not null,
  entidad_id      uuid not null,
  accion          text not null,
  payload         jsonb not null default '{}'::jsonb,
  usuario_id      uuid,
  dispositivo_id  uuid,
  creado_en       timestamptz not null default clock_timestamp(),
  hash_prev       text,
  hash            text not null,
  unique (organizacion_id, secuencia)
);
create index eventos_entidad_idx on nucleo.eventos (entidad, entidad_id, creado_en);

-- Inicio personalizable: qué tarjetas ve cada persona en cada organización y en qué
-- orden. Las tarjetas las declara cada módulo en el front (modulos/registro.ts).
create table nucleo.inicio_tarjetas (
  organizacion_id uuid not null references nucleo.organizaciones (id),
  cuenta_id       uuid not null references nucleo.cuentas (id),
  tarjeta_codigo  text not null check (tarjeta_codigo ~ '^[a-z_]+\.[a-z_]+$'),
  orden           int not null check (orden >= 0),
  visible         boolean not null default true,
  primary key (organizacion_id, cuenta_id, tarjeta_codigo)
);
