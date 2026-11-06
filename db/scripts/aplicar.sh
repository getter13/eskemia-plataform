#!/bin/sh
#
# Eskemia · Aplica migraciones pendientes y semillas de producción.
#
# Qué hace: corre en orden cada db/migraciones/*.sql que no figure en
# migraciones.aplicadas (cada una en su transacción), después todas las
# db/semillas/*.sql (idempotentes) y por último recarga el esquema de PostgREST.
# Dónde encaja: Etapa 2. Mismo procedimiento local, en CI y en producción.
# Migraciones solo hacia adelante: una aplicada no se vuelve a correr ni se edita.
#
# Uso: sh db/scripts/aplicar.sh

set -e
. "$(dirname "$0")/comun.sh"

psql_db <<'SQL'
create schema if not exists migraciones;
revoke all on schema migraciones from public;
create table if not exists migraciones.aplicadas (
  nombre      text primary key,
  aplicada_en timestamptz not null default now()
);
SQL

for archivo in "$RAIZ_DB"/migraciones/*.sql; do
    nombre=$(basename "$archivo")
    ya=$(echo "select 1 from migraciones.aplicadas where nombre = '$nombre'" | psql_db -tA)
    if [ "$ya" = "1" ]; then
        continue
    fi
    echo "Aplicando $nombre"
    { echo "begin;"; cat "$archivo"; echo; echo "insert into migraciones.aplicadas (nombre) values ('$nombre');"; echo "commit;"; } | psql_db
done

for archivo in "$RAIZ_DB"/semillas/*.sql; do
    echo "Semilla $(basename "$archivo")"
    psql_db -1 < "$archivo"
done

echo "notify pgrst, 'reload schema';" | psql_db
echo "Base al día."
