// Órdenes de compra: confirmar el pedido, seguimiento y envío al proveedor.
import { useCallback, useEffect, useState } from 'react';
import { useCarrito } from './carrito';
import { formatoMoneda, type GrupoProveedor } from './catalogo';
import { db, guardarMeta, leerMeta, type Estado } from './db';
import { formatoFecha, formatoNumero } from './formato';
import { pedirSincronizacion } from './sync';
import { supabase } from './supabase';

export type EstadoOc =
  | 'PENDIENTE_APROBACION'
  | 'APROBADA'
  | 'RECHAZADA'
  | 'ENVIADA'
  | 'RECIBIDA_PARCIAL'
  | 'RECIBIDA'
  | 'CERRADA'
  | 'ANULADA';

export const ETIQUETA_ESTADO_OC: Record<EstadoOc, string> = {
  PENDIENTE_APROBACION: 'En aprobación',
  APROBADA: 'Aprobada',
  RECHAZADA: 'Rechazada',
  ENVIADA: 'Enviada al proveedor',
  RECIBIDA_PARCIAL: 'Recibida parcial',
  RECIBIDA: 'Recibida',
  CERRADA: 'Cerrada',
  ANULADA: 'Anulada',
};

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
  proveedores: { nombre: string; codigo: string | null; cuit: string; telefono_whatsapp: string | null; email: string | null } | null;
}

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

const COLUMNAS =
  'id,numero,estado,total_estimado,creado_en,aprobada_en,enviada_en,fecha_entrega_estimada,motivo_rechazo,motivo_cierre,proveedores(nombre,codigo,cuit,telefono_whatsapp,email)';
const CLAVE_ORDENES = 'ordenes';

/** Pasa el pedido a la cola. El carrito se vacía recién cuando quedó encolado. */
export async function confirmarPedido(sedeId: string, grupos: GrupoProveedor[]) {
  const lineas = useCarrito.getState().lineas;
  const total = grupos.reduce((n, g) => n + g.subtotal, 0);
  await db.cola.add({
    tipo: 'confirmar_pedido',
    recepcion_id: null,
    item_key: null,
    creado_en: new Date().toISOString(),
    estado: 'pendiente',
    error: null,
    args: {
      p_request_uuid: crypto.randomUUID(),
      p_sede_id: sedeId,
      p_items: Object.entries(lineas).map(([oferta_id, cantidad]) => ({ oferta_id, cantidad })),
      // Solo para mostrarlo mientras espera; no viaja al servidor.
      resumen: { proveedores: grupos.map((g) => g.proveedor), total },
    },
  });
  useCarrito.getState().vaciar();
  pedirSincronizacion();
}

export interface ResumenEnCola {
  proveedores: string[];
  total: number;
}

/** Un pedido que el servidor rechazó vuelve al carrito para poder corregirlo. */
export async function recuperarPedido(seq: number) {
  const op = await db.cola.get(seq);
  if (!op) return;
  const carrito = useCarrito.getState();
  for (const { oferta_id, cantidad } of op.args.p_items as Array<{ oferta_id: string; cantidad: number }>) {
    carrito.fijarCantidad(oferta_id, cantidad);
  }
  await db.cola.delete(seq);
}

export function useOrdenes() {
  const [ordenes, setOrdenes] = useState<OrdenResumen[] | null>(null);
  const [sinConexion, setSinConexion] = useState(false);

  const cargar = useCallback(async () => {
    const { data, error } = await supabase
      .from('ordenes_compra')
      .select(COLUMNAS)
      .order('creado_en', { ascending: false })
      .limit(500);
    if (error) {
      setSinConexion(true);
      setOrdenes((actual) => actual ?? []);
      return;
    }
    const lista = data as unknown as OrdenResumen[];
    setOrdenes(lista);
    setSinConexion(false);
    await guardarMeta(CLAVE_ORDENES, lista);
  }, []);

  useEffect(() => {
    void leerMeta<OrdenResumen[]>(CLAVE_ORDENES).then((g) => {
      if (g) setOrdenes((actual) => actual ?? g);
    });
    void cargar();

    const canal = supabase
      .channel('ordenes-compra')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ordenes_compra' }, () => void cargar())
      .subscribe();
    return () => {
      void supabase.removeChannel(canal);
    };
  }, [cargar]);

  return { ordenes, sinConexion, recargar: cargar };
}

export interface SaldoOrden {
  producto_id: string;
  producto_nombre: string;
  cant_pedida: number;
  cant_recibida: number;
}

export interface RecepcionDeOrden {
  id: string;
  nro_remito: string;
  estado: Estado;
  abierta_en: string;
}

export async function traerOrden(id: string) {
  const [orden, items, saldos, recepciones] = await Promise.all([
    supabase.from('ordenes_compra').select(COLUMNAS).eq('id', id).maybeSingle(),
    supabase
      .from('oc_items')
      .select('id,producto_nombre,sku,presentacion_nombre,cantidad,precio_unitario,subtotal,disparo_aprobacion')
      .eq('oc_id', id)
      .order('producto_nombre'),
    supabase
      .from('v_oc_saldos')
      .select('producto_id,producto_nombre,cant_pedida,cant_recibida')
      .eq('oc_id', id)
      .order('producto_nombre'),
    supabase.from('recepciones').select('id,nro_remito,estado,abierta_en').eq('oc_id', id).order('abierta_en'),
  ]);
  if (orden.error) throw new Error(orden.error.message);
  if (items.error) throw new Error(items.error.message);
  return {
    orden: orden.data as unknown as OrdenResumen | null,
    items: (items.data ?? []) as ItemOrden[],
    saldos: (saldos.data ?? []) as SaldoOrden[],
    recepciones: (recepciones.data ?? []) as RecepcionDeOrden[],
  };
}

export async function marcarEnviada(id: string, canal: 'MANUAL' | 'WHATSAPP' | 'EMAIL') {
  const { error } = await supabase.rpc('marcar_oc_enviada', { p_oc_id: id, p_canal: canal });
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

async function llamar(nombre: string, args: Record<string, unknown>) {
  const { error } = await supabase.rpc(nombre, args);
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

export const anularOc = (id: string, motivo: string) => llamar('anular_oc', { p_oc_id: id, p_motivo: motivo });

export const cerrarSaldoOc = (id: string, motivo: string) =>
  llamar('cerrar_saldo_oc', { p_oc_id: id, p_motivo: motivo });

/** Es un indicador calculado, no un estado: venció la fecha estimada y todavía falta recibir. */
export function estaAtrasada(o: OrdenResumen) {
  if (!o.fecha_entrega_estimada) return false;
  if (!(['APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL'] as EstadoOc[]).includes(o.estado)) return false;
  const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(new Date());
  return o.fecha_entrega_estimada < hoy;
}

export interface PasoSeguimiento {
  etiqueta: string;
  fecha: string | null;
  hecho: boolean;
}

/** La línea de tiempo tipo seguimiento de envío. */
export function pasosSeguimiento(o: OrdenResumen): PasoSeguimiento[] {
  const pasos: PasoSeguimiento[] = [{ etiqueta: 'Creada', fecha: o.creado_en, hecho: true }];
  if (o.estado === 'RECHAZADA') {
    pasos.push({ etiqueta: 'Rechazada', fecha: null, hecho: true });
    return pasos;
  }
  pasos.push({ etiqueta: 'Aprobada', fecha: o.aprobada_en, hecho: o.aprobada_en !== null });
  if (o.estado === 'ANULADA') {
    pasos.push({ etiqueta: 'Anulada', fecha: null, hecho: true });
    return pasos;
  }
  const recibida = o.estado === 'RECIBIDA' || o.estado === 'CERRADA';
  pasos.push({ etiqueta: 'Enviada al proveedor', fecha: o.enviada_en, hecho: o.enviada_en !== null });
  pasos.push({
    etiqueta: o.estado === 'RECIBIDA_PARCIAL' ? 'Recibida parcial' : 'Recibida',
    fecha: null,
    hecho: recibida || o.estado === 'RECIBIDA_PARCIAL',
  });
  if (o.estado === 'CERRADA') pasos.push({ etiqueta: 'Cerrada', fecha: null, hecho: true });
  return pasos;
}

export function textoOrden(o: OrdenResumen, items: ItemOrden[]) {
  const lineas = items.map(
    (i) =>
      `- ${formatoNumero(i.cantidad)} x ${i.producto_nombre} (${i.presentacion_nombre})` +
      (i.sku ? ` [${i.sku}]` : ''),
  );
  return [
    `Orden de compra ${o.numero}`,
    ...(o.fecha_entrega_estimada ? [`Entrega estimada: ${formatoFecha(o.fecha_entrega_estimada)}`] : []),
    '',
    ...lineas,
    '',
    `Total estimado: ${formatoMoneda(o.total_estimado)}`,
  ].join('\n');
}

export function enlaceWhatsApp(o: OrdenResumen, items: ItemOrden[]) {
  const telefono = o.proveedores?.telefono_whatsapp?.replace(/\D/g, '');
  return telefono ? `https://wa.me/${telefono}?text=${encodeURIComponent(textoOrden(o, items))}` : null;
}

export function enlaceCorreo(o: OrdenResumen, items: ItemOrden[]) {
  const email = o.proveedores?.email;
  if (!email) return null;
  const asunto = encodeURIComponent(`Orden de compra ${o.numero}`);
  return `mailto:${email}?subject=${asunto}&body=${encodeURIComponent(textoOrden(o, items))}`;
}
