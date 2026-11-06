// Eskemia · Configuración de la aprobación de órdenes de compra.
//
// Qué hace: lee y guarda reglas de aprobación, autoaprobación y límites por rol de la
// organización actual, por @eskemia/cliente-api.
// Dónde encaja: pantalla Compras > Reglas. Exige compras.aprobacion.configurar.
import {
  datosReglas,
  fijarAutoaprobacion as fijarAuto,
  fijarLimiteRol as fijarLimite,
  guardarRegla as guardar,
  quitarRegla as quitar,
  type AlcanceRegla,
  type DatosReglas,
  type ModoRegla,
  type OpcionCatalogo,
  type ReglaAprobacion,
  type RolLimite,
} from '@eskemia/cliente-api';
import { organizacionActual } from './db';

export type { AlcanceRegla, DatosReglas, ModoRegla, OpcionCatalogo, ReglaAprobacion, RolLimite };

/** Reglas, opciones de alcance, roles y autoaprobación de la organización actual. */
export async function traerDatosReglas(): Promise<DatosReglas> {
  return datosReglas(await organizacionActual());
}

/** Crea o actualiza la regla de ese alcance. */
export async function guardarRegla(
  alcance: AlcanceRegla,
  alcanceId: string | null,
  modo: ModoRegla,
  montoUmbral: number | null,
  nivel: number,
) {
  await guardar(await organizacionActual(), {
    alcance,
    alcance_id: alcanceId,
    modo,
    monto_umbral: montoUmbral,
    nivel_requerido: nivel,
  });
}

/** Desactivarla hace que los ítems vuelvan a la regla del nivel superior. */
export async function quitarRegla(r: ReglaAprobacion) {
  await quitar(await organizacionActual(), r);
}

/** Permite o no aprobar las propias órdenes con nivel suficiente. */
export async function fijarAutoaprobacion(permitir: boolean) {
  await fijarAuto(await organizacionActual(), permitir);
}

/** Monto que un rol puede pedir sin aprobación (null: sin límite). */
export const fijarLimiteRol = (rolId: string, limite: number | null) => fijarLimite(rolId, limite);
