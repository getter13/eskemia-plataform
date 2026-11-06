// Eskemia · Sincronización del dispositivo.
//
// Qué hace: envía la cola de operaciones en orden y trae catálogos, órdenes pendientes y
// recepciones abiertas. El orden importa: una lectura no puede llegar antes que su
// recepción. Reintentar es seguro porque las RPC son idempotentes (client_uuid).
// Dónde encaja: toda la comunicación pasa por @eskemia/cliente-api; un ErrorApi
// `transitorio` deja la operación esperando y cualquier otro la marca con error.

import {
  catalogosKiosco,
  contenidoRecepcion,
  ejecutarOperacion,
  ErrorApi,
  pendientesRecepcion,
  recepcionesAbiertas,
  sesionActual,
  subirAdjunto as subirArchivo,
  type OperacionCola,
  type RecepcionAbierta,
} from '@eskemia/cliente-api';
import { aGtin14 } from './codigos';
import {
  db,
  leerMeta,
  type Estado,
  type ItemLocal,
  type OpCola,
  type TipoAdjunto,
  type TipoLectura,
  type TipoOp,
} from './db';

const INTERVALO_MS = 20_000;
const ESTADOS_ABIERTOS: Estado[] = ['ABIERTA', 'EN_CONTROL', 'RECHAZADA'];

let corriendo = false;
let repetir = false;

/** RPC que ejecuta cada tipo de operación de la cola. */
const RPC_DE: Record<TipoOp, OperacionCola> = {
  registrar_dispositivo: 'registrar_dispositivo',
  alta_proveedor: 'alta_rapida_proveedor',
  alta_producto: 'alta_rapida_producto',
  abrir_recepcion: 'abrir_recepcion',
  subir_adjunto: 'registrar_adjunto',
  registrar_lectura: 'registrar_lectura',
  fijar_control_item: 'fijar_control_item',
  iniciar_control: 'iniciar_control',
  cerrar_recepcion: 'cerrar_recepcion',
  reabrir_recepcion: 'reabrir_recepcion',
  confirmar_pedido: 'confirmar_pedido',
};

const rpc = (tipo: TipoOp, args: Record<string, unknown>) => ejecutarOperacion(RPC_DE[tipo], args);

const esTransitorio = (e: unknown) => e instanceof ErrorApi && e.transitorio;

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
  if (local?.blob) await subirArchivo(a.p_storage_path, local.blob);
  let p_item_id: string | null = null;
  if (o.item_key) {
    p_item_id = (await db.items.get(o.item_key))?.server_id ?? null;
    if (!p_item_id) throw new Error('El ítem de la foto todavía no está sincronizado');
  }
  await rpc('subir_adjunto', { ...o.args, p_item_id });
  await db.adjuntos.update(a.p_client_uuid, { blob: undefined });
}

async function ejecutar(o: OpCola) {
  switch (o.tipo) {
    case 'alta_proveedor':
    case 'alta_producto':
      await remapear(o.args.p_id as string, (await rpc(o.tipo, o.args)) as string);
      return;
    case 'subir_adjunto':
      await subirAdjunto(o);
      return;
    case 'registrar_lectura': {
      const r = (await rpc(o.tipo, o.args)) as { item_id: string };
      if (o.item_key) await db.items.update(o.item_key, { server_id: r.item_id });
      return;
    }
    case 'fijar_control_item': {
      const id = (await rpc(o.tipo, o.args)) as string;
      if (o.item_key) await db.items.update(o.item_key, { server_id: id });
      return;
    }
    case 'confirmar_pedido': {
      const { resumen: _resumen, ...args } = o.args;
      await rpc(o.tipo, args);
      return;
    }
    default:
      await rpc(o.tipo, o.args);
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
      if (esTransitorio(e)) return false;
      await db.cola.update(siguiente.seq!, {
        estado: 'error',
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

/** Trae los catálogos completos de la organización y reemplaza los guardados. */
export async function traerCatalogos() {
  const organizacion = await leerMeta<string>('organizacion_actual');
  if (!organizacion) return;
  const { categorias, productos, proveedores, codigos } = await catalogosKiosco(organizacion);
  await db.transaction('rw', db.categorias, db.productos, db.proveedores, db.codigos, async () => {
    await db.categorias.clear();
    await db.categorias.bulkPut(categorias);
    await db.productos.bulkPut(
      productos.map((p) => ({ ...p, gtin14: p.gtin ? aGtin14(p.gtin) : null })),
    );
    await db.proveedores.bulkPut(proveedores);
    await db.codigos.clear();
    await db.codigos.bulkPut(codigos);
  });
}

/** Quedan guardadas: el kiosco tiene que poder recibir una orden aunque se corte la señal. */
async function traerPendientes() {
  const sede = await leerMeta<string>('sede_actual');
  if (!sede) return;
  const filas = await pendientesRecepcion(sede);
  // Sin el permiso no hay lista: quien solo compra también sincroniza.
  if (!filas) return;
  await db.transaction('rw', db.pendientes, async () => {
    await db.pendientes.clear();
    await db.pendientes.bulkPut(filas);
  });
}

/** El servidor manda sobre las recepciones sin operaciones pendientes en esta tablet. */
async function traerRecepciones() {
  const organizacion = await leerMeta<string>('organizacion_actual');
  if (!organizacion) return;
  const filas = await recepcionesAbiertas(organizacion, ESTADOS_ABIERTOS);

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

async function hidratar(f: RecepcionAbierta) {
  const contenido = await contenidoRecepcion(f.id);
  const lecturas = contenido.lecturas as Array<{
    item_id: string;
    tipo: TipoLectura;
    valor_crudo: string | null;
    motivo: string | null;
  }>;
  const adjuntos = { data: contenido.adjuntos as Array<{
    client_uuid: string;
    item_id: string | null;
    tipo: TipoAdjunto;
    storage_path: string;
    anulado_en: string | null;
  }> };

  const ultima = new Map<string, { tipo: TipoLectura; valor_crudo: string | null; motivo: string | null }>();
  for (const l of lecturas) ultima.set(l.item_id, l);

  const claves = new Map<string, string>();
  const locales: ItemLocal[] = (contenido.items as unknown as Array<{
    id: string;
    producto_id: string;
    lote: string | null;
    vencimiento: string | null;
    cant_recibida: number;
    cant_remito: number | null;
    cant_pedida: number | null;
    tipo_diferencia: ItemLocal['tipo_diferencia'];
    motivo_diferencia: string | null;
    creado_en: string;
    producto_nombre: string;
    tipo_medida: ItemLocal['tipo_medida'];
  }>).map((i) => {
    const key = `${f.id}|${i.producto_id}|${i.lote ?? ''}|${i.vencimiento ?? ''}`;
    claves.set(i.id, key);
    const u = ultima.get(i.id);
    return {
      key,
      server_id: i.id,
      recepcion_id: f.id,
      producto_id: i.producto_id,
      producto_nombre: i.producto_nombre,
      tipo_medida: i.tipo_medida,
      lote: i.lote,
      vencimiento: i.vencimiento,
      cant_recibida: Number(i.cant_recibida),
      cant_remito: i.cant_remito === null ? null : Number(i.cant_remito),
      cant_pedida: i.cant_pedida === null ? null : Number(i.cant_pedida),
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
      organizacion_id: f.organizacion_id,
      sede_id: f.sede_id,
      estado: f.estado as Estado,
      proveedor_id: f.proveedor_id,
      proveedor_nombre: f.proveedor_nombre,
      nro_remito: f.nro_remito,
      abierta_en: f.abierta_en,
      cerrada_en: f.cerrada_en,
      observacion: f.observacion,
      oc_id: f.oc_id,
      oc_numero: f.oc_numero,
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
    if (!(await sesionActual())) return;
    if (await vaciarCola()) {
      await traerCatalogos();
      await traerRecepciones();
      await traerPendientes();
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
