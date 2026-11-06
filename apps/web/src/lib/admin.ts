// Eskemia · Back de Recepción: bandeja, detalle, validación y exportación.
//
// Qué hace: adapta lo que devuelve @eskemia/cliente-api a las pantallas del back y arma
// el CSV del día. A diferencia del kiosco, requiere conexión: muestra el estado real del
// servidor.
// Dónde encaja: pantallas Admin > Bandeja y Detalle.
import {
  bandejaRecepciones,
  datosExportacion,
  detalleRecepcion,
  rechazarRecepcion as rechazar,
  validarRecepcion as validar,
} from '@eskemia/cliente-api';
import { organizacionActual, type Estado, type TipoAdjunto, type TipoDiferencia, type TipoLectura, type TipoMedida } from './db';
import { formatoFecha, formatoFechaHora, formatoNumero } from './formato';

export type Semaforo = 'OK' | 'CON_DIFERENCIAS' | 'CONTROL_INCOMPLETO';

export interface Checklist {
  foto_remito: boolean;
  tiene_items: boolean;
  cantidades_remito: boolean;
  motivos_diferencias: boolean;
  fotos_manuales: boolean;
  firma_receptor: boolean;
  firma_transportista: boolean;
  completo: boolean;
}

export const ETIQUETAS_CHECKLIST: Array<[Exclude<keyof Checklist, 'completo'>, string]> = [
  ['foto_remito', 'Foto del remito o factura'],
  ['tiene_items', 'Ítems cargados'],
  ['cantidades_remito', 'Cantidades del remito'],
  ['motivos_diferencias', 'Motivos de las diferencias'],
  ['fotos_manuales', 'Fotos de las cargas manuales'],
  ['firma_receptor', 'Firma del receptor'],
  ['firma_transportista', 'Firma del transportista'],
];

export interface FilaBandeja {
  id: string;
  sede: string;
  estado: Estado;
  proveedor_id: string;
  proveedor: string;
  nro_remito: string;
  usuario_id: string;
  abierta_en: string;
  cerrada_en: string | null;
  validada_por: string | null;
  validada_en: string | null;
  observacion: string | null;
  fecha: string;
  items: number;
  items_con_diferencia: number;
  checklist: Checklist;
  remito_duplicado: boolean;
  oc_id: string | null;
  oc_numero: string | null;
  semaforo: Semaforo;
}

export interface ItemDetalle {
  id: string;
  cant_remito: number | null;
  cant_pedida: number | null;
  cant_recibida: number;
  diferencia: number | null;
  tipo_diferencia: TipoDiferencia | null;
  motivo_diferencia: string | null;
  lote: string | null;
  vencimiento: string | null;
  productos: {
    nombre: string;
    gtin: string | null;
    tipo_medida: TipoMedida;
    pendiente_validacion: boolean;
  };
}

export interface LecturaDetalle {
  id: string;
  tipo: TipoLectura;
  valor_crudo: string | null;
  cantidad: number;
  motivo: string | null;
  leido_en: string;
  productos: { nombre: string; tipo_medida: TipoMedida };
}

export interface AdjuntoDetalle {
  id: string;
  tipo: TipoAdjunto;
  storage_path: string;
  anulado_en: string | null;
  creado_en: string;
  url: string | null;
}

export interface EventoDetalle {
  id: string;
  secuencia: number;
  accion: string;
  payload: Record<string, unknown>;
  usuario_id: string | null;
  creado_en: string;
}

export interface Detalle {
  recepcion: FilaBandeja;
  cuit: string | null;
  items: ItemDetalle[];
  lecturas: LecturaDetalle[];
  adjuntos: AdjuntoDetalle[];
  eventos: EventoDetalle[];
  usuarios: Record<string, string>;
}

/** Hoy en Buenos Aires, como aaaa-mm-dd. */
export function fechaHoy(): string {
  // en-CA da aaaa-mm-dd.
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(new Date());
}

export function moverFecha(fecha: string, dias: number): string {
  const d = new Date(`${fecha}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

/** Recepciones del día (aaaa-mm-dd) en la organización actual. */
export async function traerBandeja(fecha: string): Promise<FilaBandeja[]> {
  return (await bandejaRecepciones(await organizacionActual(), fecha)) as unknown as FilaBandeja[];
}

/** Detalle completo de una recepción, o null si no existe o no se puede ver. */
export async function traerDetalle(id: string): Promise<Detalle | null> {
  const d = await detalleRecepcion(id);
  if (!d) return null;
  return {
    recepcion: d.recepcion as unknown as FilaBandeja,
    cuit: d.cuit,
    items: d.items as unknown as ItemDetalle[],
    lecturas: d.lecturas as unknown as LecturaDetalle[],
    adjuntos: d.adjuntos as unknown as AdjuntoDetalle[],
    eventos: d.eventos as unknown as EventoDetalle[],
    usuarios: d.usuarios,
  };
}

/** Valida una recepción cerrada (observación opcional). */
export const validarRecepcion = (id: string, observacion: string) => validar(id, observacion || null);

/** Rechaza una recepción para que el kiosco la corrija. */
export const rechazarRecepcion = (id: string, observacion: string) => rechazar(id, observacion);

// ---------------------------------------------------------------------------
// Exportación
// ---------------------------------------------------------------------------

const ENCABEZADOS_CSV = [
  'Fecha',
  'Sede',
  'Proveedor',
  'CUIT',
  'Remito o factura',
  'Remito repetido',
  'Estado',
  'Semáforo',
  'Producto',
  'GTIN',
  'Medida',
  'Lote',
  'Vencimiento',
  'Cantidad remito',
  'Cantidad recibida',
  'Diferencia',
  'Tipo de diferencia',
  'Motivo',
  'Abierta',
  'Cerrada',
  'Validada',
  'Observación',
];

/** Celda de texto. Neutraliza fórmulas, porque el CSV suele abrirse en Excel. */
export function celdaTexto(valor: string | null | undefined): string {
  let t = valor ?? '';
  if (/^[=+\-@\t\r]/.test(t)) t = `'${t}`;
  return /[";\n\r]/.test(t) ? `"${t.replaceAll('"', '""')}"` : t;
}

const celdaNumero = (n: number | null | undefined) =>
  n === null || n === undefined ? '' : `"${formatoNumero(Number(n))}"`;

export async function generarCsv(fecha: string): Promise<string> {
  const recepciones = await traerBandeja(fecha);
  const { items, cuits } = await datosExportacion(
    recepciones.map((r) => r.id),
    recepciones.map((r) => r.proveedor_id),
  );

  const porRecepcion = new Map<string, ItemDetalle[]>();
  for (const i of items as unknown as Array<ItemDetalle & { recepcion_id: string }>) {
    porRecepcion.set(i.recepcion_id, [...(porRecepcion.get(i.recepcion_id) ?? []), i]);
  }

  const filas = recepciones.flatMap((r) => {
    const comunes = [
      formatoFecha(r.fecha),
      celdaTexto(r.sede),
      celdaTexto(r.proveedor),
      cuits.get(r.proveedor_id) ?? '',
      celdaTexto(r.nro_remito),
      r.remito_duplicado ? 'Sí' : 'No',
      r.estado,
      r.semaforo,
    ];
    const finales = [
      formatoFechaHora(r.abierta_en),
      r.cerrada_en ? formatoFechaHora(r.cerrada_en) : '',
      r.validada_en ? formatoFechaHora(r.validada_en) : '',
      celdaTexto(r.observacion),
    ];
    const lineas = porRecepcion.get(r.id) ?? [];
    if (lineas.length === 0) return [[...comunes, ...Array(10).fill(''), ...finales]];
    return lineas.map((i) => [
      ...comunes,
      celdaTexto(i.productos.nombre),
      i.productos.gtin ?? '',
      i.productos.tipo_medida === 'PESO' ? 'kg' : 'unidades',
      celdaTexto(i.lote),
      i.vencimiento ? formatoFecha(i.vencimiento) : '',
      celdaNumero(i.cant_remito),
      celdaNumero(i.cant_recibida),
      celdaNumero(i.diferencia),
      i.tipo_diferencia ?? '',
      celdaTexto(i.motivo_diferencia),
      ...finales,
    ]);
  });

  // Punto y coma y BOM: es lo que Excel en español abre sin asistente.
  return `﻿${[ENCABEZADOS_CSV, ...filas].map((f) => f.join(';')).join('\r\n')}\r\n`;
}

export async function descargarCsv(fecha: string) {
  const csv = await generarCsv(fecha);
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const enlace = document.createElement('a');
  enlace.href = url;
  enlace.download = `recepciones-${fecha}.csv`;
  enlace.click();
  URL.revokeObjectURL(url);
}
