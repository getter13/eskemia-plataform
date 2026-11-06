# ADR 0003 · Stack, lenguajes y capas de personalización

- **Fecha:** 04/11/2026
- **Estado:** aceptada
- **Complementa:** ADR 0002 (Supabase self-hosted como stack definitivo)
- **Contexto:** objetivo declarado del CEO: ser la plataforma más optimizada posible, con
  la menor cantidad de lenguajes y tecnologías, y la mínima dependencia de proveedores.

---

## Decisión 1 · Seguimos con Supabase, pero recortado

### Por qué no "armamos algo directamente con SQL"

La intuición es correcta en el objetivo y equivocada en el medio. **Menos tecnologías no es
lo mismo que menos código propio.** Si saco Supabase, los conceptos no desaparecen: siguen
hiendo falta autenticación, una API, almacenamiento de archivos y websockets. Lo único que
cambia es quién los escribe, los parcha y responde cuando fallan.

Lo que habría que reemplazar, y lo que cuesta:

| Servicio | Qué hace hoy por nosotros | Costo de reemplazarlo |
|---|---|---|
| **GoTrue (Auth)** | `auth.uid()` está en **todas** nuestras políticas RLS | Implementar hashing, JWT, rotación de refresh, MFA, rate limiting y recuperación de contraseña. **Es el peor lugar posible para código propio**: un bug acá es una brecha, no un error |
| **PostgREST** | Cada llamada del front y cada RPC | Escribir y mantener a mano todos los endpoints |
| **Storage** | Tabla `adjuntos`: fotos de remitos y firmas, con permisos en Postgres | Subida, permisos, servido y limpieza de archivos |
| **Realtime** | OC aprobada aparece al instante en Pendientes | Leer el WAL y multiplexar websockets |

Nuestras 19 migraciones están escritas contra ese contrato. Cambiarlo no es un ajuste: es
rehacer las políticas RLS, el modelo de adjuntos y toda la capa de datos del front.

### Lo que sí hacemos: recortar

Supabase documenta que si no se necesitan Logflare (Analytics), Realtime, Storage, imgproxy
o Edge Runtime, se pueden quitar de `docker-compose.yml` para reducir los requisitos de
recursos. Analytics y Vector ya salieron del compose por defecto en junio de 2026 y pasaron
a un overlay opt-in.

| Servicio | Decisión |
|---|---|
| PostgreSQL | **Queda.** Es el núcleo: datos y lógica |
| Auth (GoTrue) | **Queda.** Lo exige nuestro RLS |
| PostgREST | **Queda.** Lo exige todo el front |
| Storage | **Queda.** Fotos de remitos y firmas |
| Realtime | **Queda.** Pendientes de Recepción y bandeja de aprobación |
| Supavisor (pooler) | **Queda.** Pool de conexiones, puerto 6543 |
| Gateway (Envoy) | **Queda.** Única puerta de entrada |
| postgres-meta + Studio | **Queda, solo en localhost.** Herramienta de operación |
| Edge Runtime (Deno) | **Se quita.** Nuestra lógica vive en RPC de Postgres, no en funciones |
| Logflare + Vector | **Se quitan.** Ya son opt-in. Usamos Prometheus y Grafana |
| imgproxy | **A evaluar.** No transformamos imágenes, pero hay que verificar si Storage declara dependencia antes de quitarlo |

**Resultado:** mismo código, cero reescritura, menos contenedores, menos RAM y menos
superficie de ataque. Esa es la optimización real disponible.

### Fijar versiones, no seguir master

Supabase publica releases `self-hosted/v*` y un flujo de actualización con `update.sh`. Se
clona una release fijada, nunca `master`. El `docker-compose.yml` cambia con roturas: en
agosto de 2026 el gateway pasó de Kong a Envoy.

---

## Decisión 2 · Ni Node ni Python como lenguaje de aplicación

### El dato que hay que ver primero

**Hoy no tenemos backend propio.** No hay un solo proceso de aplicación nuestro corriendo
en el servidor. La lógica de negocio vive en PL/pgSQL dentro de Postgres: `confirmar_pedido`,
`evaluar_aprobacion`, las transiciones de estado. Node aparece en dos lugares, y ninguno es
producción:

1. **Vite**, que corre solo al compilar. El resultado son archivos estáticos.
2. **Un script** (`db/legado/supabase-cloud/scripts/crear-usuarios-prueba.mjs`, del MVP; hoy lo reemplaza `db/scripts/demo.sh`), utilidad de desarrollo.

Entonces la pregunta "¿Node o Python?" todavía no tiene objeto: no hay dónde ponerlo.

### Decisión

**No se agrega ninguno de los dos ahora.** La lógica se mantiene en SQL/PL-pgSQL.

Por qué esto es lo óptimo y no una postergación:

- La lógica vive **al lado de los datos**: sin salto de red, transaccional por defecto, y
  las reglas no se pueden saltear desde ningún cliente.
- Agregar Python hoy serían **tres lenguajes** (TypeScript, SQL, Python) en contra del
  objetivo declarado. Agregar Node como backend serían dos runtimes para el mismo trabajo
  que ya hace Postgres.
- Lenguajes que escribimos hoy: **TypeScript y SQL**. Más CSS y configuración. Es
  prácticamente el piso para un producto de este alcance.

### Cuándo se reevalúa, y con qué criterio

| Disparador | Elección y por qué |
|---|---|
| Servidor delgado para el modelo de negocio 1 (ruteo de conexión por tenant) | **TypeScript.** Comparte tipos y validaciones Zod con el front: un lenguaje, no dos |
| Puente de hardware, Fase 2 (balanza serie/USB) | Decisión abierta. Corre en la tablet o en una PC del depósito, aislado del núcleo, así que no contamina el stack del servidor |
| Ciencia de datos, ML o la capa de agentes de IA | **Python**, que es donde está el ecosistema. Solo si el requerimiento es real, no anticipado |

El script `.mjs` se pasa a SQL o se marca explícitamente como utilidad de desarrollo.

---

## Decisión 3 · Personalización: el mecanismo ahora, el producto después

La pregunta era si es momento de crear las capas de personalización en HTML y CSS.
Respuesta dividida, porque son dos cosas con costos muy distintos.

### Ahora sí: la disciplina de tokens (costo casi nulo, carísimo de retrofitear)

Ya existe `app/src/styles/tokens.css`. Lo que falta es la **regla** y el control
automático:

1. **Ningún componente lleva un color, espaciado o tipografía escrito a mano.** Todo sale
   de un token.
2. **Lint en CI que falle** si aparece un hex crudo, un `px` fuera de la escala o una
   familia tipográfica fuera de `tokens.css`.
3. `app.css` tiene 24 KB en un solo archivo. Se parte por módulo junto con la
   reorganización del front (P1 #7).

Con eso cumplido, la personalización por cliente después es inyectar un bloque `:root` con
los valores de ese tenant leídos de la base. Veinte líneas. Sin la disciplina, es cazar
colores sueltos en cuarenta archivos.

### Ahora no: el producto de theming

Sin cliente que lo haya pedido, construir pantalla de administración de marca, editor de
temas o presets es trabajo que todavía no sabemos si acertamos. Se construye cuando exista
el segundo cliente.

### Y lo más importante: la personalización que pesa no es visual

Lo que tiene consecuencias de arquitectura es la **personalización funcional**:
`modulos_habilitados`, campos `jsonb` por tenant, reglas de aprobación, sectores,
categorías. Esa es la que hay que diseñar bien y está en P1 #10. La marca es la mitad
fácil; confundir una con otra sería el error.

---

## Dependencias externas después de estas decisiones

| Proveedor | Para qué | Reemplazable |
|---|---|---|
| VPS | Servidor de producción | Sí, es un Linux estándar |
| Registrador y DNS | Dominio propio | Sí |
| Let's Encrypt | Certificados TLS | Sí (es un estándar ACME) |
| Almacenamiento de objetos | Copia de backup fuera del servidor | Sí, o un equipo propio |
| Alojamiento de git | Código fuente | Sí, con espejo en nuestro servidor |
| Registros npm y de imágenes | Compilación y actualizaciones | Sí, cacheable |
| ~~Supabase cloud~~ | — | **Eliminado** |
| ~~Vercel~~ | — | **Eliminado**: la PWA se sirve desde nuestro Caddy |
| SMTP | Correos de Auth | **Evitable**: con registro cerrado y reseteo por admin, no hace falta |

Quedan seis dependencias, todas estándar y todas sustituibles sin tocar código.
