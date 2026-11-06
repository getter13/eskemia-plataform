// Bandeja de aprobación de órdenes de compra.
import { formatoMoneda } from './catalogo';
import { supabase } from './supabase';

interface ReglaAplicada {
  alcance: 'EMPRESA' | 'RUBRO' | 'CATEGORIA' | 'PRODUCTO';
  modo: 'SIEMPRE' | 'POR_MONTO';
  monto_umbral: number | null;
}

export interface OrdenBandeja {
  id: string;
  numero: string;
  sede: string;
  proveedor: string;
  emisor: string | null;
  creado_en: string;
  total_estimado: number;
  nivel_requerido: number;
  reglas_aplicadas: {
    excede_limite_rol?: boolean;
    limite_rol?: number | null;
    reglas_aplicadas?: ReglaAplicada[];
  };
  items: Array<{
    id: string;
    producto: string;
    sku: string | null;
    presentacion: string;
    cantidad: number;
    subtotal: number;
    disparo_aprobacion: boolean;
  }>;
}

const ALCANCE: Record<ReglaAplicada['alcance'], string> = {
  EMPRESA: 'de la empresa',
  RUBRO: 'del rubro',
  CATEGORIA: 'de la categoría',
  PRODUCTO: 'del producto',
};

/** Por qué esta orden necesita aprobación, en palabras. */
export function motivoAprobacion(o: OrdenBandeja): string {
  const motivos = (o.reglas_aplicadas.reglas_aplicadas ?? []).map((r) =>
    r.modo === 'POR_MONTO' && r.monto_umbral !== null
      ? `Supera ${formatoMoneda(r.monto_umbral)} en la regla ${ALCANCE[r.alcance]}`
      : `Regla ${ALCANCE[r.alcance]}: siempre se aprueba`,
  );
  if (o.reglas_aplicadas.excede_limite_rol && o.reglas_aplicadas.limite_rol != null) {
    motivos.push(`Supera el límite de ${formatoMoneda(o.reglas_aplicadas.limite_rol)} del rol`);
  }
  return `${motivos.join('. ') || 'Requiere aprobación'}. Nivel ${o.nivel_requerido}.`;
}

export async function traerBandeja(): Promise<OrdenBandeja[]> {
  const { data, error } = await supabase.rpc('bandeja_aprobacion');
  if (error) throw new Error(error.message);
  return (data ?? []) as OrdenBandeja[];
}

async function llamar(nombre: string, args: Record<string, unknown>) {
  const { error } = await supabase.rpc(nombre, args);
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

export const aprobarOc = (id: string) => llamar('aprobar_oc', { p_oc_id: id });

export const rechazarOc = (id: string, motivo: string) =>
  llamar('rechazar_oc', { p_oc_id: id, p_motivo: motivo });
