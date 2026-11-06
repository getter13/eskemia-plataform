// Eskemia · Órdenes de compra: confirmar el pedido, seguimiento y envío al proveedor.
//
// Qué hace: encola la confirmación del pedido (funciona sin señal), lista y detalla
// órdenes por @eskemia/cliente-api con aviso en tiempo real, y arma el texto, el enlace de
// WhatsApp y el email para mandarlas al proveedor.
// Dónde encaja: pantallas de Compras (Secciones, Tablero, Orden, Pedido).
import { useCallback, useEffect, useState } from 'react';
import {
  alCambiarOrdenes,
  anularOc as anular,
  cerrarSaldoOc as cerrarSaldo,
  marcarOcEnviada,
  orden as traerDetalleOrden,
  ordenes as traerOrdenes,
  type CanalEnvio,
  type EstadoOc,
  type ItemOrden,
  type OrdenResumen,
  type RecepcionDeOrden,
  type SaldoOrden,
} from '@eskemia/cliente-api';
import { useCarrito } from './carrito';
import { formatearMonto, type GrupoProveedor } from './catalogo';
import { db, guardarMeta, leerMeta, organizacionActual } from './db';
import { formatoFecha, formatoNumero } from './formato';
import { pedirSincronizacion } from './sync';

export type { EstadoOc, ItemOrden, OrdenResumen, RecepcionDeOrden, SaldoOrden };

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
    let lista: OrdenResumen[];
    try {
      lista = await traerOrdenes(await organizacionActual());
    } catch {
      setSinConexion(true);
      setOrdenes((actual) => actual ?? []);
      return;
    }
    setOrdenes(lista);
    setSinConexion(false);
    await guardarMeta(CLAVE_ORDENES, lista);
  }, []);

  useEffect(() => {
    void leerMeta<OrdenResumen[]>(CLAVE_ORDENES).then((g) => {
      if (g) setOrdenes((actual) => actual ?? g);
    });
    void cargar();

    let dejarDeEscuchar: (() => void) | null = null;
    let vigente = true;
    void organizacionActual()
      .then((org) => {
        if (vigente) dejarDeEscuchar = alCambiarOrdenes(org, () => void cargar());
      })
      .catch(() => undefined);
    return () => {
      vigente = false;
      dejarDeEscuchar?.();
    };
  }, [cargar]);

  return { ordenes, sinConexion, recargar: cargar };
}

/** Detalle de una orden: encabezado, ítems, saldos y recepciones. */
export const traerOrden = (id: string) => traerDetalleOrden(id);

/** Registra que la orden se mandó al proveedor por ese canal. */
export async function marcarEnviada(id: string, canal: CanalEnvio) {
  await marcarOcEnviada(id, canal);
}

/** Anula una orden sin recepciones (exige motivo y compras.oc.anular). */
export const anularOc = (id: string, motivo: string) => anular(id, motivo);

/** Cierra lo que falta recibir (exige motivo y compras.oc.cerrar_saldo). */
export const cerrarSaldoOc = (id: string, motivo: string) => cerrarSaldo(id, motivo);

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
    `Total estimado: ${formatearMonto(o.total_estimado)}`,
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
