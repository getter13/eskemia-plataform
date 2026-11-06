// Eskemia · @eskemia/cliente-api: única puerta a Supabase.
//
// Qué hace: reúne el cliente único y las funciones por dominio (auth, organizaciones,
// miembros, compras, recepcion). Cada función documenta qué RPC o vista usa y qué exige.
// Dónde encaja: CLAUDE.md, "Ningún archivo fuera de paquetes/cliente-api importa
// @supabase/supabase-js" (regla de ESLint en la raíz). Salas llega con su módulo, en la
// Etapa 10: hoy colab no expone vistas ni RPC.

export { BUCKET_ADJUNTOS, iniciarCliente, type ConfiguracionCliente } from './cliente';
export { ErrorApi, type CodigoNegocio } from './errores';
export * from './auth';
export * from './organizaciones';
export * from './miembros';
export * from './compras/catalogo';
export * from './compras/ordenes';
export * from './compras/aprobacion';
export * from './recepcion/kiosco';
export * from './recepcion/back';
