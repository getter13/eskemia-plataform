> **HISTÓRICO.** Auditoría del MVP (Vercel + Supabase cloud). Sus hallazgos se resuelven en el plan del esqueleto y en docs/runbook-infra.md; no describe el sistema actual.

# Eskemia · Auditoría técnica y plan de alineación

> Fecha: 04/11/2026 · Revisión del repo real (`C:\Users\CHUWAKA\Eskemia plataform`).
> Alcance de la revisión: `CLAUDE.md`, configuración (`package.json`, `tsconfig.json`,
> `vite.config.ts`, `vercel.json`, `.gitignore`, `supabase/config.toml`), 8 de 19 migraciones
> y 11 archivos del front. **No** se revisaron el resto de las páginas ni la configuración
> remota de Supabase, Vercel o el historial de git: lo que depende de eso queda marcado
> como *a verificar*.
>
> Este documento es la línea de base para la próxima sesión de código. Las acciones P0
> se ejecutan antes de construir módulos nuevos.

## 1. Estado actual

### 1.1 Lenguajes y arquitectura

| Capa | Tecnología |
|---|---|
| Lenguajes | TypeScript estricto (0 usos de `any` en `src`), SQL / PL-pgSQL |
| Front | React 19, Vite, React Router, PWA (`vite-plugin-pwa`), Dexie (IndexedDB), Zustand, Zod, TanStack Virtual, Vaul, ZXing, `@react-pdf/renderer` |
| Back | Supabase: Postgres, Auth, Storage, Realtime, RLS |
| Hosting | Vercel (front), Supabase cloud (datos) |
| Patrón | SPA/PWA que habla directo con Postgres vía PostgREST y RPC. Sin servidor propio |

### 1.2 Esqueleto del proyecto

```
Eskemia plataform/
├─ CLAUDE.md, .ux-profile.md           contexto y reglas para Claude Code
├─ docs/                               planes, principios UX, guion de prueba, esta auditoría
├─ .claude/skills/                     skills de UX (VectorLab)
├─ supabase/                           CAPA 1 · DATOS Y REGLAS DE NEGOCIO
│  ├─ migrations/ (19)                 esquema, RLS, RPC, vistas, storage
│  ├─ tests/ (10)                      tests SQL (terminan en ROLLBACK)
│  └─ seed*.sql, scripts/              datos demo, separados del esquema
└─ app/                                CAPA 2 · CLIENTE (PWA)
   ├─ vercel.json, vite.config.ts      despliegue y PWA
   └─ src/ (45 archivos TS/TSX)
      ├─ main.tsx, App.tsx             arranque y rutas
      ├─ lib/ (18)                     acceso a datos + lógica + offline (MEZCLADOS)
      │   ├─ supabase.ts               cliente único
      │   ├─ db.ts, sync.ts            Dexie y cola offline
      │   ├─ sesion.tsx, roles.ts      sesión y permisos (solo para mostrar u ocultar)
      │   └─ operaciones, ordenes, catalogo, reglas, importacion, carrito…
      ├─ componentes/ (9)              UI reutilizable
      ├─ paginas/ (16)                 recepción, admin/, compras/
      └─ styles/                       tokens.css, app.css
```

Capas reales: **4** — Postgres (reglas y seguridad), cliente de datos (`lib/`), UI, y
offline/PWA. **No existe** capa de dominio ni servidor propio.

### 1.3 Lo que está bien

- Tablas de solo lectura desde la API; toda escritura pasa por RPC con validación de
  permisos y de estado.
- `SECURITY DEFINER` con `set search_path = ''` y `revoke` explícito por tabla.
- RLS por `tenant_id` y `sede_id`; permisos por código (`tiene_permiso`), nunca por
  nombre de rol.
- `eventos` append-only con hash encadenado.
- Sincronización offline idempotente por `client_uuid`.
- 19 migraciones versionadas y 10 tests SQL.
- TypeScript `strict`, secretos en `.gitignore`, sin `service_role` en el front.

### 1.4 Lo que está mal o falta

| # | Problema | Impacto |
|---|---|---|
| 1 | Un solo entorno: los tests corren con `--remote` contra la base productiva | Alto |
| 2 | Sin CI, ESLint/Prettier, tests de front, escaneo de secretos ni `npm audit` | Alto |
| 3 | `vercel.json` sin headers de seguridad (CSP, HSTS, etc.) | Alto |
| 4 | Auth laxa en `config.toml` local: password mínima 6, sin requisitos, sin confirmación de email, registro abierto, sin MFA (*a verificar en remoto*) | Alto |
| 5 | Backups sin procedimiento documentado ni restore probado (*a verificar*) | Alto |
| 6 | Comentarios insuficientes: 1–3 % en TS (`Carga.tsx` 8/639, `operaciones.ts` 11/481, `sync.ts` 12/411, `supabase.ts` 0) | Medio |
| 7 | Front sin capas: archivos de 400–640 líneas mezclan UI, negocio y datos | Medio |
| 8 | Capas de personalización no formalizadas | Medio |
| 9 | Acoplamiento a Supabase (`auth.uid()` en RLS, Storage, URL fijada al compilar) | Medio |
| 10 | IndexedDB sin cifrar en las tablets | Bajo |
| 11 | `perfiles.rol` como deuda técnica | Bajo |

## 2. Decisiones de arquitectura

### 2.1 Postgres y Supabase se mantienen

No se reescribe. Supabase se trata como **proveedor**, no como dependencia. El esquema se
diseña para **base por cliente** en los dos modelos de negocio.

### 2.2 Tres capas de personalización (a formalizar)

1. **Núcleo inmutable** — código y esquema idénticos para todos los clientes.
2. **Configuración por tenant (datos)** — permisos, roles, reglas de aprobación,
   categorías, branding (tokens), `modulos_habilitados`, campos personalizados `jsonb`.
3. **Extensiones** — webhooks, n8n, agentes de IA, portal de proveedor. Siempre por
   interfaz pública; nunca tocan el núcleo.

### 2.3 Independencia de proveedor: por capas, no por mudanza

El desacople real no se logra cambiando de hosting de base, sino **concentrando todo el
acceso a datos en una única capa `api/`**. Cuando el modelo 1 (datos en la base del
cliente) se acerque, se agrega un servidor propio delgado (Fastify o NestJS) entre el
navegador y la base, con un catálogo central que resuelva la conexión de cada tenant.
Hacerlo hoy sería sobreingeniería; lo que se hace hoy es **no cerrar esa puerta**.

**No** se adopta "Supabase en desarrollo y servidor propio en producción": rompe la
paridad de entornos y los bugs aparecerían solo en producción. El camino es
`dev → staging → prod` sobre el mismo stack, y la independencia llega por la capa `api/`
y por self-hosting del mismo stack cuando corresponda. Ver `docs/adr/0001-independencia-proveedor.md`.

## 3. Plan de ejecución

### P0 — Antes de construir módulos nuevos

| # | Acción | Bloqueante |
|---|---|---|
| 1 | Entorno de **staging** (segundo proyecto Supabase o Docker local). Tests salen de producción. Producción recibe solo migraciones aprobadas | Nico crea el proyecto |
| 2 | **CI** en GitHub Actions: `tsc`, build, tests SQL en Postgres efímero, `gitleaks`, `npm audit` | — |
| 3 | **Regla de comentarios** en `CLAUDE.md` + backfill: cabecera por archivo, JSDoc en funciones públicas, bloque "qué hace / precondiciones / eventos que escribe" en cada RPC | — |
| 4 | **Headers de seguridad** y CSP en `vercel.json` | — |
| 5 | **Endurecer auth**: registro cerrado, password mínima 12, MFA obligatorio para admin, rate limits revisados | Confirmar config remota |
| 6 | **Backups**: confirmar PITR, probar un restore, `pg_dump` periódico a almacenamiento propio | Confirmar plan Supabase |

### P1 — Próximas 2–3 semanas

| # | Acción |
|---|---|
| 7 | Reorganizar el front por módulo y partir los archivos grandes:<br>`src/nucleo/` (sesión, permisos, sync, ui base)<br>`src/modulos/{recepcion,compras,admin}/{paginas,componentes,api,dominio}` |
| 8 | Capa **`api/`** única sobre `supabase-js`, con Zod en los bordes. Ningún componente importa `supabase` directo |
| 9 | ESLint + Prettier, Vitest para lógica pura, Playwright E2E del flujo Compras → Recepción |
| 10 | `modulos_habilitados`, branding y campos `jsonb` por tenant + vista de **espacio por empresa** (base y archivos) para poder cobrarlo |

### P2 — Después

| # | Acción |
|---|---|
| 11 | ADRs en `docs/adr/` para cada decisión de arquitectura |
| 12 | Monorepo con paquetes `db`, `app`, `bridge` |
| 13 | Política de retención de `eventos` y adjuntos |
| 14 | Borrar `perfiles.rol` cuando todas las tablets estén actualizadas |
| 15 | Evaluar cifrado de IndexedDB en dispositivos compartidos |

## 4. Criterio de salida

La alineación se considera cumplida cuando:

- Ninguna prueba toca la base productiva.
- Un push abre CI que corre tipos, build, tests SQL y escaneo de secretos.
- Un restore de backup fue probado y documentado.
- Todo archivo nuevo o modificado lleva cabecera explicativa y las funciones públicas,
  JSDoc.
- Ningún componente importa `supabase` directo: todo pasa por `api/`.
- Ningún archivo de `src` supera ~300 líneas sin justificación escrita.
