# infra/compose · Supabase self-hosted de Eskemia

Stack local idéntico a producción (Plan B de `docs/runbook-infra.md`, Etapa 0 de
`docs/planes/plan-ejecucion-esqueleto.md`). Mismo `docker-compose.yml` en desarrollo y en
producción; lo que cambia va en overlays y en `.env`.

## Release fijada

`self-hosted/v0.8.4` del repo `supabase/supabase` (commit `189adda9`), ver `.supabase-version`.

| Servicio | Imagen | Puerto en el host |
|---|---|---|
| db | `supabase/postgres:17.6.1.136` | — |
| auth | `supabase/gotrue:v2.197.0` | — |
| rest | `postgrest/postgrest:v14.18` | — |
| realtime | `supabase/realtime:v2.148.3` | — |
| storage | `supabase/storage-api:v1.89.12` | — |
| meta | `supabase/postgres-meta:v0.100.0` | — |
| studio | `supabase/studio:2026.11.02-sha-a05e7ec` | vía gateway |
| api-gw (Envoy) | `envoyproxy/envoy:v1.39.6` | `127.0.0.1:8000` |
| supavisor | `supabase/supavisor:2.9.13` | `127.0.0.1:5432` (sesión), `127.0.0.1:6543` (transacción) |
| mailpit (solo dev) | `axllent/mailpit:v1.33.0` | `127.0.0.1:8025` (web), `127.0.0.1:1025` (SMTP) |

**Quitados respecto del upstream:** Edge Runtime, Logflare/Vector (y `logs.sql`), imgproxy
(Storage queda con `ENABLE_IMAGE_TRANSFORMATION=false`), overlays de Kong, nginx, Caddy, S3,
PgBouncer y pg15. El overlay de Caddy se suma en la Fase 3 de producción, con imagen fijada
y el Caddyfile propio (PWA + API en un solo origen).

## Primera vez

```bash
cd ~/eskemia/infra/compose
sh utils/crear-env.sh     # genera .env con secretos propios (chmod 600)
docker compose up -d
docker compose ps         # todos (healthy)
```

`POSTGRES_PASSWORD` queda grabada en `volumes/db/data` en el primer arranque. No se edita
en `.env` después; para rotarla, `utils/db-passwd.sh`.

## Día a día

| Acción | Comando (desde `infra/compose/`) |
|---|---|
| Levantar | `docker compose up -d` |
| Bajar (conserva datos) | `docker compose down` |
| Estado | `docker compose ps` |
| Logs de un servicio | `docker compose logs -f auth` |
| Reiniciar Auth tras cambiar `.env` | `docker compose up -d auth` |

| Qué | Dónde |
|---|---|
| Studio | http://localhost:8000 (usuario y contraseña: `DASHBOARD_*` en `.env`) |
| API (supabase-js) | `http://localhost:8000` con `SUPABASE_PUBLISHABLE_KEY` |
| Mailpit | http://localhost:8025 |
| Postgres (pooler) | `psql -h 127.0.0.1 -p 5432 -U postgres.<POOLER_TENANT_ID> postgres` |

## Empezar de cero (destructivo)

Los datos locales son descartables. Esto borra base y archivos de Storage:

```bash
docker compose down -v
rm -rf volumes/db/data volumes/storage/stub
```

Si además se quieren secretos nuevos: borrar `.env` y volver a `sh utils/crear-env.sh`.

## Auth configurado

- Registro público abierto, con confirmación de email obligatoria.
- Contraseña mínima de 12 caracteres (`PASSWORD_MIN_LENGTH`).
- Teléfono, anónimos y OAuth deshabilitados.
- Claves asimétricas ES256 activas; las claves HS256 heredadas siguen validando.
- En desarrollo, todo email va a Mailpit con `SMTP_USER`/`SMTP_PASS` vacíos (el cliente
  SMTP de Auth no manda credenciales sin TLS).

## Actualizar la release

1. Ver la última `self-hosted/v*` con
   `git ls-remote --tags https://github.com/supabase/supabase 'refs/tags/self-hosted/v*'`.
2. Clonar esa tag aparte y comparar su `docker/` con esta carpeta (`diff -r`), respetando
   los recortes de la cabecera de `docker-compose.yml`.
3. Leer `CHANGELOG.md` y `versions.md` del upstream; actualizar tags, esta tabla y
   `.supabase-version`. Probar en local antes que en producción.

## Archivos

- `docker-compose.yml`: stack base, sin secretos.
- `docker-compose.dev.yml`: overlay de desarrollo (Mailpit).
- `.env.example`: plantilla comentada; `.env` real nunca va a git.
- `utils/crear-env.sh`: genera el `.env`. El resto de `utils/` y `run.sh` son los
  utilitarios oficiales de la release, sin cambios.
- `volumes/`: configuración montada (Envoy, SQL de inicialización, pooler). `db/data`,
  `storage` y `snippets` son datos locales ignorados por git.
