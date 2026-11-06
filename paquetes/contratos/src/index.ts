// Eskemia · @eskemia/contratos: tipos de la base y esquemas de formularios.
//
// Qué hace: reexporta los tipos generados del esquema api (base.generada.ts) con alias
// cortos, y los esquemas Zod que validan formularios en el front con las mismas reglas
// que las precondiciones de las RPC.
// Dónde encaja: lo usan paquetes/cliente-api (tipado del cliente) y apps/web (formularios).
// No importa nada de Supabase: son solo tipos y validaciones.

import type { Database } from './base.generada';

export type { Database, Json } from './base.generada';
export * from './formularios';

type Api = Database['api'];

/** Fila de una vista del esquema api, por nombre: Fila<'productos'>. */
export type Fila<V extends keyof Api['Views']> = Api['Views'][V]['Row'];

/** Argumentos de una RPC del esquema api, por nombre: Argumentos<'abrir_recepcion'>. */
export type Argumentos<F extends keyof Api['Functions']> = Api['Functions'][F]['Args'];

/** Lo que devuelve una RPC del esquema api, por nombre: Resultado<'confirmar_pedido'>. */
export type Resultado<F extends keyof Api['Functions']> = Api['Functions'][F]['Returns'];

/** Nombre de cualquier RPC del esquema api. */
export type NombreRpc = keyof Api['Functions'];

/** Valores de un enum de la base, por nombre: Enum<'estado_oc'>. */
export type Enum<E extends keyof Api['Enums']> = Api['Enums'][E];
