// Eskemia · Sesión (Supabase Auth).
//
// Qué hace: ingreso, salida, sesión actual y aviso de cambios de sesión.
// Dónde encaja: dominio "auth" de la Etapa 3. Registro, verificación y recuperación se
// suman acá en la Etapa 4.

import type { Session } from '@supabase/supabase-js';
import { cliente } from './cliente';
import { aErrorApi } from './errores';

/** Sesión de Supabase Auth. Se reexporta para que la app no importe supabase-js. */
export type Sesion = Session;

/** Eventos de sesión que le interesan a la app. */
export type EventoSesion = 'INGRESO' | 'SALIDA' | 'OTRO';

/** Ingresa con email y contraseña. Lanza ErrorApi si las credenciales no son válidas. */
export async function ingresar(email: string, contrasena: string): Promise<Sesion> {
  const { data, error } = await cliente().auth.signInWithPassword({ email, password: contrasena });
  if (error) throw aErrorApi(error);
  return data.session;
}

/** Cierra la sesión en este dispositivo. */
export async function salir(): Promise<void> {
  const { error } = await cliente().auth.signOut();
  if (error) throw aErrorApi(error);
}

/** Sesión guardada en el dispositivo, o null. No requiere conexión. */
export async function sesionActual(): Promise<Sesion | null> {
  const { data } = await cliente().auth.getSession();
  return data.session;
}

/**
 * Avisa cuando la persona ingresa o sale. Devuelve la función para dejar de escuchar.
 * El aviso se difiere: llamar a Supabase dentro del callback de Auth puede trabarlo.
 */
export function alCambiarSesion(avisar: (evento: EventoSesion, sesion: Sesion | null) => void): () => void {
  const { data } = cliente().auth.onAuthStateChange((evento, sesion) => {
    const traducido: EventoSesion =
      evento === 'SIGNED_IN' ? 'INGRESO' : evento === 'SIGNED_OUT' ? 'SALIDA' : 'OTRO';
    setTimeout(() => avisar(traducido, sesion), 0);
  });
  return () => data.subscription.unsubscribe();
}
