// Eskemia · Recepción: lo que necesita el back (supervisión).
//
// Qué hace: bandeja diaria con semáforo y checklist, detalle completo de una recepción
// (ítems, lecturas, fotos con enlace firmado y eventos), validación, rechazo y los datos
// para exportar a CSV.
// Dónde encaja: dominio "recepcion" de la Etapa 3. Requiere conexión: muestra el estado
// real del servidor. Validar exige recepcion.recepcion.validar.

import { BUCKET_ADJUNTOS, cliente } from '../cliente';
import { exigir, sinError } from '../errores';
import { miembros } from '../miembros';

const COLUMNAS_BANDEJA =
  'id,organizacion_id,sede,estado,proveedor_id,proveedor,nro_remito,usuario_id,abierta_en,cerrada_en,validada_por,validada_en,observacion,fecha,items,items_con_diferencia,checklist,remito_duplicado,semaforo,oc_id,oc_numero';

const COLUMNAS_ITEM =
  'id,recepcion_id,producto_id,cant_remito,cant_recibida,cant_pedida,diferencia,tipo_diferencia,motivo_diferencia,lote,vencimiento';

/** Datos del producto que muestra el back junto a ítems y lecturas. */
export interface ProductoResumen {
  nombre: string;
  gtin: string | null;
  tipo_medida: 'UNIDAD' | 'PESO';
  pendiente_validacion: boolean;
}

/** Agrega `productos` (nombre, GTIN, medida) a cada fila con producto_id. */
async function conProducto<T extends { producto_id: string | null }>(filas: T[]) {
  const ids = [...new Set(filas.map((f) => f.producto_id).filter((id): id is string => !!id))];
  const lista = ids.length
    ? exigir(await cliente().from('productos').select('id,nombre,gtin,tipo_medida,pendiente_validacion').in('id', ids))
    : [];
  const porId = new Map(lista.map((p) => [p.id, p as unknown as ProductoResumen]));
  const vacio: ProductoResumen = { nombre: '', gtin: null, tipo_medida: 'UNIDAD', pendiente_validacion: false };
  return filas.map((f) => ({ ...f, productos: porId.get(f.producto_id ?? '') ?? vacio }));
}

/** Recepciones de la organización en un día (aaaa-mm-dd), las más nuevas primero. */
export async function bandejaRecepciones(organizacionId: string, fecha: string) {
  return exigir(
    await cliente()
      .from('recepciones_bandeja')
      .select(COLUMNAS_BANDEJA)
      .eq('organizacion_id', organizacionId)
      .eq('fecha', fecha)
      .order('abierta_en', { ascending: false }),
  );
}

/** Detalle completo de una recepción, o null si no existe o no se puede ver. */
export async function detalleRecepcion(id: string) {
  const c = cliente();
  // La lista de columnas es larga para el parser de tipos de supabase-js: se tipa a mano.
  const fila = exigir(await c.from('recepciones_bandeja').select(COLUMNAS_BANDEJA).eq('id', id).maybeSingle()) as
    | (Record<string, unknown> & { proveedor_id: string; organizacion_id: string })
    | null;
  if (!fila) return null;

  const [proveedor, items, lecturas, adjuntos, eventos, equipo] = await Promise.all([
    c.from('proveedores').select('cuit').eq('id', fila.proveedor_id).maybeSingle(),
    c.from('recepcion_items').select(COLUMNAS_ITEM).eq('recepcion_id', id).order('creado_en'),
    c.from('lecturas').select('id,producto_id,tipo,valor_crudo,cantidad,motivo,leido_en').eq('recepcion_id', id).order('leido_en'),
    c.from('adjuntos').select('id,tipo,storage_path,anulado_en,creado_en').eq('recepcion_id', id).order('creado_en'),
    c.from('eventos').select('id,secuencia,accion,payload,usuario_id,creado_en')
      .eq('entidad', 'recepcion').eq('entidad_id', id).order('secuencia'),
    miembros(fila.organizacion_id),
  ]);

  const listaAdjuntos = exigir(adjuntos);
  const urls = new Map<string, string>();
  if (listaAdjuntos.length > 0) {
    const firmadas = exigir(
      await c.storage.from(BUCKET_ADJUNTOS).createSignedUrls(listaAdjuntos.map((a) => a.storage_path as string), 3600),
    );
    for (const f of firmadas) if (f.path && f.signedUrl) urls.set(f.path, f.signedUrl);
  }

  return {
    recepcion: fila,
    cuit: exigir(proveedor)?.cuit ?? null,
    items: await conProducto(exigir(items)),
    lecturas: await conProducto(exigir(lecturas)),
    adjuntos: listaAdjuntos.map((a) => ({ ...a, url: urls.get(a.storage_path as string) ?? null })),
    eventos: exigir(eventos),
    usuarios: Object.fromEntries(equipo.map((m) => [m.cuenta_id, m.nombre])) as Record<string, string>,
  };
}

/** Valida una recepción cerrada. Exige recepcion.recepcion.validar. */
export async function validarRecepcion(id: string, observacion: string | null): Promise<void> {
  sinError(await cliente().rpc('validar_recepcion', { p_recepcion_id: id, p_observacion: observacion ?? undefined }));
}

/** Rechaza una recepción para que el kiosco la corrija. La observación es obligatoria. */
export async function rechazarRecepcion(id: string, observacion: string): Promise<void> {
  sinError(await cliente().rpc('rechazar_recepcion', { p_recepcion_id: id, p_observacion: observacion }));
}

/** Ítems (con su producto) de varias recepciones y CUIT de sus proveedores, para el CSV. */
export async function datosExportacion(recepcionIds: string[], proveedorIds: string[]) {
  if (recepcionIds.length === 0) return { items: [], cuits: new Map<string, string>() };
  const c = cliente();
  const [items, proveedores] = await Promise.all([
    c.from('recepcion_items').select(COLUMNAS_ITEM).in('recepcion_id', recepcionIds),
    c.from('proveedores').select('id,cuit').in('id', proveedorIds),
  ]);
  return {
    items: await conProducto(exigir(items)),
    cuits: new Map(exigir(proveedores).map((p) => [p.id as string, p.cuit as string])),
  };
}
