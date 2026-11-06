// Eskemia · Bandeja de aprobación de órdenes de compra.
//
// Qué hace: trae la bandeja de la organización actual por @eskemia/cliente-api, aprueba
// o rechaza, y explica en palabras por qué cada orden necesita aprobación.
// Dónde encaja: pantalla Compras > Aprobaciones.
import {
  aprobarOc as aprobar,
  bandejaAprobacion,
  rechazarOc as rechazar,
  type OrdenBandeja,
  type ReglaAplicada,
} from '@eskemia/cliente-api';
import { formatoMoneda } from './catalogo';
import { organizacionActual } from './db';

export type { OrdenBandeja };

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

/** Órdenes que la cuenta puede aprobar en la organización actual. */
export async function traerBandeja(): Promise<OrdenBandeja[]> {
  return bandejaAprobacion(await organizacionActual());
}

/** Aprueba una orden pendiente. */
export const aprobarOc = (id: string) => aprobar(id);

/** Rechaza una orden pendiente con motivo. */
export const rechazarOc = (id: string, motivo: string) => rechazar(id, motivo);
