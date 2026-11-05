# ADR 0001 · Camino de independencia de proveedor

- **Fecha:** 04/11/2026
- **Estado:** aceptada
- **Contexto:** Eskemia debe soportar dos modelos de negocio (datos en la base del
  cliente / 100 % en la nube de Eskemia) y no quedar atada a Supabase.

## Pregunta planteada

¿Conviene usar Supabase en desarrollo y migrar producción a un servidor propio, para
iniciar el camino de la independencia?

## Decisión

**No.** No se adopta un stack distinto en desarrollo y en producción.

La independencia se construye en este orden:

1. **Ahora:** capa `api/` única en el front. Ningún componente importa `supabase-js`
   directo. El esquema vive solo en migraciones SQL portables.
2. **Ahora:** `dev → staging → prod` sobre el **mismo** stack. Staging es un segundo
   proyecto Supabase o el stack de Supabase en Docker local.
3. **Cuando haya volumen o el primer cliente del modelo 1:** servidor propio delgado
   (Fastify o NestJS) entre el navegador y la base, con catálogo central de tenants.
4. **Si hay que salir de Supabase:** self-hosting del **mismo** stack
   (`supabase/postgres` + GoTrue + Storage + PostgREST + Realtime), no de un stack nuevo.

## Motivos

- **Paridad de entornos.** Probar en un stack y publicar en otro hace que los bugs
  aparezcan solo en producción, donde más caro es. Es el escenario opuesto al que
  buscamos: hoy el problema es que se prueba *en* producción; la respuesta es un staging
  idéntico, no una producción distinta.
- **Supabase no es "solo Postgres".** Aporta Auth (GoTrue, del que depende `auth.uid()`
  en todas las políticas RLS), Storage (del que depende la tabla `adjuntos`), PostgREST
  (de la que depende cada llamada del front) y Realtime. Un "servidor propio" sin esas
  cuatro piezas obliga a reescribir RLS, subida de archivos y toda la capa de datos.
- **El acoplamiento no está en el hosting, está en el código.** Mover la base sin la capa
  `api/` deja el mismo acoplamiento, con más trabajo de operación encima.
- **Costo de operación.** Un servidor propio agrega backups, PITR, parches, alta
  disponibilidad, monitoreo y respuesta a incidentes. Hoy no hay equipo para eso y el
  tiempo rinde más en los módulos que validan el producto.

## Consecuencias

- Se acepta seguir en Supabase cloud en producción por ahora.
- Se exige que todo el esquema sea aplicable a cualquier Postgres 15+ con las extensiones
  de Supabase, y que ninguna migración contenga datos propios de Eskemia.
- Se exige la capa `api/` como condición para cualquier módulo nuevo (P1 de la auditoría).
- Cuando se evalúe self-hosting, el criterio de decisión será: primer cliente del modelo 1,
  o costo mensual de Supabase por encima del costo de operación propio, o un requisito
  legal de residencia de datos.

## Alternativa descartada

**Supabase self-hosted desde ahora (Docker, en VPS propio).** Es técnicamente viable y
sería el camino correcto si la independencia fuera urgente. Se descarta por ahora porque
agrega carga de operación sin resolver ninguna de las seis brechas P0 de la auditoría.
Se reevalúa cuando se cumpla alguno de los criterios de arriba.
