# ADR 0002 · Supabase self-hosted como stack definitivo

- **Fecha:** 04/11/2026
- **Estado:** aceptada
- **Reemplaza a:** ADR 0001 (independencia de proveedor), que queda *supersedida*
- **Contexto nuevo:** no existe producción. Nadie usa la plataforma. Todo está en fase 0.

## Por qué cambia la decisión del ADR 0001

El ADR 0001 recomendaba quedarse en Supabase cloud. Su argumento central era no romper
la paridad de entornos con una producción viva, y no sumar carga de operación mientras
hubiera brechas P0 abiertas.

**Ese argumento no aplica: no hay producción viva.** Y con eso caen tres premisas:

1. **No hay nada que migrar.** Cero datos reales, cero usuarios, cero tablets en campo.
   El costo de mudarse es el más bajo que va a tener en toda la vida del producto, y sube
   de forma monótona a partir de acá.
2. **La carga de operación se paga una sola vez.** Si el destino es self-hosted, aprender
   a operarlo ahora (sin datos, sin nadie esperando) es más barato que operar cloud ahora
   y self-hosted después.
3. **El modelo de negocio 1 lo exige.** "Servicios en la nube, datos en la base del
   cliente" significa literalmente desplegar este stack para cada cliente. Escribir el
   runbook de self-hosting **es construir el producto**, no es gasto administrativo.

## Decisión

**Supabase self-hosted (Docker Compose oficial) como stack único en los tres entornos:
desarrollo, staging y producción.**

Con dos precisiones que son el núcleo de esta decisión:

### 1. "Servidor propio" significa el mismo stack, no un backend propio

Self-hosted Supabase es el mismo producto que la nube: Postgres, Auth (GoTrue), Storage,
PostgREST, Realtime, Studio y el runtime de Edge Functions, detrás de un gateway (Envoy
en las versiones actuales; reemplazó a Kong en agosto de 2026).

Eso implica **cero reescritura de código**:

| Pieza | Hoy depende de | Self-hosted |
|---|---|---|
| RLS (`auth.uid()`) | GoTrue | Mismo GoTrue |
| `adjuntos` (fotos, firmas) | Storage API | Misma Storage API |
| Cada llamada del front y las RPC | PostgREST | Misma PostgREST |
| OC aprobada → Pendientes | Realtime | Mismo Realtime |

Construir un backend propio desde cero (reimplementar auth, storage y la capa REST)
sería meses de trabajo y obligaría a reescribir las 19 migraciones, todas las políticas
RLS y toda la capa de datos del front. **Queda descartado.**

### 2. Docker Compose es el entorno de desarrollo desde ahora

Esto resuelve dos cosas de una: la brecha P0 #1 (hoy se prueba contra la única base) y la
independencia. Si desarrollo corre el mismo Compose que producción, la paridad es exacta
por construcción, staging es el mismo Compose en otro host, y *dónde vive producción* pasa
a ser un detalle de despliegue en vez de una decisión de arquitectura.

## Lo que asumimos (costos reales, verificados el 04/11/2026)

No hay que endulzarlo. Pasa a ser nuestro:

| Responsabilidad | Detalle |
|---|---|
| **Backups y PITR** | No vienen incluidos. PITR requiere `wal-g` o `pgBackRest` con archivado de WAL, montado por nosotros. Los archivos de Storage viven en otro volumen y **necesitan su propio backup**: un dump de la base no los incluye |
| **Actualizaciones** | El `docker-compose.yml` oficial no es un endpoint estable: cambia, con roturas (Kong → Envoy en agosto 2026, el servicio de logs pasó a opt-in en junio 2026). Hay que fijar versiones de imagen y tener runbook de upgrade |
| **Monitoreo** | Sin métricas de plataforma. Hay que montar Prometheus y Grafana, más agregación de logs |
| **Punto único de falla** | El Compose oficial corre todo en un host, sin balanceo ni failover |
| **Studio** | Sin control de acceso por rol; solo autenticación básica HTTP. **Nunca se expone a internet**: se accede por túnel SSH o VPN |
| **Infra** | Mínimo 4 GB de RAM y 2 núcleos; recomendado 8 GB y 4 núcleos para producción. El stack idle ronda los 2,5–3 GB antes de nuestros datos |
| **Un proyecto por stack** | Cada entorno es su propio Compose |

**El ahorro no es el motivo.** Un VPS de 8 GB cuesta aproximadamente lo mismo que el plan
Pro de Supabase. Lo que se compra es soberanía de datos y la capacidad de desplegar en la
infraestructura del cliente, que es el modelo de negocio 1.

### Mitigación que ya tenemos

El punto único de falla pesa menos de lo que parece en el módulo crítico: la PWA es
offline-first con cola en IndexedDB. Si el servidor se cae, Recepción **sigue operando** y
sincroniza al volver. Una caída degrada el servicio, no lo detiene. Eso compra tiempo de
recuperación, y es una razón más para no debilitar nunca la cola offline.

## Orden de ejecución

| Paso | Acción | Cuándo |
|---|---|---|
| 1 | Clonar el Compose oficial, **fijar versiones de imagen**, generar secretos propios, commitear `docker-compose.yml`, el override y `.env.example` (nunca el `.env`) | Próxima sesión |
| 2 | Aplicar las 19 migraciones y los seeds demo contra el stack local. Verificar login, Storage, Realtime y las RPC | Próxima sesión |
| 3 | Apuntar el front al stack local por `.env.local`. Correr el guion de prueba de punta a punta | Próxima sesión |
| 4 | Dar de baja el proyecto de Supabase cloud una vez que local funcione. No hay datos que migrar | Próxima sesión |
| 5 | Runbook de operación en `docs/runbook-infra.md`: arranque, upgrade con versiones fijadas, backup, **restore probado**, rotación de secretos | Antes del VPS |
| 6 | VPS de producción (8 GB): mismo Compose, Caddy o Traefik con TLS, firewall, Studio solo por túnel, Postgres sin puerto público | Antes del primer piloto |
| 7 | `pgBackRest` o `wal-g` con WAL + backup separado del volumen de Storage, copia fuera del servidor, y **un restore probado y documentado** | Antes del primer piloto |
| 8 | Prometheus y Grafana, con alertas de espacio, contenedor caído y antigüedad del último backup | Antes del primer piloto |

**Criterio de no retorno:** el paso 7 es bloqueante. No entra un solo dato real de un
cliente antes de tener un restore probado. Un backup que nunca se restauró no es un backup.

## Trampas conocidas a evitar

- `docker compose down -v` **no** borra los datos: en el Compose oficial Postgres y Storage
  usan bind mounts del host (`./volumes/db/data`, `./volumes/storage`). Borrar ese
  directorio sí destruye todo de forma irreversible.
- `POSTGRES_PASSWORD` se escribe en el volumen en el **primer** arranque y no se vuelve a
  leer del `.env`. Cambiarlo después rompe cada servicio que conecta con él.
- PostgREST cachea el esquema y no detecta DDL hecho por fuera: después de una migración
  aplicada por `psql` hay que recargar la caché con un `NOTIFY`.
- El Compose referencia del orden de 90 variables de entorno. `.env.example` documentado
  es obligatorio.

## Consecuencias sobre el plan P0

- **P0 #1 (staging)** se reformula: ya no es "crear un segundo proyecto en la nube" sino
  "Compose local como desarrollo + Compose en VPS como staging/producción".
- **P0 #2 (CI)** se simplifica: los tests SQL corren contra un Postgres efímero en el
  runner, nunca contra una base compartida.
- **P0 #5 (auth)** sigue igual, pero ahora se configura por `.env` y reinicio de
  contenedor, no por dashboard.
- **P0 #6 (backups)** se vuelve más pesado y más importante: pasa a ser enteramente nuestro.
- **P1 #8 (capa `api/`)** sigue siendo obligatoria. Self-hosting da soberanía de
  infraestructura; la capa `api/` da desacople de código. Son cosas distintas y se
  necesitan las dos.

## Fuentes

Documentación de self-hosting de Supabase y relevamientos de la comunidad consultados el
04/11/2026. Las versiones y los requisitos del Compose cambian seguido: **reverificar
antes de ejecutar el paso 1.**
