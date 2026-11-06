// Eskemia · Cliente Supabase único.
//
// Qué hace: crea UNA instancia de supabase-js apuntada al esquema api (el único que
// expone PostgREST) y la entrega al resto del paquete. La app la inicia una vez al
// arrancar con iniciarCliente(); ningún otro paquete crea clientes.
// Dónde encaja: CLAUDE.md, "Ningún archivo fuera de paquetes/cliente-api importa
// @supabase/supabase-js" (lo controla ESLint). Nunca recibe la service_role: solo la clave
// pública, y la seguridad la ponen RLS y las RPC.

import { createClient } from '@supabase/supabase-js';
import type { Database, NombreRpc } from '@eskemia/contratos';
import type { ErrorCrudo } from './errores';

/** Bucket de Storage con las fotos y firmas de las recepciones. */
export const BUCKET_ADJUNTOS = 'adjuntos';

const crear = (url: string, clave: string) =>
  createClient<Database, 'api'>(url, clave, {
    db: { schema: 'api' },
    auth: { persistSession: true, autoRefreshToken: true },
  });

/** Tipo del cliente tipado contra el esquema api. */
export type ClienteEskemia = ReturnType<typeof crear>;

let instancia: ClienteEskemia | null = null;

/** Configuración del cliente: URL del gateway de Supabase y clave pública (publishable). */
export interface ConfiguracionCliente {
  url: string;
  clave: string;
}

/**
 * Crea el cliente único. Se llama una sola vez, al arrancar la app; llamarla de nuevo
 * no crea otra instancia.
 */
export function iniciarCliente(config: ConfiguracionCliente): void {
  if (instancia) return;
  if (!config.url || !config.clave) {
    throw new Error('Falta la URL o la clave pública de Supabase para iniciar el cliente.');
  }
  instancia = crear(config.url, config.clave);
}

/** Devuelve el cliente único. Falla si la app no llamó antes a iniciarCliente(). */
export function cliente(): ClienteEskemia {
  if (!instancia) throw new Error('cliente-api: falta llamar a iniciarCliente() al arrancar la app.');
  return instancia;
}

/**
 * Llama a una RPC con argumentos sin tipar. Solo para dos casos: parámetros que aceptan
 * null en la base aunque los tipos generados no lo digan (p_sede_id nulo = todas las
 * sedes), y la cola offline del kiosco, que guarda los argumentos en IndexedDB. El nombre
 * sí se valida contra el esquema api.
 */
export async function rpcLibre(
  nombre: NombreRpc,
  args: Record<string, unknown>,
): Promise<{ data: unknown; error: ErrorCrudo | null }> {
  const c = cliente();
  const llamar = c.rpc.bind(c) as unknown as (
    n: string,
    a: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: ErrorCrudo | null }>;
  return llamar(nombre, args);
}
