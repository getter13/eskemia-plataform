# Eskemia · Contexto para Claude Code (núcleo)

> Plan de ejecución completo (12 etapas + cierre, con prompts): https://claude.ai/artifact/EgZhTeHoHzLQDBPbdUne2A
> Copiar este archivo como CLAUDE.md en la raíz del repo. Los CLAUDE.md de Compras y Recepción pasan a docs/planes/.
> Aprobado por el CEO el 05/11/2026 (barra de navegación a la izquierda).

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
  (posición en --nav-lado), colapsada en tablet, barra inferior + hoja en celular.
- Zona superior de la barra: selector de organización, Inicio, Perfil de empresa, Usuarios,
  Salas de reuniones, Herramientas (Compras, Recepción). Zona inferior: Perfil personal,
  Cuenta, Privacidad, Cerrar sesión.
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
