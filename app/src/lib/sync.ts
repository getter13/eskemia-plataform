// Sincronización: envía la cola en orden y trae catálogos y recepciones abiertas.
// El orden importa: una lectura no puede llegar antes que su recepción.
// Reintentar es seguro porque las RPC son idempotentes (client_uuid).
import { aGtin14 } from './codigos';
import { db, type Estado, type ItemLocal, type OpCola, type Producto, type TipoLectura } from './db';
import { BUCKET_ADJUNTOS, supabase } from './supabase';

const INTERVALO_MS = 20_000;
const ESTADOS_ABIERTOS: Estado[] = ['ABIERTA', 'EN_CONTROL', 'RECHAZADA'];

let corriendo = false;
let repetir = false;

class ErrorTransitorio extends Error {}

function clasificar(error: { message: string; code?: string; statusCode?: string }): Error {
  const code = error.code ?? '';
  const transitorio =
    code === '' ||
    code.startsWith('08') ||
    code.startsWith('5') ||
    code === 'PGRST301' ||
    code === 'PGRST303' ||
    /fetch|network|timeout/i.test(error.message);
  return transitorio ? new ErrorTransitorio(error.message) : new Error(error.message);
}

async function rpc(nombre: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await supabase.rpc(nombre, args);
  if (error) throw clasificar(error);
  return data;
}

function reemplazarId<T>(valor: T, viejo: string, nuevo: string): T {
  return JSON.parse(JSON.stringify(valor).replaceAll(viejo, nuevo)) as T;
}

/** El servidor puede devolver otro id si el CUIT o el GTIN ya existían. */
async function remapear(viejo: string, nuevo: string) {
  if (viejo === nuevo) return;
  await db.transaction(
    'rw',
    [db.cola, db.items, db.adjuntos, db.productos, db.proveedores, db.recepciones],
    async () => {
      for (const o of await db.cola.toArray()) {
        await db.cola.put(reemplazarId(o, viejo, nuevo));
      }
      for (const i of await db.items.toArray()) {
        if (!i.key.includes(viejo)) continue;
        await db.items.delete(i.key);
        await db.items.put(reemplazarId(i, viejo, nuevo));
      }
      for (const a of await db.adjuntos.toArray()) {
        if (a.item_key?.includes(viejo)) {
          await db.adjuntos.update(a.client_uuid, { item_key: a.item_key.replaceAll(viejo, nuevo) });
        }
      }
      for (const r of await db.recepciones.toArray()) {
        if (r.proveedor_id === viejo) await db.recepciones.update(r.id, { proveedor_id: nuevo });
      }
      await db.productos.delete(viejo);
      await db.proveedores.delete(viejo);
    },
  );
}

async function subirAdjunto(o: OpCola) {
  const a = o.args as { p_client_uuid: string; p_storage_path: string };
  const local = await db.adjuntos.get(a.p_client_uuid);
  if (local?.blob) {
    const { error } = await supabase.storage
      .from(BUCKET_ADJUNTOS)
      .upload(a.p_storage_path, local.blob, { upsert: false, contentType: local.blob.type });
    // Si ya estaba, es el reintento de una subida que cortó antes de registrarse.
    if (error && !/exists|duplicate/i.test(error.message)) {
      const { statusCode, status } = error as { statusCode?: string | number; status?: number };
      const codigo = String(statusCode ?? status ?? '');
      if (codigo === '' || codigo.startsWith('5') || /jwt|token/i.test(error.message)) {
        throw new ErrorTransitorio(error.message);
      }
      throw new Error(error.message);
    }
  }
  let p_item_id: string | null = null;
  if (o.item_key) {
    p_item_id = (await db.items.get(o.item_key))?.server_id ?? null;
    if (!p_item_id) throw new Error('El ítem de la foto todavía no está sincronizado');
  }
  await rpc('registrar_adjunto', { ...o.args, p_item_id });
  await db.adjuntos.update(a.p_client_uuid, { blob: undefined });
}

async function ejecutar(o: OpCola) {
  switch (o.tipo) {
    case 'registrar_dispositivo':
      await rpc('registrar_dispositivo', o.args);
      return;
    case 'alta_proveedor':
      await remapear(o.args.p_id as string, (await rpc('alta_rapida_proveedor', o.args)) as string);
      return;
    case 'alta_producto':
      await remapear(o.args.p_id as string, (await rpc('alta_rapida_producto', o.args)) as string);
      return;
    case 'abrir_recepcion':
      await rpc('abrir_recepcion', o.args);
      return;
    case 'subir_adjunto':
      await subirAdjunto(o);
      return;
    case 'registrar_lectura': {
      const r = (await rpc('registrar_lectura', o.args)) as { item_id: string };
      if (o.item_key) await db.items.update(o.item_key, { server_id: r.item_id });
      return;
    }
    case 'fijar_control_item': {
      const id = (await rpc('fijar_control_item', o.args)) as string;
      if (o.item_key) await db.items.update(o.item_key, { server_id: id });
      return;
    }
    case 'iniciar_control':
      await rpc('iniciar_control', o.args);
      return;
    case 'cerrar_recepcion':
      await rpc('cerrar_recepcion', o.args);
      return;
    case 'reabrir_recepcion':
      await rpc('reabrir_recepcion', o.args);
      return;
    case 'confirmar_pedido': {
      const { resumen: _resumen, ...args } = o.args;
      await rpc('confirmar_pedido', args);
      return;
    }
  }
}

/** Devuelve false si hay que esperar al próximo intento (sin red o sesión vencida). */
async function vaciarCola(): Promise<boolean> {
  for (;;) {
    const ops = await db.cola.orderBy('seq').toArray();
    // Una operación rechazada frena las siguientes de esa recepción, no las de las demás.
    const bloqueadas = new Set(ops.filter((o) => o.estado === 'error').map((o) => o.recepcion_id));
    const siguiente = ops.find(
      (o) =>
        o.estado === 'pendiente' && !(o.recepcion_id !== null && bloqueadas.has(o.recepcion_id)),
    );
    if (!siguiente) return true;
    try {
      await ejecutar(siguiente);
      await db.cola.delete(siguiente.seq!);
    } catch (e) {
      if (e instanceof ErrorTransitorio) return false;
      await db.cola.update(siguiente.seq!, {
        estado: 'error',
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

async function traerTodo<T>(tabla: string, columnas: string): Promise<T[]> {
  const filas: T[] = [];
  const pagina = 1000;
  for (let desde = 0; ; desde += pagina) {
    const { data, error } = await supabase
      .from(tabla)
      .select(columnas)
      .range(desde, desde + pagina - 1);
    if (error) throw clasificar(error);
    filas.push(...(data as T[]));
    if (!data || data.length < pagina) return filas;
  }
}

export async function traerCatalogos() {
  const [categorias, productos, proveedores] = await Promise.all([
    traerTodo<{ id: string; nombre: string; orden: number }>('categorias', 'id,nombre,orden'),
    traerTodo<Omit<Producto, 'gtin14'>>(
      'productos',
      'id,gtin,nombre,tipo_medida,requiere_lote,requiere_vencimiento,pendiente_validacion,categoria_id',
    ),
    traerTodo<{ id: string; nombre: string; cuit: string }>('proveedores', 'id,nombre,cuit'),
  ]);
  await db.transaction('rw', db.categorias, db.productos, db.proveedores, async () => {
    await db.categorias.clear();
    await db.categorias.bulkPut(categorias);
    await db.productos.bulkPut(
      productos.map((p) => ({ ...p, gtin14: p.gtin ? aGtin14(p.gtin) : null })),
    );
    await db.proveedores.bulkPut(proveedores);
  });
}

interface FilaRecepcion {
  id: string;
  tenant_id: string;
  sede_id: string;
  estado: Estado;
  proveedor_id: string;
  nro_remito: string;
  abierta_en: string;
  cerrada_en: string | null;
  observacion: string | null;
  proveedores: { nombre: string } | null;
}

/** El servidor manda sobre las recepciones sin operaciones pendientes en esta tablet. */
async function traerRecepciones() {
  const { data, error } = await supabase
    .from('recepciones')
    .select(
      'id,tenant_id,sede_id,estado,proveedor_id,nro_remito,abierta_en,cerrada_en,observacion,proveedores(nombre)',
    )
    .in('estado', ESTADOS_ABIERTOS);
  if (error) throw clasificar(error);
  const filas = (data ?? []) as unknown as FilaRecepcion[];

  const conPendientes = new Set((await db.cola.toArray()).map((o) => o.recepcion_id));
  const ids = new Set(filas.map((f) => f.id));

  // Abiertas en esta tablet que en el servidor ya avanzaron.
  for (const local of await db.recepciones.where('estado').anyOf(ESTADOS_ABIERTOS).toArray()) {
    if (!ids.has(local.id) && !conPendientes.has(local.id)) {
      await db.recepciones.delete(local.id);
    }
  }

  for (const f of filas) {
    if (conPendientes.has(f.id)) continue;
    await hidratar(f);
  }
}

async function hidratar(f: FilaRecepcion) {
  const [items, lecturas, adjuntos] = await Promise.all([
    supabase
      .from('recepcion_items')
      .select(
        'id,producto_id,lote,vencimiento,cant_recibida,cant_remito,tipo_diferencia,motivo_diferencia,creado_en,productos(nombre,tipo_medida)',
      )
      .eq('recepcion_id', f.id),
    supabase
      .from('lecturas')
      .select('item_id,tipo,valor_crudo,motivo,leido_en')
      .eq('recepcion_id', f.id)
      .order('leido_en', { ascending: true }),
    supabase
      .from('adjuntos')
      .select('client_uuid,item_id,tipo,storage_path,anulado_en')
      .eq('recepcion_id', f.id),
  ]);
  const error = items.error ?? lecturas.error ?? adjuntos.error;
  if (error) throw clasificar(error);

  const ultima = new Map<string, { tipo: TipoLectura; valor_crudo: string | null; motivo: string | null }>();
  for (const l of lecturas.data ?? []) ultima.set(l.item_id, l);

  const claves = new Map<string, string>();
  const locales: ItemLocal[] = ((items.data ?? []) as unknown as Array<{
    id: string;
    producto_id: string;
    lote: string | null;
    vencimiento: string | null;
    cant_recibida: number;
    cant_remito: number | null;
    tipo_diferencia: ItemLocal['tipo_diferencia'];
    motivo_diferencia: string | null;
    creado_en: string;
    productos: { nombre: string; tipo_medida: ItemLocal['tipo_medida'] };
  }>).map((i) => {
    const key = `${f.id}|${i.producto_id}|${i.lote ?? ''}|${i.vencimiento ?? ''}`;
    claves.set(i.id, key);
    const u = ultima.get(i.id);
    return {
      key,
      server_id: i.id,
      recepcion_id: f.id,
      producto_id: i.producto_id,
      producto_nombre: i.productos.nombre,
      tipo_medida: i.productos.tipo_medida,
      lote: i.lote,
      vencimiento: i.vencimiento,
      cant_recibida: Number(i.cant_recibida),
      cant_remito: i.cant_remito === null ? null : Number(i.cant_remito),
      tipo_diferencia: i.tipo_diferencia,
      motivo_diferencia: i.motivo_diferencia,
      ultimo_tipo: u?.tipo ?? null,
      ultimo_crudo: u?.valor_crudo ?? null,
      ultimo_motivo: u?.motivo ?? null,
      orden: new Date(i.creado_en).getTime(),
    };
  });

  await db.transaction('rw', db.recepciones, db.items, db.adjuntos, db.cola, async () => {
    // Si el operario cargó algo mientras llegaba esta respuesta, lo local manda.
    if ((await db.cola.where('recepcion_id').equals(f.id).count()) > 0) return;
    await db.recepciones.put({
      id: f.id,
      tenant_id: f.tenant_id,
      sede_id: f.sede_id,
      estado: f.estado,
      proveedor_id: f.proveedor_id,
      proveedor_nombre: f.proveedores?.nombre ?? '',
      nro_remito: f.nro_remito,
      abierta_en: f.abierta_en,
      cerrada_en: f.cerrada_en,
      observacion: f.observacion,
    });
    await db.items.where('recepcion_id').equals(f.id).delete();
    await db.items.bulkPut(locales);
    await db.adjuntos.where('recepcion_id').equals(f.id).delete();
    await db.adjuntos.bulkPut(
      (adjuntos.data ?? []).map((a) => ({
        client_uuid: a.client_uuid,
        recepcion_id: f.id,
        item_key: a.item_id ? (claves.get(a.item_id) ?? null) : null,
        tipo: a.tipo,
        storage_path: a.storage_path,
        extension: a.storage_path.split('.').pop() ?? 'jpg',
        anulado: a.anulado_en !== null,
      })),
    );
  });
}

export async function sincronizar() {
  if (corriendo) {
    repetir = true;
    return;
  }
  if (!navigator.onLine) return;
  corriendo = true;
  try {
    const { data } = await supabase.auth.getSession();
    if (!data.session) return;
    if (await vaciarCola()) {
      await traerCatalogos();
      await traerRecepciones();
    }
  } catch (e) {
    console.warn('Sincronización pendiente:', e);
  } finally {
    corriendo = false;
    if (repetir) {
      repetir = false;
      void sincronizar();
    }
  }
}

export function pedirSincronizacion() {
  void sincronizar();
}

export async function reintentarErrores() {
  await db.cola.where('estado').equals('error').modify({ estado: 'pendiente', error: null });
  pedirSincronizacion();
}

export function iniciarSincronizacion() {
  window.addEventListener('online', pedirSincronizacion);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') pedirSincronizacion();
  });
  setInterval(pedirSincronizacion, INTERVALO_MS);
  pedirSincronizacion();
}
