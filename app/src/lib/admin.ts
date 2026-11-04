// Consultas del back. A diferencia del kiosco, requiere conexión: muestra el estado real del servidor.
import type { Estado, TipoAdjunto, TipoDiferencia, TipoLectura, TipoMedida } from './db';
import { formatoFecha, formatoFechaHora, formatoNumero } from './formato';
import { BUCKET_ADJUNTOS, supabase } from './supabase';

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
  hash: string;
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

const COLUMNAS_BANDEJA =
  'id,sede,estado,proveedor_id,proveedor,nro_remito,usuario_id,abierta_en,cerrada_en,validada_por,validada_en,observacion,fecha,items,items_con_diferencia,checklist,remito_duplicado,semaforo,oc_id,oc_numero';

const COLUMNAS_ITEM =
  'id,cant_remito,cant_recibida,cant_pedida,diferencia,tipo_diferencia,motivo_diferencia,lote,vencimiento,productos(nombre,gtin,tipo_medida,pendiente_validacion)';

function exigir<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message);
  return r.data as T;
}

export function fechaHoy(): string {
  // en-CA da aaaa-mm-dd.
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(new Date());
}

export function moverFecha(fecha: string, dias: number): string {
  const d = new Date(`${fecha}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

export async function traerBandeja(fecha: string): Promise<FilaBandeja[]> {
  return exigir(
    await supabase
      .from('v_recepciones_bandeja')
      .select(COLUMNAS_BANDEJA)
      .eq('fecha', fecha)
      .order('abierta_en', { ascending: false }),
  ) as unknown as FilaBandeja[];
}

export async function traerDetalle(id: string): Promise<Detalle | null> {
  const fila = exigir(
    await supabase.from('v_recepciones_bandeja').select(COLUMNAS_BANDEJA).eq('id', id).maybeSingle(),
  ) as unknown as FilaBandeja | null;
  if (!fila) return null;

  const [proveedor, items, lecturas, adjuntos, eventos, perfiles] = await Promise.all([
    supabase.from('proveedores').select('cuit').eq('id', fila.proveedor_id).maybeSingle(),
    supabase.from('recepcion_items').select(COLUMNAS_ITEM).eq('recepcion_id', id).order('creado_en'),
    supabase
      .from('lecturas')
      .select('id,tipo,valor_crudo,cantidad,motivo,leido_en,productos(nombre,tipo_medida)')
      .eq('recepcion_id', id)
      .order('leido_en'),
    supabase
      .from('adjuntos')
      .select('id,tipo,storage_path,anulado_en,creado_en')
      .eq('recepcion_id', id)
      .order('creado_en'),
    supabase
      .from('eventos')
      .select('id,secuencia,accion,payload,usuario_id,creado_en,hash')
      .eq('entidad', 'recepcion')
      .eq('entidad_id', id)
      .order('secuencia'),
    supabase.from('perfiles').select('user_id,nombre'),
  ]);

  const listaAdjuntos = exigir(adjuntos) as Array<Omit<AdjuntoDetalle, 'url'>>;
  const urls = new Map<string, string>();
  if (listaAdjuntos.length > 0) {
    const firmadas = exigir(
      await supabase.storage.from(BUCKET_ADJUNTOS).createSignedUrls(
        listaAdjuntos.map((a) => a.storage_path),
        3600,
      ),
    );
    for (const f of firmadas) {
      if (f.path && f.signedUrl) urls.set(f.path, f.signedUrl);
    }
  }

  return {
    recepcion: fila,
    cuit: exigir(proveedor)?.cuit ?? null,
    items: exigir(items) as unknown as ItemDetalle[],
    lecturas: exigir(lecturas) as unknown as LecturaDetalle[],
    adjuntos: listaAdjuntos.map((a) => ({ ...a, url: urls.get(a.storage_path) ?? null })),
    eventos: exigir(eventos) as unknown as EventoDetalle[],
    usuarios: Object.fromEntries(
      (exigir(perfiles) as Array<{ user_id: string; nombre: string }>).map((p) => [p.user_id, p.nombre]),
    ),
  };
}

async function llamar(nombre: string, args: Record<string, unknown>) {
  const { error } = await supabase.rpc(nombre, args);
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

export const validarRecepcion = (id: string, observacion: string) =>
  llamar('validar_recepcion', { p_recepcion_id: id, p_observacion: observacion || null });

export const rechazarRecepcion = (id: string, observacion: string) =>
  llamar('rechazar_recepcion', { p_recepcion_id: id, p_observacion: observacion });

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
  const ids = recepciones.map((r) => r.id);

  const [items, proveedores] = ids.length
    ? await Promise.all([
        supabase.from('recepcion_items').select(`recepcion_id,${COLUMNAS_ITEM}`).in('recepcion_id', ids),
        supabase.from('proveedores').select('id,cuit').in('id', recepciones.map((r) => r.proveedor_id)),
      ])
    : [{ data: [], error: null }, { data: [], error: null }];

  const porRecepcion = new Map<string, ItemDetalle[]>();
  for (const i of exigir(items) as unknown as Array<ItemDetalle & { recepcion_id: string }>) {
    porRecepcion.set(i.recepcion_id, [...(porRecepcion.get(i.recepcion_id) ?? []), i]);
  }
  const cuits = new Map((exigir(proveedores) as Array<{ id: string; cuit: string }>).map((p) => [p.id, p.cuit]));

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
