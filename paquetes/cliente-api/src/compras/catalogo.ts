// Eskemia · Compras: catálogo del marketplace, evaluación de aprobación e importación.
//
// Qué hace: lee el catálogo de compras de una sede (productos con sus ofertas por
// proveedor y la regla de aprobación vigente), evalúa si una orden pediría aprobación y
// corre la importación CSV del catálogo (vista previa o aplicación, todo o nada).
// Dónde encaja: dominio "compras" de la Etapa 3. Cada RPC valida permiso y módulo.

import type { Json } from '@eskemia/contratos';
import { cliente } from '../cliente';
import { exigir } from '../errores';

/** Oferta de un proveedor para un producto, en una presentación. */
export interface Oferta {
  id: string;
  proveedor_id: string;
  proveedor: string;
  proveedor_codigo: string | null;
  monto_minimo: number | null;
  plazo_entrega_dias: number | null;
  presentacion_id: string;
  presentacion: string;
  factor: number;
  precio: number | null;
  preferido: boolean;
}

/** Producto del catálogo de compras con sus ofertas. */
export interface ProductoCatalogo {
  producto_id: string;
  sku: string | null;
  nombre: string;
  unidad_stock: 'UN' | 'KG' | 'LT';
  rubro_id: string | null;
  rubro: string | null;
  categoria_id: string | null;
  categoria: string | null;
  regla_modo: 'NUNCA' | 'SIEMPRE' | 'POR_MONTO' | null;
  regla_monto_umbral: number | null;
  ofertas: Oferta[];
}

/** Resultado de evaluar_aprobacion para un grupo de ítems. */
export interface EvaluacionOrden {
  requiere_aprobacion: boolean;
  estado: 'APROBADA' | 'PENDIENTE_APROBACION';
}

/** Tipos de archivo de la importación, en el orden en que se cargan. */
export type TipoImportacion = 'rubros' | 'categorias' | 'productos' | 'presentaciones' | 'proveedores' | 'precios';

/** Problema en una fila del archivo (fila 0: el archivo entero). */
export interface ErrorFila {
  fila: number;
  mensaje: string;
}

/** Resultado de importar_catalogo. */
export interface ResultadoImportacion {
  filas: number;
  creados: number;
  actualizados: number;
  errores: ErrorFila[];
  aplicado: boolean;
}

/** Catálogo de compras visible desde la sede (respeta el sector de quien pide). */
export async function catalogoCompras(sedeId: string): Promise<ProductoCatalogo[]> {
  const filas = exigir(await cliente().rpc('catalogo_compras', { p_sede_id: sedeId }));
  return filas as unknown as ProductoCatalogo[];
}

/** Evalúa si una orden con estos ítems pediría aprobación. No guarda nada. */
export async function evaluarAprobacion(
  sedeId: string,
  items: Array<{ producto_id: string; subtotal: number }>,
): Promise<EvaluacionOrden> {
  const r = exigir(await cliente().rpc('evaluar_aprobacion', { p_sede_id: sedeId, p_items: items as unknown as Json }));
  return r as unknown as EvaluacionOrden;
}

/**
 * Importa filas ya validadas en el front. Con aplicar=false es una vista previa: informa
 * qué crearía y los errores por fila sin guardar nada. Exige compras.catalogo.gestionar.
 */
export async function importarCatalogo(
  organizacionId: string,
  tipo: TipoImportacion,
  filas: Array<Record<string, unknown>>,
  aplicar: boolean,
): Promise<ResultadoImportacion> {
  const r = exigir(
    await cliente().rpc('importar_catalogo', {
      p_organizacion_id: organizacionId,
      p_tipo: tipo,
      p_filas: filas as unknown as Json,
      p_aplicar: aplicar,
    }),
  );
  return r as unknown as ResultadoImportacion;
}
