// Eskemia · Errores de la API.
//
// Qué hace: convierte los errores de PostgREST, Auth y Storage en ErrorApi, con el código
// de negocio que manda la base (SIN_PERMISO, PRECONDICION, NO_ENCONTRADO,
// MODULO_DESHABILITADO), un mensaje listo para mostrar y si conviene reintentar.
// Dónde encaja: todas las funciones del paquete lanzan ErrorApi; la cola offline del
// kiosco usa `transitorio` para decidir si espera o marca la operación con error.

/** Código de negocio de las RPC (prefijo del mensaje en la base). */
export type CodigoNegocio = 'SIN_PERMISO' | 'PRECONDICION' | 'NO_ENCONTRADO' | 'MODULO_DESHABILITADO';

/** Error de la API con lo necesario para mostrarlo y decidir si reintentar. */
export class ErrorApi extends Error {
  /** Código de negocio, si la base lo mandó; null para errores técnicos. */
  readonly codigo: CodigoNegocio | null;
  /** SQLSTATE o código de PostgREST/Storage, tal como llegó. */
  readonly codigoTecnico: string;
  /** true si es de red, del servidor o de sesión vencida: reintentar puede funcionar. */
  readonly transitorio: boolean;

  constructor(mensaje: string, codigo: CodigoNegocio | null, codigoTecnico: string, transitorio: boolean) {
    super(mensaje);
    this.name = 'ErrorApi';
    this.codigo = codigo;
    this.codigoTecnico = codigoTecnico;
    this.transitorio = transitorio;
  }
}

/** Forma común de los errores de supabase-js (PostgREST, Auth y Storage). */
export interface ErrorCrudo {
  message: string;
  code?: string;
  status?: number | string;
  statusCode?: number | string;
}

const PREFIJO = /^(SIN_PERMISO|PRECONDICION|NO_ENCONTRADO|MODULO_DESHABILITADO):\s*/;

/** Convierte un error crudo de supabase-js en ErrorApi. */
export function aErrorApi(e: ErrorCrudo): ErrorApi {
  const codigoTecnico = String(e.code ?? e.statusCode ?? e.status ?? '');
  const coincidencia = e.message.match(PREFIJO);
  const transitorio =
    codigoTecnico === '' ||
    codigoTecnico.startsWith('08') ||
    codigoTecnico.startsWith('5') ||
    codigoTecnico === 'PGRST301' ||
    codigoTecnico === 'PGRST303' ||
    /fetch|network|timeout|jwt|token/i.test(e.message);
  return new ErrorApi(
    e.message.replace(PREFIJO, ''),
    (coincidencia?.[1] as CodigoNegocio | undefined) ?? null,
    codigoTecnico,
    transitorio && !coincidencia,
  );
}

/** Devuelve data o lanza ErrorApi. Para los resultados { data, error } de supabase-js. */
export function exigir<T>(r: { data: T | null; error: ErrorCrudo | null }): T {
  if (r.error) throw aErrorApi(r.error);
  return r.data as T;
}

/** Lanza ErrorApi si el resultado trae error (para llamadas sin datos útiles). */
export function sinError(r: { error: ErrorCrudo | null }): void {
  if (r.error) throw aErrorApi(r.error);
}
