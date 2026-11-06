# db · Base de datos de Eskemia

Línea base v1 (Etapa 2 del plan, `docs/planes/plan-ejecucion-esqueleto.md`).

| Carpeta | Qué tiene |
|---|---|
| `migraciones/` | SQL que se aplica en orden, una sola vez, solo hacia adelante. |
| `semillas/` | Catálogos globales idempotentes: módulos, permisos y puestos. Se corren siempre. |
| `pruebas/` | Tests pgTAP. Cada archivo corre en una transacción con ROLLBACK. |
| `scripts/` | `aplicar.sh`, `reset.sh` (solo local y CI) y `pruebas.sh`. |
| `legado/` | Migraciones del MVP (Supabase cloud). Solo lectura, como referencia. |

## Uso (con el stack de `infra/compose` levantado)

```sh
sh db/scripts/aplicar.sh       # migraciones pendientes + semillas
sh db/scripts/reset.sh         # BORRA la base local y la rearma (pide confirmación)
sh db/scripts/pruebas.sh       # todos los tests; o pasá archivos puntuales
```

## Tests

- `00_estructura`: RLS forzado, `organizacion_id NOT NULL`, políticas con `es_miembro`,
  sin escrituras directas, vistas `security_invoker`. Una tabla nueva que no cumpla lo hace fallar.
- `01_aislamiento`: la organización A no ve ni opera nada de B, en todas las tablas y vistas.
- `02_nucleo_rpc`: organizaciones, invitaciones, suspensión, titularidad, Inicio, módulos.
- `03` a `12`: los 10 tests de Compras y Recepción portados del legado, autónomos:
  cada uno arma su organización con `pruebas.escenario()` (ver `pruebas/_ayudantes.sql`).

## Archivos de más de ~300 líneas (justificación)

Las migraciones `…0300_nucleo_funciones`, `…0500_nucleo_rpc`, `…0600_compras_tablas`,
`…0800_compras_funciones`, `…0900_compras_rpc` y `…1000_recepcion_rpc` superan las
300 líneas. Cada una agrupa un esquema y un tipo de objeto, y cada RPC lleva su
cabecera obligatoria (qué hace, precondiciones, permisos y eventos). Partirlas
no aclararía nada y dejaría el orden de aplicación más frágil. Además, una migración
aplicada no se edita, así que el límite rige para las nuevas: un cambio, una migración chica.
