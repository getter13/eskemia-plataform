# @eskemia/cliente-api

Única puerta a Supabase: el único paquete que importa `@supabase/supabase-js`
(ESLint lo hace cumplir en todo el monorepo).

- `iniciarCliente({ url, clave })` una vez al arrancar la app, con la **clave pública**.
  Nunca la `service_role`.
- El cliente apunta al esquema `api` y está tipado con `@eskemia/contratos`.
- Todas las funciones lanzan `ErrorApi`, con `codigo` (SIN_PERMISO, PRECONDICION,
  NO_ENCONTRADO, MODULO_DESHABILITADO), un mensaje listo para mostrar y `transitorio`
  (si conviene reintentar).

| Dominio | Archivo |
|---|---|
| auth | `src/auth.ts` |
| organizaciones y sedes | `src/organizaciones.ts` |
| miembros y roles | `src/miembros.ts` |
| compras | `src/compras/` (catálogo, órdenes, aprobación) |
| recepción | `src/recepcion/` (kiosco y back) |
| salas | Etapa 10 |
