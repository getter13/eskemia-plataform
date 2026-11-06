#!/bin/sh
#
# Eskemia · Corre los tests SQL (pgTAP) de db/pruebas.
#
# Qué hace: ejecuta cada db/pruebas/NN_*.sql, precedido por _ayudantes.sql, dentro de
# una transacción que termina en ROLLBACK (no deja rastro). Falla si algún test imprime
# "not ok", si el plan no se cumple o si hay un error de SQL.
# Dónde encaja: local y CI, contra el stack de infra/compose con la base al día.
#
# Uso: sh db/scripts/pruebas.sh [archivo.sql ...]

set -e
. "$(dirname "$0")/comun.sh"

echo "set client_min_messages to warning; create extension if not exists pgtap with schema extensions;" | psql_db

if [ $# -gt 0 ]; then
    archivos="$*"
else
    archivos=$(ls "$RAIZ_DB"/pruebas/[0-9]*.sql)
fi

fallas=0
for archivo in $archivos; do
    nombre=$(basename "$archivo")
    salida=$({ echo "begin;"; cat "$RAIZ_DB/pruebas/_ayudantes.sql" "$archivo"; echo; echo "rollback;"; } | psql_db -tA 2>&1) || {
        echo "FALLA $nombre (error de SQL)"; echo "$salida" | tail -20; fallas=$((fallas + 1)); continue;
    }
    if echo "$salida" | grep -qE "^not ok|Looks like|# Failed"; then
        echo "FALLA $nombre"; echo "$salida" | grep -E "^not ok|^#" | head -40; fallas=$((fallas + 1))
    else
        echo "ok    $nombre ($(echo "$salida" | grep -c '^ok') tests)"
    fi
done

if [ "$fallas" -gt 0 ]; then
    echo "$fallas archivo(s) con fallas."
    exit 1
fi
echo "Todos los tests pasaron."
