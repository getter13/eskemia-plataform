// Eskemia · Organizaciones, sedes y permisos de la cuenta actual.
//
// Qué hace: lee a qué organizaciones pertenece la cuenta, sus sedes y qué permisos tiene
// en cada una. Los permisos sirven para decidir qué mostrar; quien autoriza es la base.
// Dónde encaja: dominio "organizaciones" de la Etapa 3. Crear organización, selector y
// /o/:org llegan en la Etapa 5.

import type { Fila } from '@eskemia/contratos';
import { cliente } from './cliente';
import { exigir } from './errores';

/** Organización de la que la cuenta es miembro. */
export type MiOrganizacion = Fila<'mis_organizaciones'>;

/** Permiso asignado. sede_id nulo: vale en todas las sedes. */
export interface PermisoAsignado {
  permiso: string;
  sede_id: string | null;
}

/** Sede de una organización. */
export interface Sede {
  id: string;
  nombre: string;
  codigo: string | null;
}

/** Datos personales de la cuenta actual. */
export type MiCuenta = Fila<'mi_cuenta'>;

/** Organizaciones donde la cuenta tiene membresía activa, por fecha de ingreso. */
export async function misOrganizaciones(): Promise<MiOrganizacion[]> {
  return exigir(
    await cliente().from('mis_organizaciones').select('*').eq('estado', 'ACTIVA').order('unida_en'),
  );
}

/** Permisos de la cuenta en la organización (omite los de módulos deshabilitados). */
export async function misPermisos(organizacionId: string): Promise<PermisoAsignado[]> {
  return exigir(await cliente().rpc('mis_permisos', { p_organizacion_id: organizacionId }));
}

/** Sedes de la organización que la cuenta alcanza, por nombre. */
export async function sedes(organizacionId: string): Promise<Sede[]> {
  const filas = exigir(
    await cliente().from('sedes').select('id,nombre,codigo').eq('organizacion_id', organizacionId).order('nombre'),
  );
  return filas as Sede[];
}

/** Datos de la cuenta actual, o null si todavía no existe su fila. */
export async function miCuenta(): Promise<MiCuenta | null> {
  return exigir(await cliente().from('mi_cuenta').select('*').maybeSingle());
}
