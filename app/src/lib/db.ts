import Dexie, { type Table } from 'dexie';

export type TipoMedida = 'UNIDAD' | 'PESO';
export type Estado =
  | 'ABIERTA'
  | 'EN_CONTROL'
  | 'CERRADA_OK'
  | 'CERRADA_CON_DIFERENCIAS'
  | 'VALIDADA'
  | 'INGRESADA_A_SISTEMA'
  | 'RECHAZADA';
export type TipoLectura = 'ESCANEO' | 'MANUAL' | 'PESAJE';
export type TipoAdjunto = 'REMITO' | 'RECHAZO' | 'MANUAL' | 'FIRMA_RECEPTOR' | 'FIRMA_TRANSPORTISTA';
export type TipoDiferencia = 'FALTANTE' | 'SOBRANTE' | 'RECHAZO';

/** sede_id nulo: el permiso vale en todas las sedes. */
export interface PermisoAsignado {
  permiso: string;
  sede_id: string | null;
}

export interface Perfil {
  user_id: string;
  tenant_id: string;
  sede_id: string;
  permisos: PermisoAsignado[];
  nombre: string;
}

/** Solo decide qué mostrar: quien autoriza es el servidor. */
export const tienePermiso = (perfil: Perfil | null, codigo: string) =>
  !!perfil?.permisos.some(
    (p) => p.permiso === codigo && (p.sede_id === null || p.sede_id === perfil.sede_id),
  );

export interface Categoria {
  id: string;
  nombre: string;
  orden: number;
}

export interface Producto {
  id: string;
  gtin: string | null;
  gtin14: string | null;
  nombre: string;
  tipo_medida: TipoMedida;
  requiere_lote: boolean;
  requiere_vencimiento: boolean;
  pendiente_validacion: boolean;
  categoria_id: string | null;
}

export interface Proveedor {
  id: string;
  nombre: string;
  cuit: string;
}

export interface RecepcionLocal {
  id: string;
  tenant_id: string;
  sede_id: string;
  estado: Estado;
  proveedor_id: string;
  proveedor_nombre: string;
  nro_remito: string;
  abierta_en: string;
  cerrada_en: string | null;
  observacion: string | null;
}

export interface ItemLocal {
  key: string;
  server_id: string | null;
  recepcion_id: string;
  producto_id: string;
  producto_nombre: string;
  tipo_medida: TipoMedida;
  lote: string | null;
  vencimiento: string | null;
  cant_recibida: number;
  cant_remito: number | null;
  tipo_diferencia: TipoDiferencia | null;
  motivo_diferencia: string | null;
  // Origen de la última lectura: los botones +/- lo repiten.
  ultimo_tipo: TipoLectura | null;
  ultimo_crudo: string | null;
  ultimo_motivo: string | null;
  orden: number;
}

export interface AdjuntoLocal {
  client_uuid: string;
  recepcion_id: string;
  item_key: string | null;
  tipo: TipoAdjunto;
  storage_path: string;
  extension: string;
  blob?: Blob;
  anulado: boolean;
}

export type TipoOp =
  | 'registrar_dispositivo'
  | 'alta_proveedor'
  | 'alta_producto'
  | 'abrir_recepcion'
  | 'subir_adjunto'
  | 'registrar_lectura'
  | 'fijar_control_item'
  | 'iniciar_control'
  | 'cerrar_recepcion'
  | 'reabrir_recepcion';

export interface OpCola {
  seq?: number;
  tipo: TipoOp;
  recepcion_id: string | null;
  args: Record<string, unknown>;
  item_key: string | null;
  creado_en: string;
  estado: 'pendiente' | 'error';
  error: string | null;
}

export interface Meta {
  clave: string;
  valor: unknown;
}

class EskemiaDb extends Dexie {
  categorias!: Table<Categoria, string>;
  productos!: Table<Producto, string>;
  proveedores!: Table<Proveedor, string>;
  recepciones!: Table<RecepcionLocal, string>;
  items!: Table<ItemLocal, string>;
  adjuntos!: Table<AdjuntoLocal, string>;
  cola!: Table<OpCola, number>;
  meta!: Table<Meta, string>;

  constructor() {
    super('eskemia-recepcion');
    this.version(1).stores({
      categorias: 'id, orden',
      productos: 'id, gtin14, categoria_id',
      proveedores: 'id, cuit',
      recepciones: 'id, estado',
      items: 'key, recepcion_id, server_id',
      adjuntos: 'client_uuid, recepcion_id, item_key',
      cola: '++seq, recepcion_id, estado',
      meta: 'clave',
    });
  }
}

export const db = new EskemiaDb();

export async function leerMeta<T>(clave: string): Promise<T | undefined> {
  return (await db.meta.get(clave))?.valor as T | undefined;
}

export function guardarMeta(clave: string, valor: unknown) {
  return db.meta.put({ clave, valor });
}

export function idDispositivo(): string {
  let id = localStorage.getItem('eskemia.dispositivo');
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem('eskemia.dispositivo', id);
  }
  return id;
}
