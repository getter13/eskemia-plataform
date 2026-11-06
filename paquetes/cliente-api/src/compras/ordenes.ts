// Eskemia · Compras: órdenes de compra.
//
// Qué hace: lista y detalla órdenes (con datos de contacto del proveedor, ítems, saldos y
// recepciones), y las envía, anula o cierra por RPC. Avisa en tiempo real cuando cambian.
// Dónde encaja: dominio "compras" de la Etapa 3. Lo que cada persona ve lo decide RLS:
// quien no tiene compras.oc.ver_todas ve solo sus órdenes.

import { cliente } from '../cliente';
import { exigir, sinError } from '../errores';

/** Estados de una orden de compra. */
export type EstadoOc =
  | 'PENDIENTE_APROBACION'
  | 'APROBADA'
  | 'RECHAZADA'
  | 'ENVIADA'
  | 'RECIBIDA_PARCIAL'
  | 'RECIBIDA'
  | 'CERRADA'
  | 'ANULADA';

/** Canal por el que se mandó la orden al proveedor. */
export type CanalEnvio = 'MANUAL' | 'WHATSAPP' | 'EMAIL';

/** Datos de contacto del proveedor de una orden. */
export interface ContactoProveedor {
  nombre: string;
  codigo: string | null;
  cuit: string;
  telefono_whatsapp: string | null;
  email: string | null;
}

/** Orden de compra para listados y encabezado del detalle. */
export interface OrdenResumen {
  id: string;
  numero: string;
  estado: EstadoOc;
  total_estimado: number;
  creado_en: string;
  aprobada_en: string | null;
  enviada_en: string | null;
  fecha_entrega_estimada: string | null;
  motivo_rechazo: string | null;
  motivo_cierre: string | null;
  proveedores: ContactoProveedor | null;
}

/** Ítem de una orden, con el snapshot de precio y presentación. */
export interface ItemOrden {
  id: string;
  producto_nombre: string;
  sku: string | null;
  presentacion_nombre: string;
  cantidad: number;
  precio_unitario: number | null;
  subtotal: number;
  disparo_aprobacion: boolean;
}

/** Pedido contra recibido de un producto de la orden, en unidades de stock. */
export interface SaldoOrden {
  producto_id: string;
  producto_nombre: string;
  cant_pedida: number;
  cant_recibida: number;
}

/** Estados de una recepción de mercadería. */
export type EstadoRecepcion =
  | 'ABIERTA'
  | 'EN_CONTROL'
  | 'CERRADA_OK'
  | 'CERRADA_CON_DIFERENCIAS'
  | 'VALIDADA'
  | 'INGRESADA_A_SISTEMA'
  | 'RECHAZADA';

/** Recepción hecha sobre una orden. */
export interface RecepcionDeOrden {
  id: string;
  nro_remito: string;
  estado: EstadoRecepcion;
  abierta_en: string;
}

const COLUMNAS =
  'id,numero,estado,total_estimado,creado_en,aprobada_en,enviada_en,fecha_entrega_estimada,motivo_rechazo,motivo_cierre,proveedor_id';

/** Agrega los datos de contacto del proveedor a cada orden (una sola consulta extra). */
async function conProveedores(filas: Array<Record<string, unknown>>): Promise<OrdenResumen[]> {
  const ids = [...new Set(filas.map((f) => f.proveedor_id as string))];
  const proveedores = ids.length
    ? exigir(
        await cliente().from('proveedores').select('id,nombre,codigo,cuit,telefono_whatsapp,email').in('id', ids),
      )
    : [];
  const porId = new Map(proveedores.map((p) => [p.id, p]));
  return filas.map(({ proveedor_id, ...orden }) => {
    const p = porId.get(proveedor_id as string);
    return {
      ...(orden as Omit<OrdenResumen, 'proveedores'>),
      total_estimado: Number(orden.total_estimado ?? 0),
      proveedores: p ? (p as ContactoProveedor) : null,
    };
  });
}

/** Órdenes de la organización que la cuenta puede ver, las más nuevas primero (hasta 500). */
export async function ordenes(organizacionId: string): Promise<OrdenResumen[]> {
  const filas = exigir(
    await cliente()
      .from('ordenes_compra')
      .select(COLUMNAS)
      .eq('organizacion_id', organizacionId)
      .order('creado_en', { ascending: false })
      .limit(500),
  );
  return conProveedores(filas as Array<Record<string, unknown>>);
}

/** Detalle de una orden: encabezado, ítems, saldos por producto y recepciones. */
export async function orden(id: string) {
  const c = cliente();
  const [encabezado, items, saldos, recepciones] = await Promise.all([
    c.from('ordenes_compra').select(COLUMNAS).eq('id', id).maybeSingle(),
    c.from('oc_items')
      .select('id,producto_nombre,sku,presentacion_nombre,cantidad,precio_unitario,subtotal,disparo_aprobacion')
      .eq('oc_id', id)
      .order('producto_nombre'),
    c.from('oc_saldos').select('producto_id,producto_nombre,cant_pedida,cant_recibida').eq('oc_id', id).order('producto_nombre'),
    c.from('recepciones').select('id,nro_remito,estado,abierta_en').eq('oc_id', id).order('abierta_en'),
  ]);
  const fila = exigir(encabezado);
  return {
    orden: fila ? (await conProveedores([fila as Record<string, unknown>]))[0] : null,
    items: exigir(items) as ItemOrden[],
    saldos: exigir(saldos) as SaldoOrden[],
    recepciones: exigir(recepciones) as RecepcionDeOrden[],
  };
}

/** Marca la orden como enviada al proveedor. Solo si está aprobada; idempotente. */
export async function marcarOcEnviada(id: string, canal: CanalEnvio): Promise<EstadoOc> {
  return exigir(await cliente().rpc('marcar_oc_enviada', { p_oc_id: id, p_canal: canal })) as EstadoOc;
}

/** Anula una orden sin recepciones. Exige compras.oc.anular y motivo. */
export async function anularOc(id: string, motivo: string): Promise<void> {
  sinError(await cliente().rpc('anular_oc', { p_oc_id: id, p_motivo: motivo }));
}

/** Da por cerrado lo que falta recibir. Exige compras.oc.cerrar_saldo y motivo. */
export async function cerrarSaldoOc(id: string, motivo: string): Promise<void> {
  sinError(await cliente().rpc('cerrar_saldo_oc', { p_oc_id: id, p_motivo: motivo }));
}

/**
 * Avisa cada vez que cambia una orden de la organización (Realtime, respeta RLS).
 * Devuelve la función para dejar de escuchar.
 */
export function alCambiarOrdenes(organizacionId: string, avisar: () => void): () => void {
  const c = cliente();
  const canal = c
    .channel(`ordenes-compra-${organizacionId}`)
    .on(
      'postgres_changes',
      { event: '*', schema: 'compras', table: 'ordenes_compra', filter: `organizacion_id=eq.${organizacionId}` },
      () => avisar(),
    )
    .subscribe();
  return () => {
    void c.removeChannel(canal);
  };
}
