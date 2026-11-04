// Configuración de la aprobación de órdenes de compra.
import { supabase } from './supabase';

export type AlcanceRegla = 'EMPRESA' | 'RUBRO' | 'CATEGORIA' | 'PRODUCTO';
export type ModoRegla = 'NUNCA' | 'SIEMPRE' | 'POR_MONTO';

export interface ReglaAprobacion {
  id: string;
  alcance: AlcanceRegla;
  alcance_id: string | null;
  modo: ModoRegla;
  monto_umbral: number | null;
  nivel_requerido: number;
}
export interface OpcionCatalogo {
  id: string;
  nombre: string;
}
export interface RolLimite {
  id: string;
  nombre: string;
  limite_monto_sin_aprobacion: number | null;
}
export interface DatosReglas {
  reglas: ReglaAprobacion[];
  rubros: OpcionCatalogo[];
  categorias: OpcionCatalogo[];
  productos: OpcionCatalogo[];
  roles: RolLimite[];
  permitirAutoaprobacion: boolean;
}

function exigir<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message);
  return r.data as T;
}

export async function traerDatosReglas(): Promise<DatosReglas> {
  const [reglas, rubros, categorias, productos, roles, config] = await Promise.all([
    supabase
      .from('reglas_aprobacion')
      .select('id,alcance,alcance_id,modo,monto_umbral,nivel_requerido')
      .eq('activa', true),
    supabase.from('rubros').select('id,nombre').eq('activo', true).order('orden').order('nombre'),
    supabase.from('categorias').select('id,nombre,rubros(nombre)').eq('activo', true).order('nombre'),
    supabase.from('productos').select('id,nombre').eq('activo', true).order('nombre'),
    supabase
      .from('roles')
      .select('id,nombre,limite_monto_sin_aprobacion')
      .eq('activo', true)
      .order('nombre'),
    supabase.from('configuracion_empresa').select('permitir_autoaprobacion').maybeSingle(),
  ]);
  return {
    reglas: exigir(reglas) as ReglaAprobacion[],
    rubros: exigir(rubros) as OpcionCatalogo[],
    categorias: (
      exigir(categorias) as unknown as Array<{ id: string; nombre: string; rubros: { nombre: string } | null }>
    ).map((c) => ({ id: c.id, nombre: c.rubros ? `${c.rubros.nombre} · ${c.nombre}` : c.nombre })),
    productos: exigir(productos) as OpcionCatalogo[],
    roles: exigir(roles) as RolLimite[],
    permitirAutoaprobacion: exigir(config)?.permitir_autoaprobacion ?? true,
  };
}

async function llamar(nombre: string, args: Record<string, unknown>) {
  const { error } = await supabase.rpc(nombre, args);
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

export const guardarRegla = (
  alcance: AlcanceRegla,
  alcanceId: string | null,
  modo: ModoRegla,
  montoUmbral: number | null,
  nivel: number,
) =>
  llamar('guardar_regla_aprobacion', {
    p_alcance: alcance,
    p_alcance_id: alcanceId,
    p_modo: modo,
    p_monto_umbral: montoUmbral,
    p_nivel_requerido: nivel,
  });

/** Desactivarla hace que los ítems vuelvan a la regla del nivel superior. */
export const quitarRegla = (r: ReglaAprobacion) =>
  llamar('guardar_regla_aprobacion', {
    p_alcance: r.alcance,
    p_alcance_id: r.alcance_id,
    p_modo: r.modo,
    p_monto_umbral: r.monto_umbral,
    p_nivel_requerido: r.nivel_requerido,
    p_activa: false,
  });

export const fijarAutoaprobacion = (permitir: boolean) => llamar('fijar_autoaprobacion', { p_permitir: permitir });

export const fijarLimiteRol = (rolId: string, limite: number | null) =>
  llamar('fijar_limite_rol', { p_rol_id: rolId, p_limite: limite });
