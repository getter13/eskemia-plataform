// Eskemia · Recepción: lo que necesita el kiosco.
//
// Qué hace: ejecuta las operaciones de la cola offline (cada RPC es idempotente por
// client_uuid o id generado en el dispositivo), sube fotos y firmas a Storage, y trae
// catálogos, órdenes pendientes y recepciones abiertas para trabajar sin señal.
// Dónde encaja: dominio "recepcion" de la Etapa 3; lo usa apps/web/src/lib/sync.ts.

import { BUCKET_ADJUNTOS, cliente, rpcLibre } from '../cliente';
import { aErrorApi, exigir } from '../errores';

/** RPC que el kiosco puede encolar mientras no hay señal. */
export type OperacionCola =
  | 'registrar_dispositivo'
  | 'alta_rapida_proveedor'
  | 'alta_rapida_producto'
  | 'abrir_recepcion'
  | 'registrar_adjunto'
  | 'registrar_lectura'
  | 'fijar_control_item'
  | 'iniciar_control'
  | 'cerrar_recepcion'
  | 'reabrir_recepcion'
  | 'confirmar_pedido';

/** Ejecuta una operación de la cola con los argumentos guardados. Lanza ErrorApi. */
export async function ejecutarOperacion(nombre: OperacionCola, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await rpcLibre(nombre, args);
  if (error) throw aErrorApi(error);
  return data;
}

/**
 * Sube una foto o firma. Si el archivo ya estaba, es el reintento de una subida que cortó
 * antes de registrarse: se da por buena.
 */
export async function subirAdjunto(ruta: string, archivo: Blob): Promise<void> {
  const { error } = await cliente()
    .storage.from(BUCKET_ADJUNTOS)
    .upload(ruta, archivo, { upsert: false, contentType: archivo.type });
  if (error && !/exists|duplicate/i.test(error.message)) throw aErrorApi(error);
}

const PAGINA = 1000;

/** Trae todas las filas de una vista de la organización, de a 1000. */
async function todas<T>(vista: 'categorias' | 'productos' | 'proveedores' | 'producto_codigos' | 'presentaciones',
  columnas: string, organizacionId: string): Promise<T[]> {
  const filas: T[] = [];
  for (let desde = 0; ; desde += PAGINA) {
    const r = await cliente()
      .from(vista)
      .select(columnas)
      .eq('organizacion_id', organizacionId)
      .range(desde, desde + PAGINA - 1);
    const pagina = exigir(r) as unknown as T[];
    filas.push(...pagina);
    if (pagina.length < PAGINA) return filas;
  }
}

/** Producto tal como lo usa el kiosco. */
export interface ProductoKiosco {
  id: string;
  gtin: string | null;
  nombre: string;
  tipo_medida: 'UNIDAD' | 'PESO';
  requiere_lote: boolean;
  requiere_vencimiento: boolean;
  pendiente_validacion: boolean;
  categoria_id: string | null;
}

/** Código de barras: qué producto y presentación identifica y cuántas unidades trae. */
export interface CodigoKiosco {
  codigo_busqueda: string;
  producto_id: string;
  presentacion: string;
  factor: number;
}

/** Catálogos completos para escanear y dar de alta sin señal. */
export async function catalogosKiosco(organizacionId: string) {
  const [categorias, productos, proveedores, codigos, presentaciones] = await Promise.all([
    todas<{ id: string; nombre: string; orden: number }>('categorias', 'id,nombre,orden', organizacionId),
    todas<ProductoKiosco>('productos',
      'id,gtin,nombre,tipo_medida,requiere_lote,requiere_vencimiento,pendiente_validacion,categoria_id', organizacionId),
    todas<{ id: string; nombre: string; cuit: string }>('proveedores', 'id,nombre,cuit', organizacionId),
    todas<{ producto_id: string; codigo_busqueda: string; presentacion_id: string | null }>(
      'producto_codigos', 'producto_id,codigo_busqueda,presentacion_id', organizacionId),
    todas<{ id: string; nombre: string; factor: number }>('presentaciones', 'id,nombre,factor', organizacionId),
  ]);
  const presentacion = new Map(presentaciones.map((p) => [p.id, p]));
  return {
    categorias,
    productos,
    proveedores,
    codigos: codigos.map<CodigoKiosco>((c) => {
      const p = c.presentacion_id ? presentacion.get(c.presentacion_id) : undefined;
      return { codigo_busqueda: c.codigo_busqueda, producto_id: c.producto_id, presentacion: p?.nombre ?? '', factor: Number(p?.factor ?? 1) };
    }),
  };
}

/** Ítem de una orden pendiente de recibir, en unidades de stock. */
export interface ItemPendiente {
  producto_id: string;
  nombre: string;
  sku: string | null;
  tipo_medida: 'UNIDAD' | 'PESO';
  cant_pedida: number;
  cant_recibida: number;
  saldo: number;
}

/** Orden de compra lista para recibir en la sede. Sin precios, salvo permiso. */
export interface PendienteRecepcion {
  id: string;
  numero: string;
  estado: string;
  proveedor_id: string;
  proveedor: string;
  fecha_entrega_estimada: string | null;
  atrasada: boolean;
  no_enviada: boolean;
  se_puede_recibir: boolean;
  items: ItemPendiente[];
}

/** Órdenes pendientes de recibir en la sede, o null si la cuenta no tiene el permiso. */
export async function pendientesRecepcion(sedeId: string): Promise<PendienteRecepcion[] | null> {
  const { data, error } = await cliente().rpc('pendientes_recepcion', { p_sede_id: sedeId });
  if (error) {
    const e = aErrorApi(error);
    if (e.codigo === 'SIN_PERMISO') return null;
    throw e;
  }
  return ((data ?? []) as unknown as PendienteRecepcion[]).map((p) => ({
    ...p,
    items: p.items.map((i) => ({
      ...i,
      cant_pedida: Number(i.cant_pedida),
      cant_recibida: Number(i.cant_recibida),
      saldo: Number(i.saldo),
    })),
  }));
}

/** Recepción abierta (o rechazada para corregir) de la organización. */
export interface RecepcionAbierta {
  id: string;
  organizacion_id: string;
  sede_id: string;
  estado: string;
  proveedor_id: string;
  proveedor_nombre: string;
  nro_remito: string;
  abierta_en: string;
  cerrada_en: string | null;
  observacion: string | null;
  oc_id: string | null;
  oc_numero: string | null;
}

/** Recepciones de la organización en los estados dados, con el nombre del proveedor. */
export async function recepcionesAbiertas(organizacionId: string, estados: string[]): Promise<RecepcionAbierta[]> {
  const filas = exigir(
    await cliente()
      .from('recepciones')
      .select('id,organizacion_id,sede_id,estado,proveedor_id,nro_remito,abierta_en,cerrada_en,observacion,oc_id,oc_numero')
      .eq('organizacion_id', organizacionId)
      .in('estado', estados as never[]),
  ) as unknown as Array<Omit<RecepcionAbierta, 'proveedor_nombre'>>;
  const ids = [...new Set(filas.map((f) => f.proveedor_id))];
  const proveedores = ids.length ? exigir(await cliente().from('proveedores').select('id,nombre').in('id', ids)) : [];
  const nombre = new Map(proveedores.map((p) => [p.id, p.nombre ?? '']));
  return filas.map((f) => ({ ...f, proveedor_nombre: nombre.get(f.proveedor_id) ?? '' }));
}

/** Ítems, lecturas y adjuntos de una recepción, para rearmarla en el dispositivo. */
export async function contenidoRecepcion(recepcionId: string) {
  const c = cliente();
  const [items, lecturas, adjuntos] = await Promise.all([
    c.from('recepcion_items')
      .select('id,producto_id,lote,vencimiento,cant_recibida,cant_remito,cant_pedida,tipo_diferencia,motivo_diferencia,creado_en')
      .eq('recepcion_id', recepcionId),
    c.from('lecturas').select('item_id,tipo,valor_crudo,motivo,leido_en').eq('recepcion_id', recepcionId)
      .order('leido_en', { ascending: true }),
    c.from('adjuntos').select('client_uuid,item_id,tipo,storage_path,anulado_en').eq('recepcion_id', recepcionId),
  ]);
  const listaItems = exigir(items);
  const ids = [...new Set(listaItems.map((i) => i.producto_id as string))];
  const productos = ids.length ? exigir(await c.from('productos').select('id,nombre,tipo_medida').in('id', ids)) : [];
  const producto = new Map(productos.map((p) => [p.id, p]));
  return {
    items: listaItems.map((i) => ({
      ...i,
      producto_nombre: producto.get(i.producto_id)?.nombre ?? '',
      tipo_medida: (producto.get(i.producto_id)?.tipo_medida ?? 'UNIDAD') as 'UNIDAD' | 'PESO',
    })),
    lecturas: exigir(lecturas),
    adjuntos: exigir(adjuntos),
  };
}
