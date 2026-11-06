# Eskemia · Contexto para Claude Code (núcleo)

> Plan de ejecución completo (12 etapas + cierre, con prompts): https://claude.ai/artifact/EgZhTeHoHzLQDBPbdUne2A
> Copiar este archivo como CLAUDE.md en la raíz del repo. Los CLAUDE.md de Compras y Recepción pasan a docs/planes/.
> Aprobado por el CEO el 05/11/2026 (barra de navegación a la izquierda).
> 06/11/2026: se agrega la sección "SEO y posicionamiento".
> 06/11/2026: estética v2 e Inicio personalizable aprobados por el CEO (secciones "Estética v2" e "Inicio").
> Sistema de diseño vigente: **Eskemia v2** https://claude.ai/artifact/HgFF2PGHQTtA8qwBrKmMMV (tokens.json es la fuente de paquetes/tokens). El sistema "Eskemia" v1 queda solo como histórico.
> Referencia visual: https://claude.ai/artifact/Rr3PZkXJ7vLAnB6ChLKQZi (página "v2 · Estilo nuevo").

Eskemia es una plataforma multi-organización (ERP/CRM/POS + agentes de IA) para estandarizar
procesos operativos y administrativos con trazabilidad. Se despliega en tres modos con el
mismo código: Cloud compartido, Cloud dedicado y Local. Plan vigente:
docs/planes/plan-ejecucion-esqueleto.md. Ante dudas de diseño, ese documento manda.

## Vocabulario
- Cuenta: identidad global de una persona (auth.users + nucleo.cuentas).
- Organización: la unidad de negocio (antes "tenant"). Sede: ubicación dentro de ella.
- Membresía: vínculo cuenta ↔ organización, con puesto, roles y estado.
- Módulo / herramienta: Compras, Recepción, Salas. Se habilita por organización.
- Tarjeta de Inicio: bloque de información o acceso que un módulo ofrece para el Inicio.

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
- Cada módulo nuevo: esquema SQL + entrada en modulos/registro.ts (con sus tarjetas de Inicio)
  + permisos + tests + doc.
- Migraciones solo hacia adelante, una nueva por cambio. db/legado/ es solo lectura.
- Tests de aislamiento A/B para toda tabla nueva.

## Comentarios (obligatorio)
- Cabecera en cada archivo: qué hace y dónde encaja.
- JSDoc en toda función exportada.
- En cada RPC: qué hace, precondiciones, permisos que exige y eventos que escribe.
- Ningún archivo de src supera ~300 líneas sin justificación escrita.

## UI
- Paleta: manual de marca Eskemia, sin cambios (surface-100/200, line, ink, ink-muted, brand,
  brand-deep, brand-tint, accent, signal-error). Proporción 70 neutros · 20 brand · 10 accent.
  accent nunca como texto sobre claro. Tokens en paquetes/tokens, generados desde el
  tokens.json del sistema de diseño Eskemia v2.
- Estética: sección "Estética v2" de este archivo. Comportamiento: docs/principios-ux.md.
- Mobile first a 375 px. Barra de navegación vertical a la IZQUIERDA en escritorio
  (posición en --nav-lado), colapsada en tablet, barra inferior + hoja en celular.
- Zona superior de la barra: selector de organización, Inicio, Perfil de empresa, Usuarios,
  Salas de reuniones, Herramientas (Compras, Recepción). Zona inferior: Perfil personal,
  Cuenta, Privacidad, Cerrar sesión.
- Skills VectorLab en cada etapa con UI; cerrar con ux-audit.
- Español rioplatense con voseo; 1.240,50; dd/mm/aaaa; $ 1.240,50.

## Estética v2 (aprobada 06/11/2026)

Referencia de estilo: el rediseño 2026 de Calendly (aire, formas redondeadas, íconos sólidos
en contenedores, píldoras). Se toma el criterio, nunca sus activos: no se usan sus tipografías
(licencia paga), íconos, logo ni formas propias.

**Tokens, no valores.** Ningún componente escribe a mano color, familia, tamaño, radio,
sombra ni espaciado: todo sale de paquetes/tokens. Los tokens se nombran por USO
(--font-ui, --font-data, --radius-card), nunca por la fuente o el valor (--font-mono, --r-24),
para que un cambio estético sea editar un solo archivo. Lint en CI que falle con hex, px fuera
de escala o familias tipográficas fuera de tokens.

| Aspecto | Regla |
|---|---|
| Tipografía | Una sola familia: **Manrope** (OFL), autoalojada en woff2 con @font-face y font-display: swap. Nunca desde un CDN (CSP 'self', funciona sin señal). Pesos 400 a 800 |
| Jerarquía | Titulares 800 con tracking negativo (-0.02 a -0.03em); títulos de tarjeta 800; cuerpo 500; metadatos 500 en ink-muted. Sentence case |
| Números | Montos, cantidades, números de OC, remitos, códigos e IDs con la misma familia y `font-variant-numeric: tabular-nums` (token --font-data). **Prohibida la monoespaciada** en la UI |
| Montos | Una sola función `formatearMonto()` en el front (redondeo, decimales, `$ 1.240,50`). Ningún componente formatea montos por su cuenta |
| Radios | Tokens radius-icon 10 · radius-control 14 · radius-block 18 · radius-card 24 · radius-pill 999 |
| Píldoras | Estados, chips de filtro, buscador, botones de acción secundaria, barra fija de carrito/confirmación y navegación inferior móvil |
| Profundidad | Fondo de la app surface-200; tarjetas y paneles surface-100 con `--shadow-card` (0 1px 2px rgba(21,24,29,.05), 0 8px 24px rgba(21,24,29,.05)). Elementos flotantes (barra de carrito, menús, hojas) con `--shadow-float`. Los bordes quedan para estados: error, borrador/en curso (punteado), foco |
| Íconos | Sólidos (relleno), dentro de contenedores redondeados: brand-tint con ícono brand, o brand con ícono surface-100 para la acción principal. Librería abierta con variante sólida (candidata: Phosphor, MIT; confirmar en la etapa de tokens). Íconos de solo trazo únicamente para utilidades chicas (buscar, flechas, cerrar) |
| Estados | Píldora con ícono + texto, nunca solo color |
| Transparencias | Solo en sombras. Sin glassmorphism, sin desenfoques, sin degradados decorativos |
| Táctil | ≥ 44 px en escritorio, ≥ 48 px en celular, ≥ 56 px en el kiosco de Recepción |

Pendiente de verificar en la etapa de tokens: calidad de las cifras tabulares de Manrope.
Si no alcanza, se elige otra familia libre con tnum y solo cambia el token.
El sitio público (apps/sitio) reutiliza estos mismos tokens.

## Inicio (aprobado 06/11/2026)
- Inicio **no** es de ningún módulo: no muestra datos de Compras ni de otro módulo por defecto.
- Se arma con **tarjetas**. Cada módulo declara las suyas en modulos/registro.ts
  (id, título, permiso requerido, tamaño). Los módulos del núcleo (Usuarios, Salas, Perfil de
  empresa) también ofrecen tarjetas.
- **Cada usuario arma su propio Inicio**, eligiendo solo entre las tarjetas de las
  herramientas que el administrador de la organización le habilitó. Una tarjeta es elegible si
  el módulo está habilitado en la organización y el usuario tiene el permiso; lo valida la base
  (RPC), no la pantalla.
- Cuentas free asociadas a una organización con membresía: su alcance lo define lo que la
  organización tiene contratado y lo que el administrador le habilitó, no el plan de la cuenta
  personal.
- La configuración se guarda en la base por membresía (cuenta + organización), no en el
  dispositivo: es la misma en celular y escritorio. Cada cambio escribe en eventos.
- Si el administrador retira un permiso o deshabilita un módulo, sus tarjetas desaparecen del
  Inicio de quien lo perdió sin romperlo.
- UI: botón "Personalizar inicio" y espacio "Agregar tarjeta" siempre visibles; Inicio vacío
  con estado vacío accionable, nunca pantalla en blanco.
- Abierto: Inicio por defecto por puesto, definido por el administrador como punto de partida.

## SEO y posicionamiento

Principio: **lo público se indexa, lo privado nunca.** La app es una SPA detrás de login:
no posiciona ni debe posicionar. El posicionamiento vive en un sitio público separado.

### Dominios (fijar antes del primer deploy público, no se cambian después)
- `www.eskemia.com`: sitio público (landing, módulos, precios, guías, blog, foro público).
  Es el único origen indexable. Redirección 301 de `eskemia.com` a `www`, y de http a https.
- `app.eskemia.com`: la PWA. `X-Robots-Tag: noindex, nofollow` en todas las respuestas
  (cabecera en Caddy) y `robots.txt` con `Disallow: /`.
- Entornos de desarrollo y staging: siempre `noindex` y, si son accesibles, con autenticación.

### Sitio público (apps/sitio)
- HTML generado en compilación (SSG), no renderizado en el cliente. Un sitio que depende de
  JavaScript para mostrar el contenido se indexa peor y más lento.
- Herramienta propuesta: Astro (TypeScript, HTML estático, cero JS por defecto). **Pendiente
  de aprobación del CEO**; respeta la regla de dos lenguajes. Reutiliza paquetes/tokens.
- Se construye cuando arranque la Fase 4 (Cloud abierto). Las reglas de esta sección rigen
  desde ahora para no tomar decisiones que después haya que deshacer.

### Reglas técnicas obligatorias en páginas públicas
- Un `<title>` único (≤ 60 caracteres) y una `meta description` única (≤ 155) por página.
- Un solo `<h1>` por página; jerarquía h2/h3 sin saltos; HTML semántico (`header`, `main`,
  `nav`, `article`, `footer`).
- `<link rel="canonical">` absoluto en cada página. `<html lang="es-AR">`.
- Open Graph y Twitter Card (título, descripción, imagen 1200×630) en cada página.
- Datos estructurados JSON-LD: `Organization` y `WebSite` en el inicio;
  `SoftwareApplication` en páginas de producto/módulo; `FAQPage` y `BreadcrumbList` donde
  aplique. Validar con la herramienta de resultados enriquecidos de Google.
- `sitemap.xml` generado en cada compilación y `robots.txt` que lo referencie.
- URLs en español, minúsculas, con guiones, sin IDs ni parámetros:
  `/modulos/compras`, `/guias/control-de-recepcion-de-mercaderia`. Una URL publicada no se
  renombra; si es inevitable, 301 permanente.
- Imágenes con `alt` descriptivo, dimensiones explícitas, formato AVIF/WebP y carga diferida
  fuera del primer pantallazo.
- Core Web Vitals en verde en móvil (LCP < 2,5 s, INP < 200 ms, CLS < 0,1). Lighthouse en
  CI con umbral: SEO ≥ 95, Performance ≥ 90, Accesibilidad ≥ 95; el build falla si baja.
- Página 404 propia que devuelva estado 404 real.

### Contenido (responsabilidad del CEO, con apoyo de K)
- Una página por módulo orientada a la búsqueda del problema, no al nombre del producto
  ("control de recepción de mercadería", "órdenes de compra para gastronomía").
- Guías y casos reales de operación: es el diferencial frente a ERP genéricos.
- El foro de la comunidad: hilos públicos indexables solo si son de acceso abierto; los de
  organizaciones, nunca.
- Nunca contenido de clientes ni datos de una organización en páginas públicas.

### Medición
- Google Search Console y Bing Webmaster Tools verificados por DNS al publicar el dominio.
- Analítica respetuosa de privacidad y sin cookies de terceros (ej. Plausible o Umami
  self-hosted), alineada con la Ley 25.326. Nunca analítica de marketing dentro de la app.

## Fuera de alcance en esta etapa
Precios, planes, pasarelas de pago, suscripciones, voz, Eskemia Local. El sitio público se
construye en Fase 4; en esta etapa solo aplica la regla de `noindex` en la app y entornos.

## Forma de trabajo
- Una etapa por commit, con resumen corto al cerrar.
- Antes de crear tablas o RPC nuevas, listarlas y esperar OK.
- Secretos solo en .env (fuera de git). Nunca service_role en el front.
- Pedir confirmación antes de operaciones destructivas.
- Si falta un dato, preguntar. No inventar.
