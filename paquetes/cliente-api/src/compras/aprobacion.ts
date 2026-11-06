// Eskemia · Compras: bandeja de aprobación y configuración de reglas.
//
// Qué hace: lee la bandeja de órdenes para aprobar (según el nivel de quien la abre), las
// aprueba o rechaza, y administra reglas de aprobación, autoaprobación y límites por rol.
// Dónde encaja: dominio "compras" de la Etapa 3. Aprobar exige compras.oc.aprobar con
// nivel suficiente; configurar, compras.aprobacion.configurar.

import { cliente, rpcLibre } from '../cliente';
import { exigir, sinError } from '../errores';

/** Alcance de una regla de aprobación. EMPRESA = toda la organización. */
export type AlcanceRegla = 'EMPRESA' | 'RUBRO' | 'CATEGORIA' | 'PRODUCTO';
/** Cuándo una regla pide aprobación. */
export type ModoRegla = 'NUNCA' | 'SIEMPRE' | 'POR_MONTO';

/** Regla que disparó la aprobación de una orden. */
export interface ReglaAplicada {
  alcance: AlcanceRegla;
  modo: 'SIEMPRE' | 'POR_MONTO';
  monto_umbral: number | null;
}

/** Orden en la bandeja de aprobación. */
export interface OrdenBandeja {
  id: string;
  numero: string;
  sede: string;
  proveedor: string;
  emisor: string | null;
  creado_en: string;
  total_estimado: number;
  nivel_requerido: number;
  reglas_aplicadas: { excede_limite_rol?: boolean; limite_rol?: number | null; reglas_aplicadas?: ReglaAplicada[] };
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

/** Regla de aprobación activa. */
export interface ReglaAprobacion {
  id: string;
  alcance: AlcanceRegla;
  alcance_id: string | null;
  modo: ModoRegla;
  monto_umbral: number | null;
  nivel_requerido: number;
}

/** Opción para elegir el alcance de una regla. */
export interface OpcionCatalogo {
  id: string;
  nombre: string;
}

/** Rol con su límite de monto sin aprobación. */
export interface RolLimite {
  id: string;
  nombre: string;
  limite_monto_sin_aprobacion: number | null;
}

/** Todo lo que necesita la pantalla de reglas. */
export interface DatosReglas {
  reglas: ReglaAprobacion[];
  rubros: OpcionCatalogo[];
  categorias: OpcionCatalogo[];
  productos: OpcionCatalogo[];
  roles: RolLimite[];
  permitirAutoaprobacion: boolean;
}

/** Órdenes que la cuenta puede aprobar (nunca las propias si no hay autoaprobación). */
export async function bandejaAprobacion(organizacionId: string): Promise<OrdenBandeja[]> {
  const filas = exigir(await cliente().rpc('bandeja_aprobacion', { p_organizacion_id: organizacionId }));
  return filas as unknown as OrdenBandeja[];
}

/** Aprueba una orden pendiente. Idempotente. */
export async function aprobarOc(id: string): Promise<void> {
  sinError(await cliente().rpc('aprobar_oc', { p_oc_id: id }));
}

/** Rechaza una orden pendiente con motivo. */
export async function rechazarOc(id: string, motivo: string): Promise<void> {
  sinError(await cliente().rpc('rechazar_oc', { p_oc_id: id, p_motivo: motivo }));
}

/** Reglas activas, opciones de alcance, roles con límite y la autoaprobación. */
export async function datosReglas(organizacionId: string): Promise<DatosReglas> {
  const c = cliente();
  const [reglas, rubros, categorias, productos, roles, config] = await Promise.all([
    c.from('reglas_aprobacion').select('id,alcance,alcance_id,modo,monto_umbral,nivel_requerido')
      .eq('organizacion_id', organizacionId).eq('activa', true),
    c.from('rubros').select('id,nombre').eq('organizacion_id', organizacionId).eq('activo', true).order('orden').order('nombre'),
    c.from('categorias').select('id,nombre,rubro_id').eq('organizacion_id', organizacionId).eq('activo', true).order('nombre'),
    c.from('productos').select('id,nombre').eq('organizacion_id', organizacionId).eq('activo', true).order('nombre'),
    c.from('roles').select('id,nombre,limite_monto_sin_aprobacion')
      .eq('organizacion_id', organizacionId).eq('activo', true).order('nombre'),
    c.from('configuracion_compras').select('permitir_autoaprobacion').eq('organizacion_id', organizacionId).maybeSingle(),
  ]);
  const listaRubros = exigir(rubros) as OpcionCatalogo[];
  const nombreRubro = new Map(listaRubros.map((r) => [r.id, r.nombre]));
  return {
    reglas: exigir(reglas) as ReglaAprobacion[],
    rubros: listaRubros,
    categorias: exigir(categorias).map((cat) => ({
      id: cat.id as string,
      nombre: nombreRubro.has(cat.rubro_id as string) ? `${nombreRubro.get(cat.rubro_id as string)} · ${cat.nombre}` : (cat.nombre as string),
    })),
    productos: exigir(productos) as OpcionCatalogo[],
    roles: exigir(roles) as RolLimite[],
    // Sin fila de configuración rige el valor por defecto de la base: se permite.
    permitirAutoaprobacion: exigir(config)?.permitir_autoaprobacion ?? true,
  };
}

/** Crea o actualiza la regla de ese alcance (una por alcance). */
export async function guardarRegla(
  organizacionId: string,
  regla: Omit<ReglaAprobacion, 'id'> & { activa?: boolean },
): Promise<void> {
  // alcance_id y monto_umbral pueden ser null (regla de toda la organización, sin monto).
  sinError(
    await rpcLibre('guardar_regla_aprobacion', {
      p_organizacion_id: organizacionId,
      p_alcance: regla.alcance,
      p_alcance_id: regla.alcance_id,
      p_modo: regla.modo,
      p_monto_umbral: regla.monto_umbral,
      p_nivel_requerido: regla.nivel_requerido,
      p_activa: regla.activa ?? true,
    }),
  );
}

/** Desactiva una regla: sus ítems vuelven a la regla del nivel superior. */
export async function quitarRegla(organizacionId: string, regla: ReglaAprobacion): Promise<void> {
  await guardarRegla(organizacionId, { ...regla, activa: false });
}

/** Permite o no que quien emite apruebe sus propias órdenes si tiene el nivel. */
export async function fijarAutoaprobacion(organizacionId: string, permitir: boolean): Promise<void> {
  sinError(await cliente().rpc('fijar_autoaprobacion', { p_organizacion_id: organizacionId, p_permitir: permitir }));
}

/** Fija el monto que un rol puede pedir sin aprobación (null: sin límite). */
export async function fijarLimiteRol(rolId: string, limite: number | null): Promise<void> {
  sinError(await rpcLibre('fijar_limite_rol', { p_rol_id: rolId, p_limite: limite }));
}
