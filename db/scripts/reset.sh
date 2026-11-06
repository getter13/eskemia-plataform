#!/bin/sh
#
# Eskemia · Reconstruye la base local desde cero (DESTRUCTIVO).
#
# Qué hace: borra (en una sola transacción) los esquemas de Eskemia, los usuarios de
# Auth, los registros del bucket adjuntos y la cola de emails, y vuelve a aplicar todas
# las migraciones y semillas. Los archivos ya subidos quedan en
# infra/compose/volumes/storage: para borrarlos también, bajá el stack y borrá esa carpeta.
# Dónde encaja: entorno local y CI. Los datos locales son descartables (runbook, Plan B).
# NUNCA contra producción: se niega si ESKEMIA_ENTORNO=produccion.
#
# Uso: sh db/scripts/reset.sh      (pide confirmación)
#      sh db/scripts/reset.sh -y   (sin preguntar, para CI)

set -e
. "$(dirname "$0")/comun.sh"

if [ "${ESKEMIA_ENTORNO:-}" = "produccion" ]; then
    echo "Error: reset.sh no corre en producción." >&2
    exit 1
fi

if [ "$1" != "-y" ]; then
    printf "Esto BORRA todos los datos de la base local (%s). ¿Seguir? (s/N) " "$DB_CONTENEDOR"
    read -r respuesta
    case "$respuesta" in
        [sS]) ;;
        *) echo "Cancelado."; exit 1 ;;
    esac
fi

psql_admin -1 <<'SQL'
-- Storage protege sus tablas contra borrados directos; acá es intencional y local.
set local storage.allow_delete_query = 'true';
do $$
begin
  if exists (select 1 from pgmq.list_queues() where queue_name = 'emails') then
    perform pgmq.drop_queue('emails');
  end if;
end;
$$;
delete from storage.objects where bucket_id = 'adjuntos';
delete from storage.buckets where id = 'adjuntos';
drop schema if exists api, colab, recepcion, compras, nucleo, migraciones cascade;
drop trigger if exists crear_cuenta on auth.users;
delete from auth.users;
SQL

sh "$(dirname "$0")/aplicar.sh"
