# Eskemia · Plan de ejecución del esqueleto del núcleo

Nov 5, 2026 · @Nicolas

## Alcance

**Se construye el esqueleto funcional del núcleo: index con registro e ingreso, creación de la organización, y un shell con barra vertical a la izquierda que aloja perfil de empresa, usuarios, salas de reuniones y las herramientas Compras y Recepción.** Estimación: 34 a 48 días de trabajo efectivo (7 a 10 semanas), 12 etapas más un cierre, con un commit cada una.

**Entra:**

- Index público, registro con verificación de email, ingreso, recuperación de contraseña.
- Alta de la primera organización (nombre, descripción, puesto) y selector para cambiar entre organizaciones.
- Shell con navegación: arriba la organización y sus herramientas, abajo lo personal (perfil, cuenta, privacidad, cerrar sesión).
- Perfil de empresa con sedes; administración de usuarios con invitaciones por email.
- Salas de reuniones con chat de texto (sin voz).
- Compras y Recepción migrados al núcleo nuevo y montados como herramientas.

**Queda afuera (decidido):** precios, pasarelas de pago, suscripciones y límites por plan; voz; Eskemia Local; sitio de marketing completo.

**Cómo usarlo:** cada etapa trae un prompt listo para pegar en Claude Code. Se ejecutan en orden, una por sesión o varias seguidas, y ninguna arranca si la anterior no cumplió su entregable verificable.

## Decisiones fijadas para esta etapa

**Todo lo comercial se posterga, pero se deja el enchufe: los módulos se habilitan por organización desde el día uno.** Cuando definas planes, los planes solo deciden qué se habilita; no hay que tocar pantallas ni tablas de negocio.

| Tema | Decisión | Por qué |
| --- | --- | --- |
| Tenencia | Base compartida, `organizacion_id` + RLS en toda tabla | Plan maestro, aprobado como dirección |
| Pertenencia | Identidad global + `membresias`; una cuenta en varias organizaciones | Lo exige "vincular otra cuenta de Eskemia" |
| RLS | Función `nucleo.es_miembro(org)` sobre membresías activas, no claim en el JWT | Sin datos viejos en el token al cambiar de organización o al suspender a alguien. El claim queda como optimización futura |
| Organización en la URL | `/o/:org/...` (slug) | Enlaces compartibles, varias pestañas con distintas organizaciones, como GitHub o Slack |
| Módulos | Tabla `nucleo.modulos` + `modulos_habilitados` por organización | Enchufe para planes futuros sin definirlos |
| Planes, precios, cobro | **No se construyen** | Pedido del CEO |
| Esquemas | `nucleo`, `compras`, `recepcion`, `colab` privados; solo `api` expuesto (vistas `security_invoker` + RPC) | Momento más barato: no hay producción |
| Migraciones | Línea base v1 nueva; las 19 actuales pasan a `db/legado/` como referencia | Se renombran `tenant_id` → `organizacion_id` y `perfiles` → `membresias` sin arrastrar historia |
| Emails | Cola `pgmq` + servicio TypeScript mínimo; en desarrollo, Mailpit captura todos los correos | Invitaciones y verificación necesitan email desde ya |
| Barra de navegación | **Vertical a la izquierda en escritorio** (≥ 1024 px); colapsada a íconos en tablet; en celular, barra inferior + hoja con el menú completo | Una barra lateral no entra a 375 px; los Principios UX piden zona del pulgar |
| Voz | Fuera. Salas con chat de texto | Plan maestro, fase 5 |

## Mapa de pantallas y navegación

**Una persona nueva llega al panel de su organización en cuatro pasos; adentro, la barra izquierda pone arriba la organización y sus herramientas, y abajo lo personal.**

&#91;embedded content: recorrido de ingreso y shell con barra a la derecha\]

Las herramientas se generan desde el registro de módulos: si una organización no tiene Compras habilitado, no aparece. En tablet la barra queda colapsada a íconos.

## Modelo de datos del núcleo

**Catorce tablas en `nucleo` sostienen todo el esqueleto; Compras y Recepción solo cambian `tenant_id` por `organizacion_id` y sus permisos pasan a colgar de la membresía.**

```sql
-- Esquema nucleo (privado). Toda tabla con organizacion_id lleva RLS forzado.
cuentas            (id = auth.users.id, nombre, apellido, alias UNIQUE, avatar_path,
                    idioma default 'es-AR', zona_horaria default 'America/Argentina/Buenos_Aires',
                    alias_visible bool, creada_en)
organizaciones     (id, slug UNIQUE, nombre, descripcion, rubro, logo_path,
                    titular_id -> cuentas, modo default 'COMPARTIDO', creada_en)
perfil_organizacion(organizacion_id PK, razon_social, cuit, domicilio, telefono, email,
                    sitio_web, campos jsonb)     -- todo opcional: se pide cuando un módulo lo necesita
sedes              (id, organizacion_id, nombre, direccion, activa)
puestos            (id, organizacion_id NULL = catálogo global, nombre, rol_sugerido_id)
membresias         (id, organizacion_id, cuenta_id, puesto_id, estado INVITADA|ACTIVA|SUSPENDIDA,
                    invitada_por, unida_en)   UNIQUE(organizacion_id, cuenta_id)
invitaciones       (id, organizacion_id, email, puesto_id, rol_id, token_hash, vence_en,
                    estado PENDIENTE|ACEPTADA|REVOCADA|VENCIDA, creada_por)
permisos           (codigo PK, modulo, descripcion)              -- global, semilla
roles              (id, organizacion_id, nombre, tipo INTERNO|EXTERNO, nivel_aprobacion,
                    limite_monto_sin_aprobacion, es_sistema)
rol_permisos       (rol_id, permiso_codigo)
membresia_roles    (membresia_id, rol_id, sede_id NULL, sector_id NULL)
modulos            (codigo PK: compras | recepcion | colab, nombre, descripcion)  -- global
modulos_habilitados(organizacion_id, modulo_codigo, habilitado_en)
eventos            -- el existente, append-only con hash encadenado, + organizacion_id
```

**Funciones base (SECURITY DEFINER, `search_path = ''`)**

| Función | Qué hace |
| --- | --- |
| `nucleo.es_miembro(org)` | `true` si `auth.uid()` tiene membresía ACTIVA en `org`. Base de toda política RLS |
| `nucleo.tiene_permiso(org, codigo, sede)` | Reemplaza a la actual; resuelve por `membresia_roles` |
| `nucleo.modulo_habilitado(org, codigo)` | Lo usan las RPC y las vistas de cada módulo |
| `api.crear_organizacion(nombre, descripcion, puesto_id)` | Crea organización, slug, membresía titular, roles semilla y módulos habilitados; escribe evento |
| `api.invitar(org, email, puesto_id, rol_id)` | Crea invitación con token hasheado y encola el email |
| `api.aceptar_invitacion(token)` | Valida email de la cuenta, crea membresía y roles |
| `api.cambiar_estado_miembro`, `api.asignar_roles`, `api.transferir_titularidad` | Administración de usuarios, con permiso y evento |

**Reglas de aislamiento**

- Política tipo: `using ((select nucleo.es_miembro(organizacion_id)))`. El `select` envolvente hace que Postgres la evalúe una vez por consulta y no por fila.
- Índice en `membresias (cuenta_id, organizacion_id) where estado = 'ACTIVA'`.
- El titular no puede quedar suspendido ni sin rol administrador.
- Test de CI que falla si una tabla de `nucleo`, `compras`, `recepcion` o `colab` no tiene RLS forzado o no tiene `organizacion_id` (salvo catálogos globales listados explícitamente).

## Estructura del repositorio y del front

**Monorepo con pnpm workspaces; el front se ordena en `nucleo/` (lo que toda organización tiene) y `modulos/` (herramientas enchufables).**

```text
eskemia/
├─ apps/
│  ├─ web/src/
│  │  ├─ main.tsx, rutas.tsx            definición única de rutas y guardas
│  │  ├─ nucleo/
│  │  │  ├─ publico/                   Index, Registro, Ingreso, Recuperar, Verificar, Invitacion
│  │  │  ├─ bienvenida/                crear primera organización
│  │  │  ├─ shell/                     Layout, BarraLateral, BarraInferiorMovil, SelectorOrganizacion
│  │  │  ├─ empresa/                   perfil de empresa, sedes
│  │  │  ├─ usuarios/                  miembros, invitaciones, roles
│  │  │  ├─ cuenta/                    perfil personal, cuenta y seguridad, privacidad
│  │  │  └─ sesion/                    proveedor de sesión, organización activa, permisos
│  │  ├─ modulos/
│  │  │  ├─ registro.ts                catálogo de módulos: código, nombre, ícono, rutas, permiso de entrada
│  │  │  ├─ colab/                     salas de reuniones
│  │  │  ├─ compras/                   lo actual, reubicado
│  │  │  └─ recepcion/                 lo actual, reubicado
│  │  └─ ui/                           componentes base (Radix + Vaul + tokens)
│  └─ api/                            servicio TS mínimo: consume la cola de emails
├─ paquetes/
│  ├─ cliente-api/                    única puerta a Supabase (nadie más importa supabase-js)
│  ├─ contratos/                      esquemas Zod + tipos generados de la base
│  └─ tokens/                         tokens.css del manual de marca
├─ db/
│  ├─ migraciones/                    línea base v1
│  ├─ pruebas/                        pgTAP
│  ├─ semillas/                       permisos, puestos, módulos (prod) · demo (dev)
│  └─ legado/                         las 19 migraciones anteriores, solo lectura
├─ infra/compose/                     Supabase fijado + Mailpit (dev) + api
└─ docs/                              adr/, planes/, runbooks/
```

**Registro de módulos en el front.** La barra lateral no conoce a Compras ni a Recepción: recorre `modulos/registro.ts` y muestra los que están habilitados para la organización y para los que el usuario tiene el permiso de entrada. Un módulo nuevo = una entrada en el registro + su carpeta + su esquema SQL.

## Etapas de ejecución

**Doce etapas, un commit cada una; las tres primeras no muestran nada en pantalla pero son las que hacen que el resto escale.** Cada prompt asume que el `CLAUDE.md` de la sección final ya está en la raíz del repo.

### Etapa 0 · Entorno local idéntico a producción (2 a 4 días)

- Repo dentro de WSL2 (`~/eskemia`), Docker Desktop con backend WSL2.
- Compose oficial de Supabase en release fijada, recortado (sin Edge Runtime ni Logflare), secretos propios, `.env.example` documentado.
- Mailpit como SMTP de desarrollo; Auth configurado: registro abierto, confirmación de email, contraseña mínima 12.
- CI mínimo en GitHub Actions: `tsc`, build, `gitleaks`.

**Entregable:** `docker compose up -d` levanta todo; Studio en `localhost`; un email de prueba aparece en Mailpit; CI en verde.

```text
Etapa 0. Prepará el entorno local según docs/runbook-infra.md, Plan B, con estos cambios:
registro público ABIERTO con confirmación de email, contraseña mínima 12, y Mailpit como
SMTP de desarrollo. Cloná el compose oficial de Supabase en la última release self-hosted/v*
(verificá cuál es antes de clonar), fijá tags de imagen, quitá Edge Runtime y Logflare,
generá secretos con openssl y dejá .env.example comentado variable por variable. Creá el
workflow de CI con tsc, build y gitleaks. No toques el código de la app todavía.
Al terminar: listame los comandos para levantar y bajar el entorno y un resumen corto.
```

### Etapa 1 · Monorepo (1 a 2 días)

- pnpm workspaces; `app/` → `apps/web`; crear `apps/api`, `paquetes/{cliente-api,contratos,tokens}`, `db/`, `infra/`.
- Mover las 19 migraciones a `db/legado/` sin modificarlas.
- La app sigue compilando y funcionando igual (todavía contra el esquema viejo).

**Entregable:** `pnpm -r build` en verde; la app abre como antes.

```text
Etapa 1. Convertí el repo en monorepo con pnpm workspaces según la estructura del
CLAUDE.md. Mové app/ a apps/web conservando el historial de git (git mv). Creá los
paquetes vacíos con su package.json y un README de una línea cada uno. Mové las
migraciones actuales a db/legado/ sin editarlas. No cambies lógica. Verificá que
pnpm -r build pase y que la app abra igual que antes.
```

### Etapa 2 · Línea base de base de datos (5 a 7 días)

- Migraciones v1 por esquema: `nucleo`, `compras`, `recepcion`, `colab` (solo tablas de salas), `api`.
- Portar Compras y Recepción desde `db/legado/`: `tenant_id` → `organizacion_id`, `perfiles` → `membresias` + `membresia_roles`, mismas reglas y RPC.
- Funciones base, RLS con `es_miembro`, semillas de permisos, puestos y módulos.
- Tests pgTAP: aislamiento entre dos organizaciones por tabla, RPC del núcleo, y los 10 tests existentes portados.
- CI suma tests SQL contra Postgres efímero y el chequeo de RLS forzado.

**Entregable:** `db reset` local aplica todo desde cero; todos los tests en verde; un usuario de la organización A no ve nada de B.

```text
Etapa 2. Escribí la línea base v1 de la base según la sección "Modelo de datos del
núcleo" del plan. Esquemas privados nucleo, compras, recepcion, colab; solo api expuesto
a PostgREST (vistas security_invoker + RPC). Portá Compras y Recepción desde db/legado/
renombrando tenant_id a organizacion_id y perfiles a membresias/membresia_roles, sin
cambiar sus reglas. RLS forzado en toda tabla con organizacion_id usando
(select nucleo.es_miembro(organizacion_id)). Cada RPC: cabecera con qué hace,
precondiciones y eventos que escribe. Tests pgTAP de aislamiento A/B por tabla y un test
que falle si alguna tabla de esos esquemas no tiene RLS forzado. Antes de escribir,
mostrame la lista de tablas y RPC que vas a crear y esperá mi OK.
```

### Etapa 3 · Capa de datos del front (2 a 3 días)

- `paquetes/contratos`: tipos generados de la base + esquemas Zod de formularios.
- `paquetes/cliente-api`: cliente Supabase único y funciones por dominio (`auth`, `organizaciones`, `miembros`, `salas`, `compras`, `recepcion`).
- Regla de lint: prohibido importar `@supabase/supabase-js` fuera de `cliente-api`.
- TanStack Query como capa de caché en la web.

**Entregable:** el lint falla si un componente importa supabase directo; Compras y Recepción ya leen por `cliente-api`.

```text
Etapa 3. Creá paquetes/contratos (tipos generados con supabase gen types sobre el esquema
api + esquemas Zod) y paquetes/cliente-api (cliente único + funciones por dominio, cada
una con JSDoc). Agregá una regla de ESLint que prohíba importar @supabase/supabase-js fuera
de cliente-api. Migrá las llamadas existentes de Compras y Recepción a cliente-api.
```

### Etapa 4 · Index, registro e ingreso (3 a 4 días)

- `/` index: nombre Eskemia, propuesta de valor en una frase, dos acciones (Crear cuenta gratis · Ingresar). Mobile first, manual de marca.
- `/registro`: nombre, apellido, email, contraseña (indicador de fortaleza), aceptación de términos (texto provisorio). Validación al salir del campo.
- `/verificar`: pantalla "Revisá tu email" con reenvío; el enlace confirma y entra.
- `/ingresar`, `/recuperar`, `/restablecer`.
- Al crear la cuenta, un trigger crea la fila en `nucleo.cuentas`.
- Guardas: rutas públicas redirigen al panel si hay sesión; rutas privadas redirigen a `/ingresar` conservando el destino.

**Entregable:** alta completa con el email capturado en Mailpit; ingreso, cierre y recuperación funcionando a 375 px y 1280 px.

```text
Etapa 4. Construí las páginas públicas en apps/web/src/nucleo/publico: index, registro,
verificar, ingresar, recuperar y restablecer, con Supabase Auth vía cliente-api. Aplicá
el manual de marca y docs/principios-ux.md; usá las skills page-patterns, forms, labels,
errors y verbs, y cerrá con ux-audit. Textos en español rioplatense con voseo. Trigger
en la base que crea nucleo.cuentas al registrarse. Guardas de rutas públicas/privadas
conservando el destino.
```

### Etapa 5 · Bienvenida y organización (2 a 3 días)

- Si la cuenta no tiene membresías activas ni invitaciones pendientes → `/bienvenida`: nombre de la empresa, descripción, tu puesto (desplegable de `puestos`). Un solo paso, tres campos.
- `api.crear_organizacion` genera el slug y redirige a `/o/:org`.
- Si hay invitaciones pendientes, se ofrecen antes de crear una organización nueva.
- Selector de organización (arriba en la barra) + "Crear otra organización". Última organización usada guardada en `cuentas`.

**Entregable:** una cuenta nueva llega al panel de su organización en menos de un minuto; una cuenta con dos organizaciones cambia entre ellas sin volver a ingresar.

```text
Etapa 5. Implementá /bienvenida (crear organización con nombre, descripción y puesto)
usando api.crear_organizacion, la oferta de invitaciones pendientes y el selector de
organización con la organización en la URL (/o/:org). Guardá la última organización usada.
```

### Etapa 6 · Shell y navegación (3 a 4 días)

- Layout `/o/:org/*` con barra vertical **a la izquierda** en escritorio, fija, ancho 264 px, colapsable a 72 px (solo íconos con tooltip).
- **Zona superior:** selector de organización · Inicio · Perfil de empresa · Usuarios · Salas de reuniones · separador con rótulo "Herramientas" · Compras · Recepción.
- **Zona inferior:** avatar y nombre · Perfil personal · Cuenta · Privacidad · Cerrar sesión.
- Cada ítem se muestra solo si el usuario tiene el permiso de entrada; las herramientas, además, si el módulo está habilitado.
- Tablet (768 a 1023 px): barra colapsada por defecto. Celular: barra inferior con Inicio · Herramientas · Salas · Menú; Menú abre una hoja inferior con la lista completa.
- `/o/:org` (Inicio): accesos a las herramientas y estado vacío útil ("Completá el perfil de tu empresa", "Invitá a tu equipo").
- Posición de la barra en una variable de layout (`--nav-lado`), para invertirla sin tocar componentes.

**Entregable:** navegación completa con teclado, sin desplazamiento horizontal de 375 a 1280 px; un operario sin permisos de administración no ve Usuarios.

```text
Etapa 6. Construí el shell en nucleo/shell: barra vertical a la IZQUIERDA en escritorio
(fija, colapsable), barra inferior + hoja de menú en celular, colapsada en tablet. Zona
superior: selector de organización, Inicio, Perfil de empresa, Usuarios, Salas de
reuniones y el grupo Herramientas generado desde modulos/registro.ts. Zona inferior:
perfil personal, Cuenta, Privacidad, Cerrar sesión. Visibilidad por permiso y módulo
habilitado. Skills: page-patterns, viewports, icon-buttons, keyboard, surfaces;
cerrá con ux-audit. Las páginas de destino pueden ser placeholders con estado vacío.
```

### Etapa 7 · Perfil personal, cuenta y privacidad (2 a 3 días)

- **Perfil personal** (`/cuenta/perfil`): nombre, apellido, alias, foto (Storage), idioma, zona horaria.
- **Cuenta** (`/cuenta/seguridad`): cambio de email con reconfirmación, cambio de contraseña, MFA con app autenticadora (obligatorio si es titular o administrador), cerrar sesión en todos los dispositivos.
- **Privacidad** (`/cuenta/privacidad`): visibilidad del alias para otras organizaciones, lista de organizaciones a las que pertenece con opción de salir, solicitud de descarga de datos y de eliminación de cuenta (registran el pedido; la ejecución es manual en esta etapa).
- **Cerrar sesión:** limpia sesión, caché de TanStack Query y datos sensibles locales; conserva la cola offline pendiente de Recepción y avisa si quedan lecturas sin sincronizar.

**Entregable:** las tres páginas guardan y validan; un titular sin MFA ve el aviso para activarlo; cerrar sesión no pierde lecturas pendientes.

```text
Etapa 7. Implementá nucleo/cuenta: perfil personal, cuenta y seguridad (email,
contraseña, MFA TOTP de Supabase Auth, cerrar todas las sesiones) y privacidad (alias
visible, salir de una organización, pedidos de descarga y eliminación registrados en una
tabla). Cerrar sesión limpia caché y sesión pero respeta la cola offline de Recepción y
avisa si hay lecturas sin sincronizar. Confirmación nombrada para salir de una
organización y para pedir la eliminación.
```

### Etapa 8 · Perfil de empresa y sedes (2 días)

- Datos obligatorios ya cargados (nombre, descripción) y opcionales (razón social, CUIT con validación de dígito verificador, domicilio, contacto, rubro, logo).
- Indicador de completitud: "Te falta el CUIT para usar Compras con proveedores" (cada módulo declara qué campos necesita).
- ABM de sedes. Solo con `nucleo.organizacion.configurar`.

**Entregable:** editar el perfil y crear dos sedes deja eventos en `eventos`; un usuario sin permiso ve el perfil en modo lectura.

```text
Etapa 8. Implementá nucleo/empresa: perfil de empresa con campos opcionales progresivos,
validación de CUIT, logo en Storage (bucket por organización con política RLS) y ABM de
sedes. Escritura solo por RPC con permiso nucleo.organizacion.configurar y evento.
```

### Etapa 9 · Administración de usuarios e invitaciones (4 a 5 días)

- Lista de miembros (tarjetas en celular, tabla en escritorio): nombre, puesto, roles, sede, estado.
- Invitar por email: puesto + rol + sede. Invitación con token de un solo uso (guardado como hash), vence a los 7 días, reenviar y revocar.
- `/invitacion/:token`: si no tiene cuenta, registro con el email ya cargado; si tiene, ingresar y aceptar. Se valida que el email de la cuenta coincida.
- Cambiar puesto o roles, suspender, reactivar, transferir titularidad (confirmación nombrada).
- `apps/api` mínimo: consume la cola `emails` de `pgmq` y envía por SMTP (Mailpit en desarrollo). Reintentos y registro de envíos.
- Pantalla de roles: ver roles semilla y sus permisos (edición de roles queda para después).

**Entregable:** el titular invita, el invitado recibe el email en Mailpit, crea su cuenta, entra a la organización con el rol asignado y ve solo lo que ese rol permite.

```text
Etapa 9. Implementá nucleo/usuarios (miembros, invitaciones, cambio de puesto y roles,
suspender, transferir titularidad) y la ruta pública /invitacion/:token. Creá apps/api
con Node LTS + Hono + TypeScript estricto: un worker que lee la cola emails de pgmq y
envía por SMTP con plantillas simples en español, con reintentos e idempotencia por id de
mensaje. Sin endpoints públicos todavía salvo /salud. Sumalo al compose. Tests pgTAP de
invitar/aceptar y de que un suspendido pierde acceso al instante.
```

### Etapa 10 · Salas de reuniones (3 a 4 días)

- Lista de salas de la organización; crear sala (nombre, descripción, pública dentro de la organización o privada con miembros elegidos y contraseña opcional guardada como hash).
- Chat de texto en tiempo real: mensajes por RPC, difusión por Realtime, historial paginado, indicador de no leídos.
- Adjuntos a Storage (imágenes y PDF) con límite de tamaño.
- Campo "enlace de llamada" opcional por sala (para usar una videollamada externa mientras no exista voz propia).

**Entregable:** dos usuarios de la misma organización chatean en vivo; un tercero sin acceso a la sala privada no la ve ni lee sus mensajes (test pgTAP).

```text
Etapa 10. Implementá modulos/colab: salas (públicas en la organización o privadas con
miembros y contraseña opcional hasheada con pgcrypto), chat de texto con RPC de envío y
Realtime para difusión, historial paginado, no leídos, adjuntos en Storage y enlace de
llamada externa opcional. Sin voz. Registralo en modulos/registro.ts como módulo del
núcleo (siempre habilitado).
```

### Etapa 11 · Compras y Recepción como herramientas (3 a 4 días)

- Mover páginas y componentes a `modulos/compras` y `modulos/recepcion`; rutas bajo `/o/:org/compras/*` y `/o/:org/recepcion/*`.
- Entradas en `modulos/registro.ts` con su permiso de entrada; el kiosco de Recepción conserva su modo pantalla completa (sin barra) en tablet.
- La cola offline de Recepción se separa por organización.
- Correr el guion de prueba de punta a punta existente sobre el núcleo nuevo.

**Entregable:** el guion de Compras → Recepción pasa completo; deshabilitar Compras en una organización la quita de la barra y bloquea sus RPC.

```text
Etapa 11. Reubicá Compras y Recepción como módulos en apps/web/src/modulos, montados en el
shell vía modulos/registro.ts. Rutas bajo /o/:org. Kiosco de Recepción en pantalla
completa. Cola offline separada por organización. Verificá que modulo_habilitado bloquee
las RPC del módulo deshabilitado. Corré docs/guion-prueba-compras.md completo.
```

### Cierre · Semillas, pruebas de punta a punta y documentación (2 a 3 días)

- Semilla demo: dos organizaciones, cinco usuarios con roles distintos, una cuenta en ambas.
- Playwright: registro → bienvenida → invitar → aceptar → pedido → recepción → chat, a 375 px y 1280 px.
- `ux-audit` de todas las pantallas; ADR 0004 actualizado; `docs/` con una página por módulo.

```text
Cierre. Creá la semilla demo, el test E2E con Playwright del recorrido completo en 375 y
1280 px, corré ux-audit sobre todas las pantallas y actualizá docs/. Entregame la lista
de deuda técnica que quede abierta.
```

## Criterios de aceptación del esqueleto

El esqueleto está terminado cuando se cumplen los diez puntos; cualquiera pendiente bloquea pasar al piloto.

- [ ] Una persona se registra, verifica su email, crea su organización y llega al panel en menos de un minuto.
- [ ] Invita a otra persona, que crea su cuenta desde el email y entra con el rol asignado.
- [x] Una cuenta que pertenece a dos organizaciones cambia entre ellas sin volver a ingresar.
- [ ] Tests de aislamiento en verde: ningún usuario de A lee ni escribe datos de B, en ninguna tabla.
- [ ] Un miembro suspendido pierde el acceso en la siguiente consulta, sin esperar a que venza su token.
- [ ] La barra izquierda, colapsada y móvil funcionan sin desplazamiento horizontal de 375 a 1280 px y con teclado.
- [ ] Compras y Recepción pasan su guion de punta a punta montados como herramientas.
- [ ] Salas: chat en vivo entre dos usuarios; sala privada invisible para quien no es miembro.
- [ ] Ningún componente importa `supabase-js` directo; toda escritura pasa por RPC con evento.
- [ ] CI en verde: tipos, build, lint, tests SQL, chequeo de RLS forzado, `gitleaks` y E2E.

## CLAUDE.md del repositorio

Reemplaza al `CLAUDE.md` actual en la raíz. Los de Compras y Recepción pasan a `docs/planes/` como referencia de cada módulo.

```markdown
# Eskemia · Contexto para Claude Code (núcleo)

Eskemia es una plataforma multi-organización (ERP/CRM/POS + agentes de IA) para estandarizar
procesos operativos y administrativos con trazabilidad. Se despliega en tres modos con el
mismo código: Cloud compartido, Cloud dedicado y Local. Plan vigente:
docs/planes/plan-ejecucion-esqueleto.md. Ante dudas de diseño, ese documento manda.

## Vocabulario
- Cuenta: identidad global de una persona (auth.users + nucleo.cuentas).
- Organización: la unidad de negocio (antes "tenant"). Sede: ubicación dentro de ella.
- Membresía: vínculo cuenta ↔ organización, con puesto, roles y estado.
- Módulo / herramienta: Compras, Recepción, Salas. Se habilita por organización.

## Stack
- Lenguajes: TypeScript (estricto) y SQL/PL-pgSQL. No agregar otros.
- Base: Supabase self-hosted (compose en infra/compose, versiones fijadas).
- Web: React + Vite + TS, PWA, React Router, TanStack Query, Zustand, Zod, Radix, Vaul, Dexie.
- apps/api: Node LTS + Hono. Solo integraciones externas (hoy: envío de emails desde pgmq).
- Monorepo pnpm. CI en GitHub Actions.

## Reglas no negociables
- Toda tabla con datos de una organización: organizacion_id NOT NULL + RLS FORZADO con
  (select nucleo.es_miembro(organizacion_id)). Catálogos globales: listados en el test de RLS.
- Solo el esquema api se expone a PostgREST (vistas security_invoker + RPC).
- Toda escritura por RPC: valida permiso (nucleo.tiene_permiso), módulo habilitado y estado,
  y escribe en eventos. Nunca updates directos desde el front.
- El código consulta permisos por código ('compras.oc.aprobar'), nunca nombres de rol,
  y nunca pregunta por el modo de despliegue.
- Ningún archivo fuera de paquetes/cliente-api importa @supabase/supabase-js.
- Cada módulo nuevo: esquema SQL + entrada en modulos/registro.ts + permisos + tests + doc.
- Migraciones solo hacia adelante, una nueva por cambio. db/legado/ es solo lectura.
- Tests de aislamiento A/B para toda tabla nueva.

## Comentarios (obligatorio)
- Cabecera en cada archivo: qué hace y dónde encaja.
- JSDoc en toda función exportada.
- En cada RPC: qué hace, precondiciones, permisos que exige y eventos que escribe.
- Ningún archivo de src supera ~300 líneas sin justificación escrita.

## UI
- Manual de marca Eskemia (tokens en paquetes/tokens) y docs/principios-ux.md.
- Mobile first a 375 px. Barra de navegación vertical a la IZQUIERDA en escritorio
  (posición en --nav-lado), barra inferior + hoja en celular.
- Skills VectorLab en cada etapa con UI; cerrar con ux-audit.
- Español rioplatense con voseo; 1.240,50; dd/mm/aaaa; $ 1.240,50.

## Fuera de alcance en esta etapa
Precios, planes, pasarelas de pago, suscripciones, voz, Eskemia Local.

## Forma de trabajo
- Una etapa por commit, con resumen corto al cerrar.
- Antes de crear tablas o RPC nuevas, listarlas y esperar OK.
- Secretos solo en .env (fuera de git). Nunca service_role en el front.
- Pedir confirmación antes de operaciones destructivas.
- Si falta un dato, preguntar. No inventar.
```

## Lo que necesito antes de arrancar

Con los tres primeros puntos arranca la Etapa 0; el resto puede llegar en el camino.

- [x] **RAM de tu máquina** (el entorno local pide 16 GB): 32 GB, alcanza.
- [x] **OK para mover el repo a WSL2** (`~/eskemia`).
- [x] **OK a las decisiones de esta etapa:** base compartida con RLS, organización en la URL, línea base v1 de migraciones, barra a la izquierda con comportamiento móvil propio.
- [x] **Lista de puestos** para el desplegable de bienvenida (si no, cargo una semilla genérica marcada como provisoria): semilla genérica aprobada.
- [x] **Textos legales provisorios:** confirmar que en desarrollo usamos términos y privacidad de ejemplo, reemplazados antes de abrir al público.
- [ ] **Cuenta de GitHub** del repo, para el CI.

Al aprobar, Claude Code copia este plan a `docs/planes/plan-ejecucion-esqueleto.md` y empieza por el prompt de la Etapa 0.
