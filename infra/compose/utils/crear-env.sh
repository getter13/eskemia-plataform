#!/bin/sh
#
# Eskemia · Crea infra/compose/.env con secretos propios.
#
# Qué hace: copia .env.example a .env y completa todos los secretos usando los
# utilitarios oficiales de la release fijada:
#   - utils/generate-keys.sh     (openssl: contraseñas, claves, JWT HS256)
#   - utils/add-new-auth-keys.sh (node: par EC P-256, JWKS, claves opacas)
# Además genera POOLER_TENANT_ID y deja .env con permisos 600.
# Dónde encaja: paso único de la Etapa 0 / Plan B del runbook, antes del primer
# `docker compose up -d`. Se niega a correr si .env ya existe, porque
# POSTGRES_PASSWORD se graba en el primer arranque y no se puede cambiar así.
#
# Uso (desde cualquier carpeta):
#   sh infra/compose/utils/crear-env.sh
#

set -e

cd "$(dirname "$0")/.."

if [ -f .env ]; then
    echo "Error: ya existe infra/compose/.env. No lo piso."
    echo "Si querés empezar de cero, borrá .env Y volumes/db/data a mano."
    exit 1
fi

if [ -d volumes/db/data ] && [ -n "$(ls -A volumes/db/data 2>/dev/null)" ]; then
    echo "Error: volumes/db/data tiene datos de una instalación anterior."
    echo "Una contraseña nueva no coincidiría con la grabada. Borrá esa carpeta primero."
    exit 1
fi

umask 077
cp .env.example .env
chmod 600 .env

sh utils/generate-keys.sh --update-env >/dev/null
# add-new-auth-keys.sh también intenta descomentar líneas en docker-compose.yml;
# acá ya están activas, así que no cambia nada. Su aviso sobre SUPABASE_JWKS
# (Edge Functions) no aplica: ese servicio no existe en este stack.
sh utils/add-new-auth-keys.sh --update-env >/dev/null 2>&1

pooler_tenant_id=$(openssl rand -hex 8)
sed -i "s|^POOLER_TENANT_ID=.*$|POOLER_TENANT_ID=${pooler_tenant_id}|" .env

# Los utilitarios oficiales dejan copias .old; contienen secretos o son ruido.
rm -f .env.old docker-compose.yml.old

# Verificación: ningún secreto puede quedar vacío.
faltan=""
for var in POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY \
    SUPABASE_PUBLISHABLE_KEY SUPABASE_SECRET_KEY JWT_KEYS JWT_JWKS \
    ANON_KEY_ASYMMETRIC SERVICE_ROLE_KEY_ASYMMETRIC DASHBOARD_PASSWORD \
    SECRET_KEY_BASE REALTIME_DB_ENC_KEY VAULT_ENC_KEY PG_META_CRYPTO_KEY \
    S3_PROTOCOL_ACCESS_KEY_ID S3_PROTOCOL_ACCESS_KEY_SECRET POOLER_TENANT_ID; do
    if ! grep -q "^${var}=..*" .env; then
        faltan="$faltan $var"
    fi
done

if [ -n "$faltan" ]; then
    echo "Error: quedaron vacíos:$faltan"
    exit 1
fi

echo "Listo: infra/compose/.env creado con secretos propios (permisos 600)."
echo "Guardá una copia en tu gestor de contraseñas. Studio: usuario y"
echo "contraseña en DASHBOARD_USERNAME / DASHBOARD_PASSWORD."
