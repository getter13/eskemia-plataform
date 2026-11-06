// Eskemia · Sesión y perfil de trabajo.
//
// Qué hace: escucha la sesión de Auth y arma el Perfil con el que trabaja la app:
// organización, sede, nombre y permisos. Sin señal, usa el último perfil guardado.
// Dónde encaja: envuelve toda la app (App.tsx). Hasta la Etapa 5 (organización en la URL)
// se trabaja con la primera organización activa de la cuenta y su primera sede.

import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import {
  alCambiarSesion,
  miCuenta,
  misOrganizaciones,
  misPermisos,
  salir,
  sedes,
  sesionActual,
  type Sesion,
} from '@eskemia/cliente-api';
import { db, guardarMeta, leerMeta, tienePermiso, type Perfil } from './db';
import { useCarrito } from './carrito';
import { asegurarDispositivo } from './operaciones';
import { iniciarSincronizacion, pedirSincronizacion } from './sync';

interface EstadoSesion {
  cargando: boolean;
  session: Sesion | null;
  perfil: Perfil | null;
  errorPerfil: string | null;
}

const Contexto = createContext<EstadoSesion>({
  cargando: true,
  session: null,
  perfil: null,
  errorPerfil: null,
});

/** Sesión y perfil de trabajo actuales. */
export const useSesion = () => useContext(Contexto);

/** Perfil desde el servidor; null si la cuenta no tiene organización ni sede. */
async function perfilDelServidor(userId: string): Promise<Perfil | null> {
  const [organizaciones, cuenta] = await Promise.all([misOrganizaciones(), miCuenta()]);
  const organizacion = organizaciones[0];
  if (!organizacion?.id) return null;
  const [permisos, listaSedes] = await Promise.all([misPermisos(organizacion.id), sedes(organizacion.id)]);
  const sede = listaSedes[0];
  if (!sede) return null;
  return {
    user_id: userId,
    organizacion_id: organizacion.id,
    sede_id: sede.id,
    nombre: [cuenta?.nombre, cuenta?.apellido].filter(Boolean).join(' ') || 'Sin nombre',
    permisos,
  };
}

async function resolverPerfil(userId: string): Promise<Perfil | null> {
  const clave = `perfil:${userId}`;
  try {
    const perfil = await perfilDelServidor(userId);
    if (perfil) {
      await guardarMeta(clave, perfil);
      await guardarMeta('organizacion_actual', perfil.organizacion_id);
      await guardarMeta('sede_actual', perfil.sede_id);
    }
    return perfil;
  } catch {
    // Sin conexión se trabaja con el último perfil conocido.
    return (await leerMeta<Perfil>(clave)) ?? null;
  }
}

/** Provee la sesión y el perfil a toda la app, y arranca la sincronización. */
export function ProveedorSesion({ children }: { children: ReactNode }) {
  const [estado, setEstado] = useState<EstadoSesion>({
    cargando: true,
    session: null,
    perfil: null,
    errorPerfil: null,
  });

  useEffect(() => {
    let vigente = true;

    async function aplicar(session: Sesion | null) {
      if (!session) {
        if (vigente) setEstado({ cargando: false, session: null, perfil: null, errorPerfil: null });
        return;
      }
      const perfil = await resolverPerfil(session.user.id);
      if (!vigente) return;
      setEstado({
        cargando: false,
        session,
        perfil,
        errorPerfil: perfil ? null : 'Tu cuenta todavía no pertenece a ninguna organización con sedes.',
      });
      if (perfil && tienePermiso(perfil, 'recepcion.recepcion.operar')) {
        await asegurarDispositivo(perfil);
        pedirSincronizacion();
      }
    }

    void sesionActual().then(aplicar);
    const dejarDeEscuchar = alCambiarSesion((evento, session) => {
      if (evento !== 'OTRO') void aplicar(session);
    });

    iniciarSincronizacion();
    return () => {
      vigente = false;
      dejarDeEscuchar();
    };
  }, []);

  return <Contexto.Provider value={estado}>{children}</Contexto.Provider>;
}

/** Cierra la sesión y borra los datos locales para que la próxima persona no los herede. */
export async function cerrarSesion() {
  await salir();
  await Promise.all(db.tables.map((t) => t.clear()));
  useCarrito.getState().vaciar();
}
