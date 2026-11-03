# Eskemia · Módulo de Recepción de Mercadería (MVP)

## Contexto del proyecto

Eskemia es una plataforma (ERP / CRM / POS / medio para agentes de IA) para estandarizar y automatizar procesos operativos y administrativos con trazabilidad en tiempo real. Se construye por módulos, llevando cada uno a prueba real lo más rápido posible para validar si vale la pena avanzar.

Caso de referencia: un empresario distribuidor que necesita controlar su operación mientras no está y replicarla en cualquier sede con procesos estandarizados.

Cadena de módulos (correlativos, conectados automáticamente):
1. **Compras** (futuro): genera órdenes de compra (OC).
2. **Recepción** (este MVP): controla todo lo que ingresa contra remito/OC antes de entrar a depósito y a sistema.
3. **Administración** (futuro): visualiza compra + recepción; último paso antes de aprobar la factura (control de tres vías OC ↔ recepción ↔ factura). Debe incluir la acción para marcar una recepción como `INGRESADA_A_SISTEMA` (la RPC `marcar_ingresada` ya existe).

## Alcance del MVP

Hardware: **tablet + escáner 2D** en modo teclado (HID, sufijo Enter). Sin balanza ni impresora (Fase 2).

### Front kiosco (estilo autoservicio de supermercado, uso táctil)
1. Inicio: botón grande "Nueva recepción" + recepciones abiertas del día.
2. Alta de recepción: buscar/crear proveedor (nombre, CUIT), nº de remito, **foto obligatoria del remito** (cámara de la tablet).
3. Pantalla de carga:
   - Input con foco permanente que captura lecturas del escáner (Enter = fin de lectura). Fallback: escaneo por cámara (ZXing).
   - Busca producto por GTIN/EAN. Si no existe: alta rápida marcada `pendiente_validacion`.
   - Cantidad con botones +/- grandes, en unidades o kg según el `tipo_medida` fijo de cada producto. Si el producto lo requiere: lote y vencimiento.
   - Los productos llevan solo su nombre, sin tamaño ni envase.
   - Carga manual (sin código): navegación táctil por categorías y productos, sin tipear códigos, **foto y motivo obligatorios**.
   - Feedback visual y sonoro en cada lectura (OK / error).
4. Resumen: cantidades leídas vs cantidades del remito (ingresadas por el operario). Diferencias (faltante / sobrante / rechazo) con motivo obligatorio.
5. Cierre: firma en pantalla (canvas) del receptor y del transportista → estado `CERRADA_OK` o `CERRADA_CON_DIFERENCIAS`.
6. Offline-first: toda lectura se guarda primero en IndexedDB y se sincroniza con cola cuando hay conexión. Indicador de estado de sincronización siempre visible.

### Back (ruta `/admin`, misma app, acceso por rol)
- Bandeja diaria de recepciones con semáforo: OK / con diferencias / control incompleto.
- Detalle: ítems, lecturas crudas, fotos, firmas, línea de tiempo de eventos.
- Validar / Rechazar (con observación). La validación queda **bloqueada** si falta: foto de remito, ítems, motivos de diferencias, firmas.
- Exportar CSV del día.
- Vista SQL `v_resumen_diario` preparada para que n8n envíe el reporte diario (la integración con n8n no es parte de este MVP).

### Estados de una recepción
```
ABIERTA → EN_CONTROL → CERRADA_OK | CERRADA_CON_DIFERENCIAS
        → VALIDADA → INGRESADA_A_SISTEMA
        → RECHAZADA (vuelve a operación con observación)
```
Las transiciones se hacen **solo** mediante funciones RPC de Postgres que validan las precondiciones. Nunca con updates directos desde el front.

## Stack

- **Front**: React + Vite + TypeScript, PWA (`vite-plugin-pwa`), React Router, Dexie (IndexedDB), `@supabase/supabase-js`, `lucide-react`, `@zxing/browser`.
- **Back**: Supabase (Postgres, Auth, Storage, RLS). Migraciones versionadas en `supabase/migrations/` (Supabase CLI vía `npx supabase`).
- **Hosting**: Vercel (más adelante).
- Estructura prevista: `/app` (PWA kiosco + admin), `/supabase` (migraciones, seeds), `/bridge` (puente de hardware, Fase 2, todavía no crear).

## Modelo de datos (todas las tablas con `tenant_id` y `sede_id`)

```
tenants, sedes, perfiles (user_id, rol: operario|supervisor|admin, sede_id), dispositivos
categorias (nombre, orden)
proveedores, productos (gtin, nombre, categoria_id, tipo_medida: UNIDAD|PESO, requiere_lote, requiere_vencimiento, pendiente_validacion)
ordenes_compra, oc_items                 -- vacías en el MVP, las alimentará el módulo Compras
recepciones (estado, proveedor_id, nro_remito, oc_id null, usuario_id, abierta_en, cerrada_en, validada_por, validada_en, observacion)
recepcion_items (producto_id, cant_remito, cant_recibida, diferencia, motivo_diferencia, lote, vencimiento)
lecturas (recepcion_id, tipo: ESCANEO|MANUAL|PESAJE, valor_crudo, producto_id, cantidad, dispositivo_id, leido_en, client_uuid)
adjuntos (recepcion_id, item_id null, tipo: REMITO|RECHAZO|MANUAL|FIRMA_RECEPTOR|FIRMA_TRANSPORTISTA, storage_path)
eventos (append-only: entidad, entidad_id, accion, payload jsonb, usuario_id, dispositivo_id, creado_en, hash_prev, hash)
```
- `eventos`: sin UPDATE ni DELETE (revocar permisos + trigger que lo impida). Hash encadenado con `pgcrypto` (sha256 de hash_prev + payload).
- RLS en todas las tablas por `tenant_id` y rol.
- `lecturas.client_uuid` único para que la sincronización offline sea idempotente.

## Identidad visual (manual de marca Eskemia — obligatorio)

```css
:root {
  --surface-100: #f6f5f1; /* fondo, nunca blanco puro */
  --surface-200: #ebe9e2; /* tarjetas y paneles */
  --line:        #d5d2c8; /* hairlines 1px */
  --ink:         #15181d; /* texto principal */
  --ink-muted:   #5b6068; /* texto secundario, bordes de inputs */
  --brand:       #0e5e5a; /* petróleo: CTA primario (uno por vista), activos */
  --brand-deep:  #08403d; /* hover/pressed, secciones oscuras */
  --brand-tint:  #d3e7e3; /* badges, selección */
  --accent:      #f0a81a; /* ámbar: destacados. NUNCA como texto sobre claro */
  --signal-error:#b4372b; /* errores, siempre con ícono o texto */
  --font-display: "Space Grotesk", "IBM Plex Sans", system-ui, sans-serif;
  --font-sans:    "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
  --font-mono:    "IBM Plex Mono", ui-monospace, Menlo, monospace;
  --space-2: 8px; --space-4: 16px; --space-6: 24px; --space-10: 40px;
  --radius-sm: 3px; --radius-md: 6px; --radius-lg: 12px;
}
```
- Proporción por pantalla: 70% neutros · 20% brand · 10% accent.
- Escala tipográfica: display 56 · h1 36 · h2 24 · body 16 · body-sm 14 · label 12 (mayúsculas, 0.06em) · data 13 (mono: SKUs, GTIN, cantidades, IDs).
- Titulares en sentence case. Profundidad con bordes `line`, no sombras (sombra solo en modales/menús).
- Íconos Lucide, trazo 1.5px. Sin logo: nombre "Eskemia" en Space Grotesk 600.
- Contraste de texto ≥ 4.5:1. Estados nunca solo por color.
- Kiosco: objetivos táctiles ≥ 56px, tipografía grande, una acción principal por pantalla.

## Reglas de trabajo

- Interfaz y textos en español (Argentina): formato numérico `1.240,50`, fechas `dd/mm/aaaa`.
- Secretos solo en `.env.local` (en `.gitignore`). Nunca commitear la `service_role` / `secret key`. En el front solo la clave pública (anon/publishable).
- Toda modificación de base de datos va en una migración nueva. Nunca editar migraciones ya aplicadas.
- Pedir confirmación antes de operaciones destructivas (borrar datos, `db reset` contra remoto, force push).
- Trabajar por etapas, con un commit por etapa y un resumen corto al final de cada una.
- Si falta un dato (credenciales, modelo de hardware, sistema operativo de la tablet), preguntar. No inventar.
