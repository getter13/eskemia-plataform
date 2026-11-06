#!/bin/sh
#
# Eskemia · Funciones comunes de los scripts de base.
#
# Qué hace: define cómo ejecutar psql dentro del contenedor supabase-db del stack de
# infra/compose. Lo incluyen aplicar.sh, reset.sh y pruebas.sh.
# Variables: DB_CONTENEDOR (por defecto supabase-db).

DB_CONTENEDOR="${DB_CONTENEDOR:-supabase-db}"
RAIZ_DB="$(cd "$(dirname "$0")/.." && pwd)"

# psql como postgres (BYPASSRLS, dueño de los objetos). Lee el SQL de stdin.
psql_db() {
    docker exec -i "$DB_CONTENEDOR" psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 "$@"
}

# psql como supabase_admin: solo para el reset (borrar usuarios de auth y objetos de Storage).
psql_admin() {
    docker exec -i "$DB_CONTENEDOR" psql -U supabase_admin -d postgres -X -q -v ON_ERROR_STOP=1 "$@"
}
