# @eskemia/tokens

Tokens del sistema de diseño **Eskemia v2** (aprobado por el CEO el 06/11/2026).

- `tokens.json`: **fuente de verdad** (colores por uso, Manrope, escala tipográfica,
  espaciado, radios, sombras). Se cambia acá y solo acá.
- `tokens.css`: **generado** con `pnpm --filter @eskemia/tokens generar`. No se edita a mano;
  el CI lo regenera y falla si difiere.
- `pnpm --filter @eskemia/tokens revisar`: lint que falla con colores, familias, tamaños,
  radios, sombras o espaciados escritos a mano en la app (ver excepciones en el script).

La app lo importa con `import '@eskemia/tokens/tokens.css'`. Reglas de uso: sección
"Estética v2" del `CLAUDE.md`.
