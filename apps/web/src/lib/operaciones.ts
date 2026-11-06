// Eskemia · Acciones del kiosco de Recepción.
//
// Qué hace: toda operación escribe primero en IndexedDB y encola su envío, en una sola
// transacción: si la tablet se apaga, no queda una mitad sin la otra.
// Dónde encaja: lib/sync.ts envía la cola por @eskemia/cliente-api. Los argumentos usan
// los nombres de las RPC del esquema api (p_organizacion_id primero donde corresponde).
import { redondear } from './formato';
import {
  db,
  idDispositivo,
  organizacionActual,
  type ItemLocal,
  type OpCola,
  type PendienteRecepcion,
  type Perfil,
  type Producto,
  type TipoAdjunto,
  type TipoDiferencia,
  type TipoLectura,
  type TipoMedida,
  type TipoOp,
} from './db';
import { aGtin14 } from './codigos';
import { pedirSincronizacion } from './sync';

function op(
  tipo: TipoOp,
  recepcion_id: string | null,
  args: Record<string, unknown>,
  item_key: string | null = null,
): OpCola {
  return {
    tipo,
    recepcion_id,
    args,
    item_key,
    creado_en: new Date().toISOString(),
    estado: 'pendiente',
    error: null,
  };
}

export const claveItem = (
  recepcionId: string,
  productoId: string,
  lote: string | null,
  vencimiento: string | null,
) => `${recepcionId}|${productoId}|${lote ?? ''}|${vencimiento ?? ''}`;

export async function asegurarDispositivo(perfil: Perfil) {
  const clave = `dispositivo:${perfil.user_id}`;
  if (await db.meta.get(clave)) return;
  const id = idDispositivo();
  await db.transaction('rw', db.cola, db.meta, async () => {
    await db.cola.add(
      op('registrar_dispositivo', null, {
        p_organizacion_id: perfil.organizacion_id,
        p_id: id,
        p_nombre: `Tablet ${id.slice(0, 8)}`,
        p_sede_id: perfil.sede_id,
      }),
    );
    await db.meta.put({ clave, valor: true });
  });
  pedirSincronizacion();
}

export async function altaProveedor(nombre: string, cuit: string): Promise<string> {
  const existente = await db.proveedores.where('cuit').equals(cuit).first();
  if (existente) return existente.id;
  const id = crypto.randomUUID();
  const organizacion = await organizacionActual();
  await db.transaction('rw', db.proveedores, db.cola, async () => {
    await db.proveedores.put({ id, nombre, cuit });
    await db.cola.add(
      op('alta_proveedor', null, { p_organizacion_id: organizacion, p_id: id, p_nombre: nombre, p_cuit: cuit }),
    );
  });
  pedirSincronizacion();
  return id;
}

export async function altaProducto(datos: {
  nombre: string;
  gtin: string;
  tipo_medida: TipoMedida;
  requiere_lote: boolean;
  requiere_vencimiento: boolean;
}): Promise<Producto> {
  const producto: Producto = {
    id: crypto.randomUUID(),
    gtin: datos.gtin,
    gtin14: aGtin14(datos.gtin),
    nombre: datos.nombre,
    tipo_medida: datos.tipo_medida,
    requiere_lote: datos.requiere_lote,
    requiere_vencimiento: datos.requiere_vencimiento,
    pendiente_validacion: true,
    categoria_id: null,
  };
  const organizacion = await organizacionActual();
  await db.transaction('rw', db.productos, db.cola, async () => {
    await db.productos.put(producto);
    await db.cola.add(
      op('alta_producto', null, {
        p_organizacion_id: organizacion,
        p_id: producto.id,
        p_nombre: datos.nombre,
        p_gtin: datos.gtin,
        p_tipo_medida: datos.tipo_medida,
        p_requiere_lote: datos.requiere_lote,
        p_requiere_vencimiento: datos.requiere_vencimiento,
      }),
    );
  });
  pedirSincronizacion();
  return producto;
}

export async function abrirRecepcion(
  perfil: Perfil,
  datos: {
    proveedor_id: string;
    proveedor_nombre: string;
    nro_remito: string;
    foto: Blob;
    oc?: PendienteRecepcion | null;
  },
): Promise<string> {
  const id = crypto.randomUUID();
  const ahora = new Date().toISOString();
  await db.transaction('rw', db.recepciones, db.adjuntos, db.items, db.cola, async () => {
    await db.recepciones.put({
      id,
      organizacion_id: perfil.organizacion_id,
      sede_id: perfil.sede_id,
      estado: 'ABIERTA',
      proveedor_id: datos.proveedor_id,
      proveedor_nombre: datos.proveedor_nombre,
      nro_remito: datos.nro_remito,
      abierta_en: ahora,
      cerrada_en: null,
      observacion: null,
      oc_id: datos.oc?.id ?? null,
      oc_numero: datos.oc?.numero ?? null,
    });
    // Lo que falta recibir de la orden: el operario compara contra esto.
    await db.items.bulkPut(
      (datos.oc?.items ?? [])
        .filter((i) => i.saldo > 0)
        .map((i, n) => ({
          key: claveItem(id, i.producto_id, null, null),
          server_id: null,
          recepcion_id: id,
          producto_id: i.producto_id,
          producto_nombre: i.nombre,
          tipo_medida: i.tipo_medida,
          lote: null,
          vencimiento: null,
          cant_recibida: 0,
          cant_remito: null,
          cant_pedida: i.saldo,
          tipo_diferencia: null,
          motivo_diferencia: null,
          ultimo_tipo: null,
          ultimo_crudo: null,
          ultimo_motivo: null,
          orden: n,
        })),
    );
    await db.cola.add(
      op('abrir_recepcion', id, {
        p_organizacion_id: perfil.organizacion_id,
        p_id: id,
        p_proveedor_id: datos.proveedor_id,
        p_nro_remito: datos.nro_remito,
        p_sede_id: perfil.sede_id,
        p_abierta_en: ahora,
        p_dispositivo_id: idDispositivo(),
        p_oc_id: datos.oc?.id ?? null,
      }),
    );
    await encolarAdjunto(perfil, id, 'REMITO', datos.foto, 'jpg', null);
  });
  pedirSincronizacion();
  return id;
}

async function encolarAdjunto(
  perfil: Pick<Perfil, 'organizacion_id' | 'sede_id'>,
  recepcionId: string,
  tipo: TipoAdjunto,
  blob: Blob,
  extension: string,
  itemKey: string | null,
) {
  const client_uuid = crypto.randomUUID();
  // La política de Storage exige que la ruta empiece por la organización.
  const storage_path = `${perfil.organizacion_id}/${perfil.sede_id}/${recepcionId}/${client_uuid}.${extension}`;
  await db.adjuntos.put({
    client_uuid,
    recepcion_id: recepcionId,
    item_key: itemKey,
    tipo,
    storage_path,
    extension,
    blob,
    anulado: false,
  });
  await db.cola.add(
    op(
      'subir_adjunto',
      recepcionId,
      {
        p_client_uuid: client_uuid,
        p_recepcion_id: recepcionId,
        p_tipo: tipo,
        p_storage_path: storage_path,
        p_dispositivo_id: idDispositivo(),
      },
      itemKey,
    ),
  );
}

export async function agregarAdjunto(
  recepcionId: string,
  tipo: TipoAdjunto,
  blob: Blob,
  extension: string,
  itemKey: string | null = null,
) {
  const recepcion = await db.recepciones.get(recepcionId);
  if (!recepcion) throw new Error('Recepción inexistente');
  await db.transaction('rw', db.adjuntos, db.cola, async () => {
    if (tipo === 'FIRMA_RECEPTOR' || tipo === 'FIRMA_TRANSPORTISTA') {
      await db.adjuntos
        .where('recepcion_id')
        .equals(recepcionId)
        .filter((a) => a.tipo === tipo)
        .modify({ anulado: true });
    }
    await encolarAdjunto(recepcion, recepcionId, tipo, blob, extension, itemKey);
  });
  pedirSincronizacion();
}

export interface DatosLectura {
  recepcion_id: string;
  producto: Producto;
  cantidad: number;
  tipo: TipoLectura;
  valor_crudo: string | null;
  lote: string | null;
  vencimiento: string | null;
  motivo: string | null;
}

/** Suma (o resta) una lectura. Devuelve el ítem actualizado, o null si quedaría negativo. */
export async function registrarLectura(d: DatosLectura): Promise<ItemLocal | null> {
  const key = claveItem(d.recepcion_id, d.producto.id, d.lote, d.vencimiento);
  const item = await db.transaction('rw', db.items, db.cola, async () => {
    const previo = await db.items.get(key);
    const cantidad = redondear((previo?.cant_recibida ?? 0) + d.cantidad);
    if (cantidad < 0) return null;
    const nuevo: ItemLocal = {
      key,
      server_id: previo?.server_id ?? null,
      recepcion_id: d.recepcion_id,
      producto_id: d.producto.id,
      producto_nombre: d.producto.nombre,
      tipo_medida: d.producto.tipo_medida,
      lote: d.lote,
      vencimiento: d.vencimiento,
      cant_recibida: cantidad,
      cant_remito: previo?.cant_remito ?? null,
      cant_pedida: previo?.cant_pedida ?? null,
      tipo_diferencia: previo?.tipo_diferencia ?? null,
      motivo_diferencia: previo?.motivo_diferencia ?? null,
      ultimo_tipo: d.tipo,
      ultimo_crudo: d.valor_crudo,
      ultimo_motivo: d.motivo,
      orden: Date.now(),
    };
    await db.items.put(nuevo);
    await db.cola.add(
      op(
        'registrar_lectura',
        d.recepcion_id,
        {
          p_client_uuid: crypto.randomUUID(),
          p_recepcion_id: d.recepcion_id,
          p_tipo: d.tipo,
          p_producto_id: d.producto.id,
          p_cantidad: d.cantidad,
          p_valor_crudo: d.valor_crudo,
          p_lote: d.lote,
          p_vencimiento: d.vencimiento,
          p_motivo: d.motivo,
          p_dispositivo_id: idDispositivo(),
          p_leido_en: new Date().toISOString(),
        },
        key,
      ),
    );
    return nuevo;
  });
  if (item) pedirSincronizacion();
  return item;
}

/** Repite el origen de la última lectura del ítem para un ajuste con +/- o teclado. */
export async function ajustarItem(item: ItemLocal, delta: number) {
  const producto = await db.productos.get(item.producto_id);
  if (!producto) return null;
  const tipo = item.ultimo_tipo ?? 'ESCANEO';
  return registrarLectura({
    recepcion_id: item.recepcion_id,
    producto,
    cantidad: delta,
    tipo,
    valor_crudo: tipo === 'MANUAL' ? null : (item.ultimo_crudo ?? producto.gtin ?? producto.id),
    lote: item.lote,
    vencimiento: item.vencimiento,
    motivo: item.ultimo_motivo,
  });
}

export async function iniciarControl(recepcionId: string) {
  await db.transaction('rw', db.recepciones, db.cola, async () => {
    const r = await db.recepciones.get(recepcionId);
    if (r?.estado !== 'ABIERTA') return;
    await db.recepciones.update(recepcionId, { estado: 'EN_CONTROL' });
    await db.cola.add(
      op('iniciar_control', recepcionId, {
        p_recepcion_id: recepcionId,
        p_dispositivo_id: idDispositivo(),
      }),
    );
  });
  pedirSincronizacion();
}

export async function fijarControl(
  recepcionId: string,
  producto: Pick<Producto, 'id' | 'nombre' | 'tipo_medida'>,
  lote: string | null,
  vencimiento: string | null,
  cantRemito: number | null,
  tipo: TipoDiferencia | null,
  motivo: string | null,
) {
  const key = claveItem(recepcionId, producto.id, lote, vencimiento);
  await db.transaction('rw', db.items, db.cola, async () => {
    const previo = await db.items.get(key);
    await db.items.put({
      key,
      server_id: previo?.server_id ?? null,
      recepcion_id: recepcionId,
      producto_id: producto.id,
      producto_nombre: producto.nombre,
      tipo_medida: producto.tipo_medida,
      lote,
      vencimiento,
      cant_recibida: previo?.cant_recibida ?? 0,
      cant_remito: cantRemito,
      cant_pedida: previo?.cant_pedida ?? null,
      tipo_diferencia: tipo,
      motivo_diferencia: motivo,
      ultimo_tipo: previo?.ultimo_tipo ?? null,
      ultimo_crudo: previo?.ultimo_crudo ?? null,
      ultimo_motivo: previo?.ultimo_motivo ?? null,
      orden: previo?.orden ?? Date.now(),
    });
    await db.cola.add(
      op(
        'fijar_control_item',
        recepcionId,
        {
          p_recepcion_id: recepcionId,
          p_producto_id: producto.id,
          p_cant_remito: cantRemito,
          p_tipo_diferencia: tipo,
          p_motivo: motivo,
          p_lote: lote,
          p_vencimiento: vencimiento,
        },
        key,
      ),
    );
  });
  pedirSincronizacion();
}

/**
 * Recibido menos pedido del producto, sumando todas sus líneas: puede venir en varios lotes.
 * Nulo si la recepción no tiene orden de compra.
 */
export function diferenciaPedido(items: ItemLocal[], productoId: string, conOrden: boolean): number | null {
  if (!conOrden) return null;
  const lineas = items.filter((i) => i.producto_id === productoId);
  return redondear(
    lineas.reduce((n, i) => n + i.cant_recibida, 0) - lineas.reduce((n, i) => n + (i.cant_pedida ?? 0), 0),
  );
}

export interface ChecklistLocal {
  foto_remito: boolean;
  tiene_items: boolean;
  cantidades_remito: boolean;
  motivos_diferencias: boolean;
  fotos_manuales: boolean;
}

/** Misma regla que app_private.checklist en Postgres, sin las firmas. */
export async function checklistLocal(recepcionId: string): Promise<ChecklistLocal> {
  const items = await db.items.where('recepcion_id').equals(recepcionId).toArray();
  const conOrden = !!(await db.recepciones.get(recepcionId))?.oc_id;
  const adjuntos = (await db.adjuntos.where('recepcion_id').equals(recepcionId).toArray()).filter(
    (a) => !a.anulado,
  );
  return {
    foto_remito: adjuntos.some((a) => a.tipo === 'REMITO'),
    tiene_items: items.length > 0,
    // Con orden de compra no se carga remito: se compara contra lo pedido.
    cantidades_remito: conOrden || items.every((i) => i.cant_remito !== null),
    motivos_diferencias: items.every((i) => {
      const dif = i.cant_remito === null ? 0 : redondear(i.cant_recibida - i.cant_remito);
      if ((diferenciaPedido(items, i.producto_id, conOrden) ?? 0) !== 0) {
        const delProducto = items.filter((o) => o.producto_id === i.producto_id);
        if (!delProducto.some((o) => o.motivo_diferencia?.trim() && o.tipo_diferencia)) return false;
      }
      if (dif === 0) return true;
      if (!i.motivo_diferencia?.trim() || !i.tipo_diferencia) return false;
      if (i.tipo_diferencia === 'SOBRANTE') return dif > 0;
      if (i.tipo_diferencia === 'FALTANTE' || i.tipo_diferencia === 'RECHAZO') return dif < 0;
      return true;
    }),
    fotos_manuales: items.every(
      (i) =>
        i.ultimo_tipo !== 'MANUAL' ||
        adjuntos.some((a) => a.tipo === 'MANUAL' && a.item_key === i.key),
    ),
  };
}

export async function cerrarRecepcion(
  recepcionId: string,
  firmaReceptor: Blob,
  firmaTransportista: Blob,
): Promise<'CERRADA_OK' | 'CERRADA_CON_DIFERENCIAS'> {
  await agregarAdjunto(recepcionId, 'FIRMA_RECEPTOR', firmaReceptor, 'png');
  await agregarAdjunto(recepcionId, 'FIRMA_TRANSPORTISTA', firmaTransportista, 'png');
  const ahora = new Date().toISOString();
  const estado = await db.transaction('rw', db.recepciones, db.items, db.cola, async () => {
    const items = await db.items.where('recepcion_id').equals(recepcionId).toArray();
    const conOrden = !!(await db.recepciones.get(recepcionId))?.oc_id;
    const conDiferencias = items.some(
      (i) =>
        (i.cant_remito !== null && redondear(i.cant_recibida - i.cant_remito) !== 0) ||
        (diferenciaPedido(items, i.producto_id, conOrden) ?? 0) !== 0,
    );
    const nuevo = conDiferencias ? ('CERRADA_CON_DIFERENCIAS' as const) : ('CERRADA_OK' as const);
    await db.recepciones.update(recepcionId, { estado: nuevo, cerrada_en: ahora });
    await db.cola.add(
      op('cerrar_recepcion', recepcionId, {
        p_recepcion_id: recepcionId,
        p_cerrada_en: ahora,
        p_dispositivo_id: idDispositivo(),
      }),
    );
    return nuevo;
  });
  pedirSincronizacion();
  return estado;
}

export async function reabrirRecepcion(recepcionId: string) {
  await db.transaction('rw', db.recepciones, db.adjuntos, db.cola, async () => {
    await db.recepciones.update(recepcionId, { estado: 'EN_CONTROL', cerrada_en: null });
    await db.adjuntos
      .where('recepcion_id')
      .equals(recepcionId)
      .filter((a) => a.tipo === 'FIRMA_RECEPTOR' || a.tipo === 'FIRMA_TRANSPORTISTA')
      .modify({ anulado: true });
    await db.cola.add(
      op('reabrir_recepcion', recepcionId, {
        p_recepcion_id: recepcionId,
        p_dispositivo_id: idDispositivo(),
      }),
    );
  });
  pedirSincronizacion();
}
