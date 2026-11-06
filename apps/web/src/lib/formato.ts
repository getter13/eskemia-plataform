import type { Estado, TipoMedida } from './db';

const numero = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 3 });
const fechaHora = new Intl.DateTimeFormat('es-AR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Argentina/Buenos_Aires',
});

export const formatoNumero = (n: number) => numero.format(n);

export function formatoCantidad(n: number, medida: TipoMedida): string {
  if (medida === 'PESO') return `${numero.format(n)} kg`;
  return `${numero.format(n)} ${n === 1 ? 'unidad' : 'unidades'}`;
}

export const unidadCorta = (medida: TipoMedida) => (medida === 'PESO' ? 'kg' : 'unidades');

export const formatoFechaHora = (iso: string) => fechaHora.format(new Date(iso));

/** aaaa-mm-dd a dd/mm/aaaa, sin pasar por zona horaria. */
export function formatoFecha(iso: string): string {
  const [a, m, d] = iso.split('-');
  return `${d}/${m}/${a}`;
}

export function formatoCuit(cuit: string): string {
  return `${cuit.slice(0, 2)}-${cuit.slice(2, 10)}-${cuit.slice(10)}`;
}

export const redondear = (n: number) => Math.round(n * 1000) / 1000;

export const ETIQUETA_ESTADO: Record<Estado, string> = {
  ABIERTA: 'Abierta',
  EN_CONTROL: 'En control',
  CERRADA_OK: 'Cerrada sin diferencias',
  CERRADA_CON_DIFERENCIAS: 'Cerrada con diferencias',
  VALIDADA: 'Validada',
  INGRESADA_A_SISTEMA: 'Ingresada a sistema',
  RECHAZADA: 'Rechazada',
};
