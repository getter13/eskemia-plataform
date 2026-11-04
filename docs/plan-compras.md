# Eskemia · Módulo de Compras — Plan de implementación (v3)

> v3: marketplace mobile first con experiencia tipo Mercado Libre / PedidosYa, PWA instalable y confirmación sin señal. Principios UX transversales en `docs/principios-ux.md`.
> v2: suma permisos parametrizables por rol/cargo/sector, aprobación configurable por rubro, producto y perfil, múltiples códigos de barra por producto con presentación asociada, y etapas de ejecución detalladas.

## 0. Objetivo y lugar en la cadena

Primer eslabón de la cadena **Compras → Recepción → Administración**.

- El perfil **Compras** arma un único pedido desde un marketplace de insumos configurados.
- Al confirmar, el sistema **separa el pedido por proveedor** y genera **una OC por proveedor**.
- Cada OC pasa (o no) por **aprobación**, según la parametrización de rubro, producto y privilegios del usuario.
- Las OC aprobadas aparecen en el perfil **Recepción** como **pendientes**. Al llegar el proveedor, logística selecciona la OC y recibe contra lo pedido.
- Administración (futuro) cruza OC ↔ recepción ↔ factura.

**El marketplace es interno:** lo usan solo los perfiles de la empresa (compras, aprobadores, recepción, administración). En el MVP los proveedores no acceden al sistema; solo reciben la OC (PDF/WhatsApp/mail). El **portal de proveedor** queda planificado para una fase futura (ver §10), y el modelo de datos se diseña desde ahora para soportarlo sin rehacer nada.

**Alcance inmediato (MVP):** que Recepción vea la lista de pendientes generada desde Compras, con la aprobación parametrizable funcionando.

## 1. Decisiones de arquitectura

| Decisión | Motivo |
|---|---|
| Misma base Supabase y misma app que Recepción (ruta `/compras`) | La conexión entre módulos es una clave foránea, no una integración. Un login, un despliegue. |
| **Permisos por código, no por rol fijo** | Los roles se configuran por empresa. El código consulta permisos (`compras.oc.aprobar`), nunca nombres de rol. Agregar un cargo nuevo no requiere programar. |
| **Aprobación evaluada por OC, después del split** | Si solo un proveedor tiene ítems que requieren aprobación, las demás OC salen inmediatamente. |
| **Reglas de aprobación con prioridad producto > categoría > rubro > empresa** | Permite "proteínas siempre se aprueban, salvo este corte" o "limpieza nunca". |
| **Código de barra → presentación → factor** | Cada producto admite N códigos; el escaneo determina la presentación y la cantidad por defecto. |
| Transiciones de estado solo por funciones RPC | Igual que Recepción. El front nunca cambia estados directamente. |
| Mismo log `eventos` (append-only, hash encadenado) | Trazabilidad única: pedido → OC → aprobación → recepción. |
| Saldos de OC por vista (`v_oc_saldos`) | Lo recibido se deriva de `recepcion_items`; una recepción rechazada deja de contar sola. |
| n8n solo para automatizaciones | No es fuente de verdad. |

## 2. Stack

| Capa | Herramienta | Uso |
|---|---|---|
| Base, Auth, API, Storage | Supabase (PostgreSQL) | Catálogo, OC, permisos, RLS por `tenant_id`/`sede_id`/permiso |
| Lógica | Funciones SQL/RPC → NestJS/Fastify al crecer | `confirmar_pedido`, `evaluar_aprobacion`, `aprobar_oc`, numeración |
| Tiempo real | Supabase Realtime | La OC aprobada aparece al instante en Pendientes de Recepción y en la bandeja del aprobador |
| Front | React + Vite + TypeScript (misma PWA) | Marketplace responsive; kiosco de Recepción sin cambios de base |
| Estado servidor | TanStack Query | Caché y refresco de catálogo, OC y bandejas |
| Carrito | Zustand con persistencia | No se pierde al cerrar la pestaña |
| Validación | Zod | Formularios e importación con los mismos esquemas |
| Importación | Papa Parse | Carga masiva de rubros, productos, códigos, proveedores y precios (CSV) |
| PDF de OC | @react-pdf/renderer (MVP) → Edge Function (Fase 3) | Comprobante para el proveedor |
| Envío al proveedor | MVP: `wa.me` y `mailto:` · Fase 3: n8n | Sin integraciones pagas |
| Analítica | Metabase | Cumplimiento de proveedores, tiempos de aprobación |
| PWA móvil | `vite-plugin-pwa` (Workbox) | Instalable en el celular, caché del catálogo, apertura sin señal |
| Cola offline de confirmación | Dexie (mismo que Recepción) | Confirmar pedido sin señal; se sincroniza al volver la conexión |
| Componentes accesibles | **Radix UI** (primitivas sin estilo) + **Vaul** (bottom sheets) | Foco, teclado y ARIA resueltos; estilos 100% del manual Eskemia |
| Listas largas | **TanStack Virtual** | Catálogo fluido en celulares de gama media |
| Notificaciones push (Fase 3) | Web Push + Edge Function | OC para aprobar, cambios de estado |

No se recomienda en el MVP: motor de búsqueda externo (alcanza `pg_trgm`), backend separado, ni librería de permisos de terceros (el modelo es simple y vive en Postgres, donde lo aplica RLS).

## 3. Permisos parametrizables

### 3.1 Modelo

```
permisos        catálogo fijo de códigos, definido por el sistema
roles           configurables por empresa (cargo): nombre, nivel_aprobacion, limite_monto_sin_aprobacion
rol_permisos    qué permisos tiene cada rol
sectores        cocina, barra, depósito, administración... configurables por empresa
usuario_roles   usuario + rol + sede + sector (un usuario puede tener más de un rol)
```

- `nivel_aprobacion` (entero): 0 = no aprueba; 1 = encargado; 2 = gerente; 3 = dirección. Los niveles son configurables.
- `limite_monto_sin_aprobacion`: monto máximo de OC que el rol puede emitir sin aprobación (null = sin límite propio).
- Función `tiene_permiso(codigo, sede_id)` usada en RLS y en cada RPC.
- Sector: en el MVP restringe qué rubros ve cada usuario en el marketplace (ej. barra solo ve bebidas). Opcional por empresa.
- Preparación para el portal de proveedor: `roles.tipo` (`INTERNO` | `EXTERNO`) y `usuario_roles.proveedor_id` (null) se crean desde la etapa 1, aunque en el MVP solo se usen roles internos.

### 3.2 Catálogo inicial de permisos

| Código | Descripción |
|---|---|
| `compras.catalogo.ver` | Ver marketplace |
| `compras.catalogo.gestionar` | Alta/edición de productos, códigos, proveedores, precios, importación |
| `compras.pedido.crear` | Armar y confirmar pedidos |
| `compras.oc.ver_todas` | Ver OC de otros usuarios (si no, solo las propias) |
| `compras.oc.aprobar` | Aprobar/rechazar OC (hasta su `nivel_aprobacion`) |
| `compras.oc.anular` | Anular OC sin recepciones |
| `compras.oc.cerrar_saldo` | Cerrar saldo pendiente |
| `compras.aprobacion.configurar` | Editar reglas de aprobación |
| `recepcion.pendientes.ver` | Ver lista de OC pendientes |
| `recepcion.pendientes.ver_en_aprobacion` | Ver también OC aún no aprobadas (informativo) |
| `recepcion.precios.ver` | Ver precios en OC |
| `recepcion.recepcion.operar` | Operar el kiosco |
| `recepcion.recepcion.validar` | Validar/rechazar recepciones |
| `recepcion.recepcion.marcar_ingresada` | Marcar una recepción validada como ingresada a sistema |
| `recepcion.eventos.ver` | Ver la línea de tiempo de eventos y los nombres de quienes actuaron |
| `admin.usuarios.gestionar` | Usuarios, roles y permisos |
| `admin.eventos.verificar` | Verificar la cadena de hash de `eventos` |

### 3.3 Roles semilla (editables por la empresa)

| Rol | Nivel aprob. | Permisos principales |
|---|---|---|
| Comprador | 0 | catálogo.ver, pedido.crear |
| Encargado de compras | 1 | + oc.ver_todas, oc.aprobar, oc.anular, catalogo.gestionar |
| Gerente | 2 | + oc.cerrar_saldo, aprobacion.configurar |
| Operario de recepción | 0 | pendientes.ver, recepcion.operar |
| Supervisor de recepción | 0 | + recepcion.validar, marcar_ingresada, eventos.ver, pendientes.ver_en_aprobacion |
| Administración | 0 | oc.ver_todas, precios.ver, recepcion.validar, marcar_ingresada, eventos.ver |
| Admin | 3 | todos |

## 4. Aprobación parametrizable

### 4.1 Reglas

Tabla `reglas_aprobacion`:

| Campo | Valores |
|---|---|
| `alcance` | `EMPRESA` · `RUBRO` · `CATEGORIA` · `PRODUCTO` (Fase 3: `PROVEEDOR`) |
| `alcance_id` | id del rubro, categoría o producto (null en EMPRESA) |
| `modo` | `NUNCA` · `SIEMPRE` · `POR_MONTO` |
| `monto_umbral` | para `POR_MONTO`: subtotal, dentro de la OC, de los ítems que resolvieron a esa regla |
| `nivel_requerido` | nivel mínimo del aprobador |
| `activa` | bool |

**Resolución por ítem:** regla de PRODUCTO si existe → si no, de su CATEGORÍA → si no, del RUBRO de esa categoría → si no, de EMPRESA (por defecto `NUNCA`).

### 4.2 Evaluación (`evaluar_aprobacion(oc_id)`)

1. Para cada ítem se resuelve la regla y se determina si requiere aprobación y con qué nivel.
2. `nivel_requerido_oc` = máximo nivel entre los ítems que requieren.
3. Se suma la regla de perfil: si `total_oc > limite_monto_sin_aprobacion` del rol del usuario, la OC requiere al menos nivel 1.
4. Resultado:
   - No requiere → OC `APROBADA`, tipo `AUTOMATICA`.
   - Requiere y el usuario tiene `compras.oc.aprobar` con nivel ≥ requerido → `APROBADA`, tipo `AUTOAPROBADA` (queda registrado quién y por qué).
   - Requiere y el usuario no alcanza → `PENDIENTE_APROBACION`, visible en la bandeja de aprobadores de nivel suficiente.
5. Se guardan en la OC los ítems que dispararon la aprobación y la regla aplicada (snapshot), para auditoría.

Parámetro por empresa `permitir_autoaprobacion` (default sí). Si es no, quien emite nunca puede aprobar su propia OC.

### 4.3 Bandeja de aprobación

- Lista de OC `PENDIENTE_APROBACION` filtrada por nivel del usuario.
- Detalle con ítems resaltados (los que dispararon la regla) y motivo.
- Acciones: **Aprobar**, **Rechazar** (motivo obligatorio), **Editar cantidades y aprobar** (Fase 3).
- MVP: aviso dentro de la app (tiempo real). Fase 3: aviso por WhatsApp/mail vía n8n.

Fase 4: aprobación multinivel en cadena (nivel 1 y luego nivel 2).

## 5. Productos, formatos y códigos de barra

```
productos          insumo base, unidad de stock (UN | KG | LT), rubro
presentaciones     formatos del producto: "Unidad", "Caja x 12", "Bolsa 25 kg"; factor respecto a la unidad de stock
producto_codigos   N códigos por producto: codigo, tipo (EAN13 | EAN8 | DUN14 | GS1_128 | UPC | INTERNO), presentacion_id
producto_proveedor producto + proveedor + presentación de compra por defecto + precio + código del proveedor
```

- **Al comprar:** el comprador elige la presentación (selector en la tarjeta del producto); por defecto la configurada para ese proveedor.
- **Al recibir:** el código escaneado identifica producto + presentación; la cantidad se suma con el factor (escanear una caja x 12 = 12 unidades contra la OC). El operario puede cambiar la presentación si hace falta.
- Un mismo código no puede repetirse dentro de una empresa (índice único `tenant_id + codigo`).
- Un código desconocido abre el alta rápida (`pendiente_validacion`) asociando el código a un producto existente o nuevo.

## 6. Flujo operativo

### 6.1 Compras — marketplace mobile first

El marketplace se diseña para **pedir desde el celular, en cualquier momento y lugar**, con la experiencia de Mercado Libre / PedidosYa. El escritorio queda para catálogo, configuración, tablero y reportes. Rige `docs/principios-ux.md`.

**Inicio (móvil)**
- Buscador fijo arriba, tolerante a errores de tipeo. Busca en el dispositivo sobre el catálogo guardado, para funcionar sin señal.
- Chips de rubros desplazables.
- Secciones: "Repetir último pedido" (un toque → carrito precargado), "Lo que más pedís", "Tus plantillas", favoritos.
- Barra inferior de navegación: Inicio · Buscar · Pedidos · Perfil.

**Tarjeta de producto**
- Nombre, presentación por defecto, proveedor, último precio, badge "Requiere aprobación" (texto + ícono).
- Botón "+" que se transforma en stepper "− 2 +" sin salir de la lista. Vibración corta al agregar.
- Toque en la tarjeta → bottom sheet para cambiar presentación o proveedor.
- Un producto puede tener varios proveedores. Si tiene más de uno activo, **quien arma el pedido elige a quién comprarle** antes de agregarlo; `preferido` solo lo muestra primero, no decide por la persona. Con un único proveedor, se agrega directo.

**Carrito**
- Barra fija inferior siempre visible: "3 proveedores · 14 ítems · $ 182.400 — Ver pedido".
- Vista agrupada por proveedor (como un pedido multitienda): subtotal, pedido mínimo con barra de progreso, entrega estimada y aviso "Esta orden va a aprobación".
- Se guarda solo en el dispositivo; cerrar la app no lo borra.

**Confirmación y seguimiento**
- Un botón: "Confirmar pedido". Sin conexión: queda en cola y se confirma al volver la señal (idempotente por `request_uuid`), con estado visible.
- Resultado por OC con línea de tiempo tipo seguimiento de envío: Creada → Aprobada → Enviada al proveedor → Recibida parcial/total.
- Acciones por OC: compartir por WhatsApp, PDF.
- Sección "Pedidos" con el estado de cada OC en tiempo real.

**Aprobadores (móvil)**
- Bandeja con tarjetas; aprobar con un toque y "Deshacer" durante unos segundos; rechazar con motivo en bottom sheet.

### 6.2 `confirmar_pedido(pedido_id, request_uuid)` — una transacción

1. Valida estado `BORRADOR` y permisos.
2. Agrupa por proveedor y crea una OC por cada uno (número `OC-<SEDE>-<AAAA>-000123`, tabla `secuencias` con bloqueo de fila).
3. Copia ítems con snapshot de precio, presentación y factor.
4. Ejecuta `evaluar_aprobacion` por OC.
5. Registra eventos; pedido pasa a `CONFIRMADO`.
6. `request_uuid` evita OC duplicadas por doble toque o reintento.

### 6.3 Recepción — lista de pendientes

- Pantalla de inicio del kiosco: sección **Pendientes** con OC `APROBADA`, `ENVIADA` y `RECIBIDA_PARCIAL`, ordenadas por entrega estimada; badge "atrasada" si pasó la fecha; badge "no enviada" si está aprobada pero nadie marcó el envío.
- Con `recepcion.pendientes.ver_en_aprobacion`: también se ven las `PENDIENTE_APROBACION`, en gris y sin poder recibir contra ellas.
- Al iniciar recepción y elegir proveedor se sugieren sus OC pendientes; opción "Sin OC" (queda marcada para revisión).
- Precarga de ítems esperados (saldo pendiente) y comparación de **pedida · remito · recibida**.
- Diferencias: faltante, sobrante, no pedido, sustitución, rechazo, con motivo obligatorio.
- Al cerrar, se recalcula el saldo y se actualiza el estado de la OC.

## 7. Estados

**Pedido**
```
BORRADOR → CONFIRMADO | DESCARTADO
```

**Orden de compra**
```
PENDIENTE_APROBACION → APROBADA | RECHAZADA
APROBADA → ENVIADA → RECIBIDA_PARCIAL → RECIBIDA → CERRADA
APROBADA | ENVIADA → ANULADA (motivo, sin recepciones)
RECIBIDA_PARCIAL → CERRADA (cierre de saldo con motivo)
```
`atrasada` es un indicador calculado (fecha estimada vencida), no un estado.

## 8. Modelo de datos

Todas las tablas con `tenant_id` y `sede_id` (salvo catálogos globales), RLS por permiso.

```sql
-- Permisos
permisos              (codigo PK, modulo, descripcion)            -- global, semilla
roles                 (id, nombre, tipo INTERNO|EXTERNO, nivel_aprobacion, limite_monto_sin_aprobacion, activo)
rol_permisos          (rol_id, permiso_codigo)
sectores              (id, nombre)
sector_rubros         (sector_id, rubro_id)                        -- qué rubros ve cada sector
usuario_roles         (user_id, rol_id, sede_id, sector_id null, proveedor_id null)  -- proveedor_id: portal futuro
configuracion_empresa (permitir_autoaprobacion, ...)

-- Catálogo
rubros                (id, nombre, orden, activo)                 -- ej.: Comida, Limpieza, Descartables
categorias            -- existente: + rubro_id, activo            -- ej.: Proteínas, Lácteos (rubro Comida)
productos             -- existente: + sku, unidad_stock, activo; el rubro se deriva de categoria_id
presentaciones        (id, producto_id, nombre, factor, activa)
producto_codigos      (id, producto_id, presentacion_id, codigo, tipo)  UNIQUE(tenant_id, codigo)
proveedores           -- existente: + codigo (ID del proveedor), contacto, telefono_whatsapp, email, canal_envio,
                      --   plazo_entrega_dias, dias_pedido[], monto_minimo
producto_proveedor    (producto_id, proveedor_id, presentacion_id, codigo_proveedor,
                       precio_actual, preferido, activo)
precios_historial     (producto_proveedor_id, precio, vigente_desde, usuario_id)

-- Aprobación
reglas_aprobacion     (alcance, alcance_id, modo, monto_umbral, nivel_requerido, activa)

-- Pedidos y OC
pedidos_compra        (estado, usuario_id, sector_id, request_uuid, creado_en, confirmado_en)
pedido_items          (pedido_id, producto_proveedor_id, presentacion_id, cantidad)
secuencias            (tipo, anio, ultimo_numero)
ordenes_compra        -- existente: + pedido_id, proveedor_id, numero, estado,
                      --   requiere_aprobacion, nivel_requerido, tipo_aprobacion,
                      --   aprobada_por, aprobada_en, motivo_rechazo, reglas_aplicadas jsonb,
                      --   fecha_entrega_estimada, total_estimado, enviada_en, canal_envio
oc_items              -- existente: + producto_id, presentacion_id, cant_pedida, factor,
                      --   precio_unitario, subtotal, disparo_aprobacion
recepcion_items       -- existente: + oc_item_id null, presentacion_id, cant_pedida
v_oc_saldos           -- vista: pedido vs recibido por oc_item
v_pendientes_recepcion -- vista: OC visibles para Recepción con saldos e indicadores
eventos               -- existente, sin cambios
```

Nota: si el MVP de Recepción ya tiene `perfiles (rol)`, la etapa 1 migra ese campo a `usuario_roles` con una migración nueva, sin romper lo existente.

## 9. Etapas de ejecución (un commit por etapa)

| # | Etapa | Entregable verificable | Estimado |
|---|---|---|---|
| 0 | Verificación de base | Estado del repo y de Supabase revisado; migraciones de Recepción aplicadas; plan de migración de `perfiles` | 0,5 día |
| 1 | Permisos y roles | Tablas de permisos, roles semilla, `tiene_permiso()`, RLS actualizado, pantalla admin de roles/usuarios | 2 días |
| 2 | Catálogo | Modelo Rubro → Categoría → Producto → Proveedor, con presentaciones, códigos múltiples y precios. El alta de productos pertenece al módulo de Administración (futuro); hasta entonces se carga por seed o CSV | 2 días |
| 3 | Importación CSV | Plantillas CSV descargables, validación con Zod, vista previa de errores, carga masiva | 1 día |
| 4 | Reglas de aprobación | Tabla, pantalla de configuración (empresa/rubro/producto), `evaluar_aprobacion` con tests SQL | 1,5 días |
| 5 | Marketplace móvil y carrito | PWA instalable, inicio con "repetir último pedido", buscador, chips de rubro, tarjeta con stepper inline, bottom sheets, carrito agrupado por proveedor con barra fija, persistencia local, auditoría UX a 375 px | 3 días |
| 6 | Confirmación y OC | `confirmar_pedido`, numeración, snapshot, cola offline de confirmación, seguimiento por OC, PDF, compartir por WhatsApp/mail, marcar enviada | 2 días |
| 7 | Bandeja de aprobación | Tarjetas móviles por nivel, aprobar con deshacer, rechazar en bottom sheet, tiempo real, eventos | 1 día |
| 8 | Pendientes en Recepción | `v_pendientes_recepcion`, sección Pendientes en el kiosco, selección de OC, precarga, escaneo por código → presentación → factor, triple cantidad, saldos | 2,5 días |
| 9 | Tablero de OC | Estados, filtros, detalle con línea de tiempo, anular / cerrar saldo | 1 día |
| 10 | Datos demo y prueba | Seed con empresa demo (rubros gastronómicos, 3 proveedores, 40 productos, reglas), guion de prueba de punta a punta | 1 día |

Total estimado: ~17,5 días de trabajo efectivo (≈ 4 semanas calendario). Es una estimación sin conocer aún el estado real del repo; se ajusta en la etapa 0.

**Criterio de salida del MVP:** un comprador arma un pedido con productos de 3 proveedores; una OC queda en aprobación por regla de rubro, otra se aprueba sola; el encargado aprueba la pendiente; las 3 aparecen en Pendientes de Recepción; se recibe una completa escaneando cajas y otra parcial; los saldos y estados se actualizan; todo queda en `eventos`.

## 10. Fases posteriores

| Fase | Alcance |
|---|---|
| 3. Automatización | Envío automático de OC por n8n, avisos de aprobación por WhatsApp/mail, alertas de OC atrasadas, regla por proveedor, editar y aprobar |
| 4. Escala | Aprobación multinivel en cadena, pedido sugerido por stock/consumo/recetas, solicitudes internas por sector consolidadas por el comprador, compras centralizadas multisede, scoring de proveedores |
| 5. Portal de proveedor | Acceso externo del proveedor: ver y confirmar OC, informar fecha de entrega y faltantes anticipados, cargar remito y factura, actualizar listas de precios. Se apoya en el mismo modelo de permisos (roles de tipo `EXTERNO` vinculados a `proveedor_id`, RLS limitado a sus propias OC) |

## 11. Indicadores para validar el MVP

- % de recepciones con OC asociada.
- Tiempo de armado de pedido y tiempo medio de aprobación.
- Diferencias detectadas en recepción contra OC (cantidad y monto).
- % de OC recibidas completas y en fecha, por proveedor.
- % de pedidos hechos desde el celular; tiempo para armar un pedido habitual en móvil (objetivo < 60 s); toques para repetir el último pedido (objetivo ≤ 3).

## 12. Pendientes de relevamiento

- Cargos/sectores reales y qué puede hacer cada uno (para ajustar los roles semilla).
- Rubros reales y cuáles requieren aprobación (siempre / por monto / nunca), con umbrales.
- Productos puntuales con regla distinta a su rubro.
- Cómo se origina hoy un pedido (define si se adelantan las solicitudes internas por sector).
- Canal de envío a cada proveedor.
- Catálogo: insumos, proveedores, presentaciones y códigos de barra disponibles.
