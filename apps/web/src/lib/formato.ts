// Eskemia · Formatos de la app: montos, cantidades, fechas y CUIT, en es-AR.
//
// Qué hace: es el único lugar donde se formatean números para mostrar. Los montos salen
// SOLO de formatearMonto() (CLAUDE.md, Estética v2): ningún componente arma "$ " a mano.
// Dónde encaja: lo usan todas las pantallas y el PDF de la orden.
import type { Estado, TipoMedida } from './db';

const numero = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 3 });
const moneda = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/**
 * Monto en pesos con el formato de Eskemia: `$ 1.240,50`, negativos `-$ 1.240,50`.
 * Redondea a 2 decimales (mitad hacia afuera, como Intl). Acepta el texto numérico que
 * devuelve la base para columnas numeric.
 */
export function formatearMonto(valor: number | string): string {
  const n = typeof valor === 'string' ? Number(valor) : valor;
  if (!Number.isFinite(n)) return '—';
  const texto = moneda.format(Math.abs(n));
  return texto === '0,00' || n >= 0 ? `$ ${texto}` : `-$ ${texto}`;
}
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
