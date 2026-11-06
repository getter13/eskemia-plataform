#!/bin/sh
#
# Eskemia · Genera los tipos TypeScript del esquema api.
#
# Qué hace: le pide a postgres-meta (el servicio "meta" del stack de infra/compose, el
# mismo que usa Studio) los tipos de la base filtrados al esquema api, y los escribe en
# src/base.generada.ts. No hace falta el CLI de Supabase.
# Dónde encaja: Etapa 3. Correrlo después de cada migración que cambie el esquema api;
# el archivo generado se commitea y no se edita a mano.
#
# Uso (con el stack levantado): pnpm --filter @eskemia/contratos generar

set -e
cd "$(dirname "$0")/.."

CONTENEDOR="${META_CONTENEDOR:-supabase-meta}"
DESTINO="src/base.generada.ts"

tipos=$(docker exec "$CONTENEDOR" node -e '
  fetch("http://localhost:8080/generators/typescript?included_schemas=api")
    .then((r) => { if (!r.ok) throw new Error("postgres-meta respondió " + r.status); return r.text(); })
    .then((t) => process.stdout.write(t))
    .catch((e) => { console.error(e.message); process.exit(1); });
')

{
  echo "// Eskemia · Tipos del esquema api, GENERADOS por scripts/generar-tipos.sh."
  echo "// No editar a mano: se regeneran después de cada migración que cambie el esquema api."
  echo
  printf '%s\n' "$tipos"
} > "$DESTINO"

echo "Tipos generados en paquetes/contratos/$DESTINO ($(wc -l < "$DESTINO") líneas)."
