# Eskemia · Módulo de Compras (MVP)

## Contexto del proyecto

Eskemia es una plataforma (ERP / CRM / POS / medio para agentes de IA) para estandarizar y automatizar procesos operativos y administrativos con trazabilidad en tiempo real. Se construye por módulos, llevando cada uno a prueba real lo más rápido posible.

Caso de referencia: operación gastronómica/distribuidora cuyo dueño necesita controlar la operación mientras no está y replicarla en cualquier sede.

Cadena de módulos: **Compras** (este MVP) → **Recepción** (MVP existente, ver su CLAUDE.md) → **Administración** (futuro, control OC ↔ recepción ↔ factura).

El plan completo está en `docs/plan-compras.md`. Ante dudas de diseño, ese documento manda.

## Alcance del MVP

1. Permisos parametrizables por código (roles configurables por empresa, niveles de aprobación, sectores).
2. Catálogo: rubros, productos, presentaciones, **múltiples códigos de barra por producto** (cada código asociado a una presentación y su factor), proveedores, relación producto ↔ proveedor con precio. Importación CSV.
3. Reglas de aprobación con prioridad **producto > rubro > empresa** (modos `NUNCA | SIEMPRE | POR_MONTO`, `nivel_requerido`) + límite por rol (`limite_monto_sin_aprobacion`).
4. Marketplace con carrito agrupado por proveedor y selector de presentación.
5. `confirmar_pedido`: split por proveedor → una OC por proveedor → `evaluar_aprobacion` por OC.
6. Bandeja de aprobación por nivel.
7. **Lista de pendientes en el perfil Recepción**, precarga de ítems desde la OC, escaneo código → presentación → factor, comparación pedida · remito · recibida, saldos.
8. Tablero de OC.

El marketplace es **interno**: solo usuarios de la empresa. En el MVP los proveedores no tienen acceso; reciben la OC por PDF/WhatsApp/mail. El **portal de proveedor** es una fase futura: desde la etapa 1 crear `roles.tipo` (`INTERNO` | `EXTERNO`) y `usuario_roles.proveedor_id` (null) para soportarlo sin migraciones disruptivas, pero no construir pantallas externas.

Escala: Eskemia es una plataforma de largo plazo con muchos módulos futuros. Diseñar cada tabla, permiso y RPC pensando en multiempresa, multisede y módulos que todavía no existen. Ante la duda entre un atajo y una estructura extensible de costo similar, elegir la extensible.

**Experiencia: mobile first.** El marketplace se usa principalmente desde el celular, en cualquier lugar, con la experiencia de Mercado Libre / PedidosYa: buscador fijo, "repetir último pedido", agregar con un toque (stepper inline), barra fija de carrito con total, carrito agrupado por proveedor, seguimiento de cada OC como un envío. Se diseña a 375 px primero; el escritorio es para catálogo, configuración, tablero y reportes. Los principios completos están en `docs/principios-ux.md` y aplican a todos los módulos.

**Prioridad del MVP:** que las OC aprobadas aparezcan como pendientes en el perfil Recepción (etapa 8). Todo lo demás se diseña en función de ese resultado.

Fuera del MVP: n8n, aprobación multinivel en cadena, pedido sugerido por stock.

## Reglas de diseño no negociables

- El código **nunca** consulta nombres de rol: siempre `tiene_permiso('codigo', sede_id)`.
- Transiciones de estado **solo** mediante funciones RPC de Postgres que validan precondiciones y permisos. Nunca updates directos desde el front.
- Toda RPC que cambia estado escribe en `eventos` (append-only, hash encadenado, ya existente).
- RLS en todas las tablas por `tenant_id`, `sede_id` y permiso.
- La OC guarda **snapshot** de precio, presentación, factor y reglas aplicadas.
- Saldos de OC siempre por vista (`v_oc_saldos`), nunca contadores mutables.
- `UNIQUE(tenant_id, codigo)` en `producto_codigos`.
- `confirmar_pedido` es idempotente por `request_uuid`. Numeración de OC con tabla `secuencias` y `SELECT ... FOR UPDATE`.
- La lógica de `evaluar_aprobacion` y `confirmar_pedido` lleva tests SQL (pgTAP o scripts de prueba en `supabase/tests/`).

## Estados

```
Pedido: BORRADOR → CONFIRMADO | DESCARTADO

OC:     PENDIENTE_APROBACION → APROBADA | RECHAZADA
        APROBADA → ENVIADA → RECIBIDA_PARCIAL → RECIBIDA → CERRADA
        APROBADA | ENVIADA → ANULADA
        RECIBIDA_PARCIAL → CERRADA (cierre de saldo)
```
Tipos de aprobación: `AUTOMATICA` (no requería), `AUTOAPROBADA` (el emisor tenía nivel suficiente y `permitir_autoaprobacion` = true), `MANUAL`.

Recepción ve: `APROBADA`, `ENVIADA`, `RECIBIDA_PARCIAL`. Con `recepcion.pendientes.ver_en_aprobacion` también `PENDIENTE_APROBACION` (solo lectura).

## Stack

- Front: React + Vite + TypeScript (misma PWA que Recepción), React Router, `@supabase/supabase-js`, **TanStack Query**, **Zustand** (persist), **Zod**, **Papa Parse**, **@react-pdf/renderer**, `lucide-react`, `vite-plugin-pwa`, **Dexie** (cola offline de confirmación), **Radix UI** (primitivas accesibles sin estilo), **Vaul** (bottom sheets), **TanStack Virtual** (listas largas).
- Back: Supabase (Postgres, Auth, Storage, Realtime, RLS). Migraciones en `supabase/migrations/`.
- Rutas: `/compras` (marketplace, carrito, mis pedidos), `/compras/aprobaciones`, `/compras/oc`, `/compras/catalogo`, `/admin/roles`; Recepción suma la sección Pendientes en su inicio.

## Etapas (un commit por etapa, resumen corto al final de cada una)

0. Verificación de base: revisar repo y migraciones de Recepción; proponer migración de `perfiles.rol` → `usuario_roles`. **Esperar confirmación antes de seguir.**
1. Permisos y roles (tablas, semillas, `tiene_permiso`, RLS, pantalla admin).
2. Catálogo (rubros, productos, presentaciones, códigos, proveedores, precios, ABM).
3. Importación CSV.
4. Reglas de aprobación + `evaluar_aprobacion` + tests.
5. Marketplace móvil y carrito (PWA instalable, diseño a 375 px primero, `ux-audit` al cerrar).
6. `confirmar_pedido`, OC, cola offline de confirmación, seguimiento por OC, PDF, envío manual.
7. Bandeja de aprobación.
8. Pendientes en Recepción + escaneo por presentación + saldos.
9. Tablero de OC.
10. Seed demo y guion de prueba de punta a punta.

## Identidad visual (manual de marca Eskemia — obligatorio)

```css
:root {
  --surface-100: #f6f5f1; --surface-200: #ebe9e2; --line: #d5d2c8;
  --ink: #15181d; --ink-muted: #5b6068;
  --brand: #0e5e5a; --brand-deep: #08403d; --brand-tint: #d3e7e3;
  --accent: #f0a81a; /* nunca como texto sobre claro */
  --signal-error: #b4372b;
  --font-display: "Space Grotesk", "IBM Plex Sans", system-ui, sans-serif;
  --font-sans: "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, Menlo, monospace;
  --space-2: 8px; --space-4: 16px; --space-6: 24px; --space-10: 40px;
  --radius-sm: 3px; --radius-md: 6px; --radius-lg: 12px;
}
```
- 70% neutros · 20% brand · 10% accent. Un CTA primario por vista.
- Tipografía: display 56 · h1 36 · h2 24 · body 16 · body-sm 14 · label 12 (mayúsculas, 0.06em) · data 13 mono (códigos, cantidades, números de OC, montos).
- Sentence case. Profundidad con bordes, sin sombras (salvo modales/menús). Íconos Lucide 1.5px. Sin logo: "Eskemia" en Space Grotesk 600.
- Contraste ≥ 4.5:1. Estados nunca solo por color (badge con texto o ícono).
- Objetivos táctiles ≥ 48px en móvil (≥ 56px en el kiosco de Recepción). Base 16px en inputs.
- El manual de marca define lo visual; `docs/principios-ux.md` define el comportamiento. Skills de UX: correr `/vectorlab-ux-skills:setup-ui-ux-skills` una vez; en cada etapa con UI aplicar las skills correspondientes y cerrar con `ux-audit`.

## Reglas de trabajo

- Interfaz en español (Argentina): `1.240,50`, `dd/mm/aaaa`, moneda `$ 1.240,50`.
- Secretos solo en `.env.local` (en `.gitignore`). Nunca commitear `service_role`/secret key. En el front solo la clave pública.
- Toda modificación de base en una migración nueva. Nunca editar migraciones aplicadas.
- Pedir confirmación antes de operaciones destructivas (borrar datos, `db reset` remoto, force push).
- Si falta un dato (rubros reales, reglas, credenciales), preguntar. No inventar. Usar datos demo solo en el seed y marcados como tales.
