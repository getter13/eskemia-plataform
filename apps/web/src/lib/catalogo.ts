// Eskemia · Catálogo del marketplace de Compras.
//
// Qué hace: se trae entero por @eskemia/cliente-api y se guarda en el dispositivo, así
// abre sin señal y la búsqueda (tolerante a errores de tipeo) responde al instante. Agrupa
// el carrito por proveedor: cada grupo será una orden de compra.
// Dónde encaja: pantallas de Compras (Marketplace, Pedido).
import { useCallback, useEffect, useState } from 'react';
import {
  catalogoCompras,
  evaluarAprobacion,
  type EvaluacionOrden,
  type Oferta,
  type ProductoCatalogo,
} from '@eskemia/cliente-api';
import { guardarMeta, leerMeta } from './db';

export type { EvaluacionOrden, Oferta, ProductoCatalogo };

const moneda = new Intl.NumberFormat('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
export const formatoMoneda = (n: number) => `$ ${moneda.format(n)}`;

export function useCatalogo(sedeId: string | undefined) {
  const [productos, setProductos] = useState<ProductoCatalogo[] | null>(null);
  const [sinConexion, setSinConexion] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    if (!sedeId) return;
    const clave = `catalogo:${sedeId}`;
    const guardado = await leerMeta<ProductoCatalogo[]>(clave);
    if (guardado) setProductos((actual) => actual ?? guardado);

    let lista: ProductoCatalogo[];
    try {
      lista = await catalogoCompras(sedeId);
    } catch {
      setSinConexion(true);
      if (!guardado) setError('No se pudo cargar el catálogo. Revisá la conexión.');
      return;
    }
    setProductos(lista);
    setSinConexion(false);
    setError(null);
    await guardarMeta(clave, lista);
  }, [sedeId]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  return { productos, sinConexion, error, recargar: cargar };
}

export const normalizar = (texto: string) =>
  texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();

/** Cambios necesarios para pasar de a a b, contando como uno el de dos letras invertidas. */
function distancia(a: string, b: string) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array<number>(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j += 1) d[0][j] = j;
  for (let i = 1; i <= a.length; i += 1) {
    for (let j = 1; j <= b.length; j += 1) {
      const costo = a[i - 1] === b[j - 1] ? 0 : 1;
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + costo);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return d[a.length][b.length];
}

const LARGO_MINIMO_TOLERANTE = 4;
const LARGO_DOS_ERRORES = 7;

/** Compara también con el comienzo de la palabra, para corregir mientras se escribe. */
function pareceA(token: string, palabra: string) {
  const tolerancia = token.length >= LARGO_DOS_ERRORES ? 2 : 1;
  return (
    distancia(token, palabra) <= tolerancia || distancia(token, palabra.slice(0, token.length)) <= tolerancia
  );
}

/** Tolera errores de tipeo en palabras, no en códigos: un SKU con un dígito distinto es otro producto. */
export function coincide(busqueda: string, texto: string) {
  const objetivo = normalizar(texto);
  const palabras = objetivo.split(/\s+/);
  return normalizar(busqueda)
    .split(/\s+/)
    .filter(Boolean)
    .every(
      (token) =>
        objetivo.includes(token) ||
        (token.length >= LARGO_MINIMO_TOLERANTE && !/\d/.test(token) && palabras.some((p) => pareceA(token, p))),
    );
}

const textoBuscable = (p: ProductoCatalogo) =>
  [p.nombre, p.sku, p.categoria, p.rubro, ...p.ofertas.flatMap((o) => [o.proveedor, o.proveedor_codigo])]
    .filter(Boolean)
    .join(' ');

export function filtrarCatalogo(productos: ProductoCatalogo[], busqueda: string, rubroId: string | null) {
  const porRubro = rubroId ? productos.filter((p) => p.rubro_id === rubroId) : productos;
  if (!busqueda.trim()) return porRubro;
  const encontrados = porRubro.filter((p) => coincide(busqueda, textoBuscable(p)));
  // Lo que coincide literalmente en el nombre va primero.
  const literal = normalizar(busqueda);
  return [
    ...encontrados.filter((p) => normalizar(p.nombre).includes(literal)),
    ...encontrados.filter((p) => !normalizar(p.nombre).includes(literal)),
  ];
}

export function rubrosDe(productos: ProductoCatalogo[]) {
  const vistos = new Map<string, string>();
  for (const p of productos) if (p.rubro_id && p.rubro) vistos.set(p.rubro_id, p.rubro);
  return [...vistos].map(([id, nombre]) => ({ id, nombre }));
}

export interface LineaPedido {
  producto: ProductoCatalogo;
  oferta: Oferta;
  cantidad: number;
  subtotal: number;
}

export interface GrupoProveedor {
  proveedorId: string;
  proveedor: string;
  montoMinimo: number | null;
  plazoEntregaDias: number | null;
  lineas: LineaPedido[];
  subtotal: number;
  sinPrecio: boolean;
}

/** Un grupo por proveedor: al confirmar, cada uno será una orden de compra. */
export function agruparPedido(productos: ProductoCatalogo[], lineas: Record<string, number>) {
  const grupos = new Map<string, GrupoProveedor>();
  const encontradas = new Set<string>();

  for (const producto of productos) {
    for (const oferta of producto.ofertas) {
      const cantidad = lineas[oferta.id];
      if (!cantidad) continue;
      encontradas.add(oferta.id);
      const subtotal = (oferta.precio ?? 0) * cantidad;
      const grupo = grupos.get(oferta.proveedor_id) ?? {
        proveedorId: oferta.proveedor_id,
        proveedor: oferta.proveedor,
        montoMinimo: oferta.monto_minimo,
        plazoEntregaDias: oferta.plazo_entrega_dias,
        lineas: [],
        subtotal: 0,
        sinPrecio: false,
      };
      grupo.lineas.push({ producto, oferta, cantidad, subtotal });
      grupo.subtotal += subtotal;
      grupo.sinPrecio ||= oferta.precio === null;
      grupos.set(oferta.proveedor_id, grupo);
    }
  }

  return {
    grupos: [...grupos.values()].sort((a, b) => a.proveedor.localeCompare(b.proveedor)),
    noDisponibles: Object.keys(lineas).filter((id) => !encontradas.has(id)),
  };
}

/** Anticipa si la orden de ese proveedor pedirá aprobación; null si no se pudo saber. */
export async function evaluarOrden(sedeId: string, grupo: GrupoProveedor): Promise<EvaluacionOrden | null> {
  try {
    return await evaluarAprobacion(
      sedeId,
      grupo.lineas.map((l) => ({ producto_id: l.producto.producto_id, subtotal: l.subtotal })),
    );
  } catch {
    return null;
  }
}
