import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { db, guardarMeta, leerMeta, type Perfil } from './db';
import { asegurarDispositivo } from './operaciones';
import { iniciarSincronizacion, pedirSincronizacion } from './sync';
import { supabase } from './supabase';

interface EstadoSesion {
  cargando: boolean;
  session: Session | null;
  perfil: Perfil | null;
  errorPerfil: string | null;
}

const Contexto = createContext<EstadoSesion>({
  cargando: true,
  session: null,
  perfil: null,
  errorPerfil: null,
});

export const useSesion = () => useContext(Contexto);

async function resolverPerfil(userId: string): Promise<Perfil | null> {
  const clave = `perfil:${userId}`;
  const { data, error } = await supabase
    .from('perfiles')
    .select('user_id,tenant_id,sede_id,rol,nombre')
    .eq('user_id', userId)
    .maybeSingle();

  // Sin conexión se trabaja con el último perfil conocido.
  if (error || !data) return (await leerMeta<Perfil>(clave)) ?? null;

  let sedeId = data.sede_id as string | null;
  if (!sedeId) {
    // El admin no tiene sede fija: el kiosco opera en la primera de su tenant.
    const { data: sede } = await supabase.from('sedes').select('id').order('creado_en').limit(1).maybeSingle();
    sedeId = sede?.id ?? null;
  }
  if (!sedeId) return null;

  const perfil: Perfil = { ...data, sede_id: sedeId };
  await guardarMeta(clave, perfil);
  return perfil;
}

export function ProveedorSesion({ children }: { children: ReactNode }) {
  const [estado, setEstado] = useState<EstadoSesion>({
    cargando: true,
    session: null,
    perfil: null,
    errorPerfil: null,
  });

  useEffect(() => {
    let vigente = true;

    async function aplicar(session: Session | null) {
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
        errorPerfil: perfil ? null : 'Este usuario no tiene un perfil activo.',
      });
      if (perfil) {
        await asegurarDispositivo(perfil);
        pedirSincronizacion();
      }
    }

    void supabase.auth.getSession().then(({ data }) => aplicar(data.session));

    const { data: sub } = supabase.auth.onAuthStateChange((evento, session) => {
      // Se difiere: llamar a Supabase dentro de este callback puede trabar el cliente de Auth.
      if (evento === 'SIGNED_IN' || evento === 'SIGNED_OUT') {
        setTimeout(() => void aplicar(session), 0);
      }
    });

    iniciarSincronizacion();
    return () => {
      vigente = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  return <Contexto.Provider value={estado}>{children}</Contexto.Provider>;
}

/** Borra los datos locales para que el próximo usuario no herede los del anterior. */
export async function cerrarSesion() {
  await supabase.auth.signOut();
  await Promise.all(db.tables.map((t) => t.clear()));
}
