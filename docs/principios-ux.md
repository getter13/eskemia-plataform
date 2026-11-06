# Eskemia · Principios UX/UI (todos los módulos)

> Rige para todos los módulos de Eskemia. Los colores, tipografías y tokens salen del manual de marca Eskemia; este documento define **cómo se usa** la interfaz, no cómo se ve.
>
> **Sistema de diseño v2 (aprobado por el CEO el 06/11/2026).** Los valores viven en `paquetes/tokens/tokens.json`. La estética completa está en la sección "Estética v2" del `CLAUDE.md` (manda ante cualquier diferencia); acá, el resumen de uso en la sección 9.

## 1. Para quién diseñamos

Quienes operan Eskemia son personas a las que el día a día les pasa por encima: cocineros, encargados, logística, compradores. Casi nunca están sentados frente a una computadora, tienen las manos ocupadas, poco tiempo y conexión irregular.

Consecuencias:

- **El celular es el dispositivo principal de la operación.** El escritorio es para supervisión, configuración y reportes.
- **Cada tarea operativa se completa en segundos y con una mano.**
- **El sistema supervisa por la persona**: la parametrización (permisos, reglas, aprobaciones) controla. La pantalla no le pide al operario que piense en el control.

## 2. Referencia de experiencia

| Contexto | Referencia | Qué tomamos |
|---|---|---|
| Marketplace de Compras | Mercado Libre, PedidosYa | Buscador siempre visible, agregar con un toque, carrito persistente con total visible, pedido multitienda agrupado, seguimiento del pedido como "envío" |
| Kiosco de Recepción | Autoservicio de supermercado | Una acción por pantalla, feedback inmediato por lectura, botones grandes |
| Back / reportes | Herramientas de análisis densas y limpias | Tablas, filtros, exportación, sin decoración |

## 3. Principios

1. **Mobile first real.** Se diseña a 375 px y se amplía. Ninguna función operativa existe solo en escritorio.
2. **Zona del pulgar.** Acciones principales abajo: barra de navegación inferior, barra fija de carrito/confirmación, hojas inferiores (bottom sheets) en lugar de modales centrados.
3. **Un toque para lo frecuente.** Agregar al carrito, aprobar una OC: un toque. Lo infrecuente puede costar dos.
4. **Valores por defecto inteligentes.** Presentación, proveedor y cantidad sugeridos según historial y configuración. El usuario corrige, no completa.
5. **Nada se pierde.** Carrito, borradores y formularios se guardan solos en el dispositivo. Cerrar la app no borra trabajo.
6. **Respuesta inmediata.** Actualización optimista (la UI responde antes que el servidor), sin spinners bajo 100 ms, skeletons en cargas largas, nunca pantallas en blanco.
7. **Tolerante a mala conexión.** La app abre y navega el catálogo sin señal (caché). Las acciones que requieren servidor se encolan o reintentan de forma idempotente, con estado visible.
8. **Estados con seguimiento.** Todo lo que el usuario inicia (pedido, OC, recepción) tiene una línea de tiempo visible tipo "seguimiento de envío".
9. **Errores que ayudan.** Nunca culpan al usuario, siempre ofrecen la salida. Validación al salir del campo, el error se limpia al corregir.
10. **Accesibilidad no negociable.** WCAG 2.2 AA, contraste ≥ 4.5:1, estados nunca solo por color, foco visible, `prefers-reduced-motion`.
11. **Sin ruido.** Sin glassmorphism, degradados decorativos, ilustraciones infantiles ni animaciones sin función.
12. **Textos con verbo.** Botones que dicen lo que hacen ("Confirmar pedido", "Aprobar OC"), nunca "OK", "Enviar" o "Aceptar" sueltos.

## 4. Patrones móviles estándar

| Patrón | Uso |
|---|---|
| Barra inferior de navegación (máx. 4–5 ítems) | Navegación principal en móvil; barra lateral colapsable en escritorio |
| Buscador fijo arriba | Catálogos y listados |
| Chips horizontales desplazables | Filtros rápidos (rubros, estados) |
| Tarjeta con stepper inline | Productos: el "+" se convierte en "− 2 +" sin salir de la lista |
| Barra fija de acción inferior | Carrito ("3 proveedores · 14 ítems · $ 182.400 — Ver pedido"), confirmación |
| Bottom sheet | Selección de presentación, proveedor, filtros, detalle rápido |
| Deslizar para acción | Solo con alternativa visible (botón) y deshacer |
| Toast con "Deshacer" | En lugar de confirmaciones para acciones reversibles |
| Confirmación nombrada | Solo para destructivas: "Anular OC-CEN-2026-000123" |
| Pull to refresh | Bandejas y listados |
| Vibración corta (Android, `navigator.vibrate`) | Agregar al carrito, lectura de escáner OK/error |

## 5. Objetivos táctiles y layout

- Mínimo 44 × 44 px en escritorio, 48 × 48 px en móvil y 56 px en el kiosco de Recepción. Separación mínima 8 px.
- Ritmo de espaciado de 4/8 px (tokens del manual).
- Sin desplazamiento horizontal de página entre 375 y 1280 px. Tablas: en móvil se transforman en tarjetas.
- Tipografía base 16 px en móvil (evita el zoom automático de iOS en inputs).

## 6. PWA

- Instalable en la pantalla de inicio del celular (manifest, íconos, `display: standalone`).
- Service worker: caché del shell de la app y del catálogo; actualización en segundo plano.
- Notificaciones web push (Fase 3): OC para aprobar, OC aprobada/rechazada, proveedor llegó.

## 7. Métricas de experiencia

- Tiempo para armar un pedido habitual en móvil: objetivo < 60 s.
- Tiempo para aprobar una OC desde la notificación: objetivo < 15 s.
- Tareas completadas sin ayuda en la primera prueba con usuarios reales.

## 8. Skills de UX en Claude Code

Antes de la primera pantalla, correr una vez `/vectorlab-ux-skills:setup-ui-ux-skills` en el repo. Respuestas sugeridas:

| Pregunta | Respuesta |
|---|---|
| Referencia estética | Mercado Libre / PedidosYa en flujo; sistema de diseño Eskemia v2 en lo visual (sobrio; radios y sombras solo por token) |
| Antipatrones prohibidos | Glassmorphism, degradados decorativos, CTAs múltiples por vista, ilustraciones caricaturescas, modales centrados en móvil, spinners de pantalla completa |
| Accesibilidad | WCAG 2.2 AA |
| Voz | Español rioplatense con voseo ("Confirmá el pedido"), directo, sin tecnicismos |
| Íconos | Sólidos dentro de contenedores (v2). Librería candidata: Phosphor (MIT), a confirmar en la etapa de tokens |

En cada etapa con UI usar las skills correspondientes (`page-patterns`, `viewports`, `forms`, `surfaces`, `loaders`, `empty-states`, `errors`, `verbs`, `motion`) y cerrar con `ux-audit`.

## 9. Sistema de diseño v2

| Tema | Regla |
|---|---|
| Tipografía | Manrope es la única familia, autoalojada en woff2 (nunca desde un CDN). Sin monoespaciada |
| Cifras | Tabulares en todo dato numérico (montos, cantidades, OC, remitos, códigos), vía `--font-data` |
| Tokens | Se usan por nombre de uso (`--font-ui`, `--font-data`, `--radius-card`, `--shadow-card`…), nunca primitivos ni valores sueltos. Un lint en CI falla con hex, px fuera de escala o familias fuera de tokens |
| Color, radio, sombra | Solo por token. Nada de hex, `rgb()`, radios o sombras escritos a mano |
| Profundidad | Fondo surface-200; tarjetas surface-100 con `--shadow-card`; flotantes con `--shadow-float`. Los bordes quedan para estados: error, en curso (punteado) y foco |
| Píldoras | Estados, chips, buscador, acciones secundarias, barra fija de carrito y navegación inferior móvil |
| Íconos | Sólidos, dentro de un contenedor (brand-tint con ícono brand; brand con ícono surface-100 para la acción principal). De solo trazo, únicamente utilidades chicas |
| Estados | Píldora con ícono y texto, nunca solo color |
| Montos | Siempre con `formatearMonto()`: `$ 1.240,50` |

## 10. Inicio personalizable

- El Inicio no es de ningún módulo y no muestra datos de ninguno por defecto.
- Cada usuario arma su Inicio con tarjetas, por organización: elige cuáles ve y en qué orden. Se guarda en la base por membresía (igual en celular y escritorio) y cada cambio queda en eventos.
- Cada módulo, incluidos los del núcleo (Usuarios, Salas, Perfil de empresa), declara sus tarjetas en `modulos/registro.ts` (código, título, permiso que exige, tamaño). El Inicio no conoce a ningún módulo.
- Una tarjeta es elegible solo si el módulo está habilitado y el usuario tiene su permiso. Lo valida la base (RPC), no la pantalla. Si después pierde el permiso o se deshabilita el módulo, la tarjeta desaparece sin romper el Inicio.
- "Personalizar inicio" y "Agregar tarjeta" siempre visibles. Sin tarjetas elegidas, el Inicio muestra un estado vacío accionable, nunca una pantalla en blanco.
- Pendiente de definir: Inicio por defecto por puesto, armado por el administrador como punto de partida.
