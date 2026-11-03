// Acciones del kiosco. Toda operación escribe primero en IndexedDB y encola su envío,
// en una sola transacción: si la tablet se apaga, no queda una mitad sin la otra.
import { redondear } from './formato';
import {
  db,
  idDispositivo,
  type ItemLocal,
  type OpCola,
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
  await db.transaction('rw', db.proveedores, db.cola, async () => {
    await db.proveedores.put({ id, nombre, cuit });
    await db.cola.add(op('alta_proveedor', null, { p_id: id, p_nombre: nombre, p_cuit: cuit }));
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
  await db.transaction('rw', db.productos, db.cola, async () => {
    await db.productos.put(producto);
    await db.cola.add(
      op('alta_producto', null, {
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
  datos: { proveedor_id: string; proveedor_nombre: string; nro_remito: string; foto: Blob },
): Promise<string> {
  const id = crypto.randomUUID();
  const ahora = new Date().toISOString();
  await db.transaction('rw', db.recepciones, db.adjuntos, db.cola, async () => {
    await db.recepciones.put({
      id,
      tenant_id: perfil.tenant_id,
      sede_id: perfil.sede_id,
      estado: 'ABIERTA',
      proveedor_id: datos.proveedor_id,
      proveedor_nombre: datos.proveedor_nombre,
      nro_remito: datos.nro_remito,
      abierta_en: ahora,
      cerrada_en: null,
      observacion: null,
    });
    await db.cola.add(
      op('abrir_recepcion', id, {
        p_id: id,
        p_proveedor_id: datos.proveedor_id,
        p_nro_remito: datos.nro_remito,
        p_sede_id: perfil.sede_id,
        p_abierta_en: ahora,
        p_dispositivo_id: idDispositivo(),
      }),
    );
    await encolarAdjunto(perfil, id, 'REMITO', datos.foto, 'jpg', null);
  });
  pedirSincronizacion();
  return id;
}

async function encolarAdjunto(
  perfil: Pick<Perfil, 'tenant_id' | 'sede_id'>,
  recepcionId: string,
  tipo: TipoAdjunto,
  blob: Blob,
  extension: string,
  itemKey: string | null,
) {
  const client_uuid = crypto.randomUUID();
  const storage_path = `${perfil.tenant_id}/${perfil.sede_id}/${recepcionId}/${client_uuid}.${extension}`;
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
  cantRemito: number,
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
  const adjuntos = (await db.adjuntos.where('recepcion_id').equals(recepcionId).toArray()).filter(
    (a) => !a.anulado,
  );
  return {
    foto_remito: adjuntos.some((a) => a.tipo === 'REMITO'),
    tiene_items: items.length > 0,
    cantidades_remito: items.every((i) => i.cant_remito !== null),
    motivos_diferencias: items.every((i) => {
      const dif = i.cant_remito === null ? 0 : redondear(i.cant_recibida - i.cant_remito);
      if (dif === 0) return true;
      if (!i.motivo_diferencia?.trim() || !i.tipo_diferencia) return false;
      return i.tipo_diferencia === 'SOBRANTE' ? dif > 0 : dif < 0;
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
    const conDiferencias = items.some(
      (i) => i.cant_remito !== null && redondear(i.cant_recibida - i.cant_remito) !== 0,
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
