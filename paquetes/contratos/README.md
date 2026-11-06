# @eskemia/contratos

Tipos de la base y esquemas de formularios, compartidos por `cliente-api` y `apps/web`.

- `src/base.generada.ts`: tipos del esquema `api`, **generados**. No se editan a mano.
  Regenerar después de cada migración que cambie `api`, con el stack levantado:
  `pnpm --filter @eskemia/contratos generar`.
- `src/index.ts`: alias cortos (`Fila<'productos'>`, `Argumentos<'abrir_recepcion'>`,
  `Resultado<…>`, `Enum<…>`).
- `src/formularios.ts`: esquemas Zod con las mismas reglas que las precondiciones de las RPC.
