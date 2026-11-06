// Eskemia · Importación CSV del catálogo de Compras.
//
// Qué hace: define los seis archivos (columnas y validación Zod), lee el CSV como lo
// exporta Excel en Argentina y manda las filas válidas a la base. El formato se valida
// acá; las referencias (rubro existente, CUIT cargado…), en el servidor.
// Dónde encaja: pantalla Admin > Importar. Exige compras.catalogo.gestionar.
import Papa from 'papaparse';
import { z } from 'zod';
import {
  importarCatalogo as importar,
  type ErrorFila,
  type ResultadoImportacion,
  type TipoImportacion,
} from '@eskemia/cliente-api';
import { organizacionActual } from './db';

export type { ErrorFila, ResultadoImportacion, TipoImportacion };
export type FilaImportacion = Record<string, unknown> & { fila: number };

/** Excel en Argentina exporta "1.240,50"; también se acepta "1240.50". */
export function aNumero(texto: string): number {
  const v = texto.replace(/[$\s]/g, '');
  if (v.includes(',')) return Number(v.replace(/\./g, '').replace(',', '.'));
  if (/^\d{1,3}(\.\d{3})+$/.test(v)) return Number(v.replace(/\./g, ''));
  return v === '' ? NaN : Number(v);
}

const requerido = (nombre: string) => z.string({ message: `Falta ${nombre}` }).trim().min(1, `Falta ${nombre}`);
const opcional = z.string().trim().optional().transform((v) => v || null);

const numero = (nombre: string, minimo: number) =>
  z
    .string()
    .trim()
    .refine((v) => aNumero(v) >= minimo, `${nombre} no es válido`)
    .transform(aNumero);
const numeroOpcional = (nombre: string, minimo = 0) =>
  z
    .string()
    .trim()
    .optional()
    .refine((v) => !v || aNumero(v) >= minimo, `${nombre} no es válido`)
    .transform((v) => (v ? aNumero(v) : null));
const enteroOpcional = (nombre: string) =>
  numeroOpcional(nombre).refine((v) => v === null || Number.isInteger(v), `${nombre} debe ser un número entero`);

const siNo = (nombre: string) =>
  z
    .string()
    .trim()
    .optional()
    .refine((v) => !v || /^(si|sí|s|no|n)$/i.test(v), `${nombre} debe decir sí o no`)
    .transform((v) => !!v && /^(si|sí|s)$/i.test(v));

const opcion = <T extends readonly [string, ...string[]]>(nombre: string, valores: T) =>
  z
    .string()
    .trim()
    .toUpperCase()
    .pipe(z.enum(valores, { message: `${nombre} debe ser ${valores.join(', ')}` }));

const cuit = z
  .string()
  .trim()
  .transform((v) => v.replace(/\D/g, ''))
  .refine((v) => v.length === 11, 'El CUIT debe tener 11 dígitos');

const TIPOS_CODIGO = ['EAN13', 'EAN8', 'DUN14', 'GS1_128', 'UPC', 'INTERNO'] as const;

export interface Columna {
  nombre: string;
  requerida?: boolean;
  ayuda: string;
}

export interface DefinicionImportacion {
  tipo: TipoImportacion;
  etiqueta: string;
  descripcion: string;
  columnas: Columna[];
  esquema: z.ZodType<Record<string, unknown>>;
}

// En el orden en que hay que cargarlos: cada archivo usa lo que cargó el anterior.
export const IMPORTACIONES: DefinicionImportacion[] = [
  {
    tipo: 'rubros',
    etiqueta: '1. Rubros',
    descripcion: 'Agrupan las categorías. Por ejemplo: Comida, Limpieza, Descartables.',
    columnas: [
      { nombre: 'rubro', requerida: true, ayuda: 'Nombre del rubro' },
      { nombre: 'orden', ayuda: 'Posición en el listado' },
    ],
    esquema: z.object({ rubro: requerido('el rubro'), orden: enteroOpcional('El orden') }),
  },
  {
    tipo: 'categorias',
    etiqueta: '2. Categorías',
    descripcion: 'Cada categoría pertenece a un rubro. Por ejemplo: Proteínas o Lácteos en Comida.',
    columnas: [
      { nombre: 'rubro', requerida: true, ayuda: 'Rubro ya cargado' },
      { nombre: 'categoria', requerida: true, ayuda: 'Nombre de la categoría' },
      { nombre: 'orden', ayuda: 'Posición en el listado' },
    ],
    esquema: z.object({
      rubro: requerido('el rubro'),
      categoria: requerido('la categoría'),
      orden: enteroOpcional('El orden'),
    }),
  },
  {
    tipo: 'productos',
    etiqueta: '3. Productos',
    descripcion: 'Solo el nombre, sin tamaño ni envase: eso va en las presentaciones.',
    columnas: [
      { nombre: 'rubro', requerida: true, ayuda: 'Rubro ya cargado' },
      { nombre: 'categoria', requerida: true, ayuda: 'Categoría ya cargada en ese rubro' },
      { nombre: 'producto', requerida: true, ayuda: 'Nombre del producto' },
      { nombre: 'unidad', requerida: true, ayuda: 'UN, KG o LT' },
      { nombre: 'requiere_lote', ayuda: 'sí o no' },
      { nombre: 'requiere_vencimiento', ayuda: 'sí o no' },
    ],
    esquema: z.object({
      rubro: requerido('el rubro'),
      categoria: requerido('la categoría'),
      producto: requerido('el producto'),
      unidad: opcion('La unidad', ['UN', 'KG', 'LT'] as const),
      requiere_lote: siNo('requiere_lote'),
      requiere_vencimiento: siNo('requiere_vencimiento'),
    }),
  },
  {
    tipo: 'presentaciones',
    etiqueta: '4. Presentaciones y códigos',
    descripcion: 'Una fila por formato o código de barras. El escaneo identifica la presentación y su factor.',
    columnas: [
      { nombre: 'producto', requerida: true, ayuda: 'Producto ya cargado' },
      { nombre: 'presentacion', requerida: true, ayuda: 'Por ejemplo: Caja x 12' },
      { nombre: 'factor', requerida: true, ayuda: 'Unidades de stock que trae: 12' },
      { nombre: 'codigo', ayuda: 'Código de barras' },
      { nombre: 'tipo_codigo', ayuda: `Si hay código: ${TIPOS_CODIGO.join(', ')}` },
    ],
    esquema: z
      .object({
        producto: requerido('el producto'),
        presentacion: requerido('la presentación'),
        factor: numero('El factor', 0.001),
        codigo: opcional,
        tipo_codigo: z.string().trim().optional().transform((v) => v?.toUpperCase() || null),
      })
      .refine((f) => !f.codigo || TIPOS_CODIGO.some((t) => t === f.tipo_codigo), {
        message: `Con código, tipo_codigo debe ser ${TIPOS_CODIGO.join(', ')}`,
      }),
  },
  {
    tipo: 'proveedores',
    etiqueta: '5. Proveedores',
    descripcion: 'Se identifican por CUIT. Una celda vacía borra el dato que estuviera cargado.',
    columnas: [
      { nombre: 'proveedor', requerida: true, ayuda: 'Razón social o nombre' },
      { nombre: 'cuit', requerida: true, ayuda: '11 dígitos' },
      { nombre: 'contacto', ayuda: 'Persona de contacto' },
      { nombre: 'telefono_whatsapp', ayuda: 'Con código de país' },
      { nombre: 'email', ayuda: 'Correo para enviar la orden' },
      { nombre: 'canal_envio', ayuda: 'MANUAL, WHATSAPP o EMAIL' },
      { nombre: 'plazo_entrega_dias', ayuda: 'Días hasta la entrega' },
      { nombre: 'dias_pedido', ayuda: '0 = domingo … 6 = sábado, separados por |: 1|4' },
      { nombre: 'monto_minimo', ayuda: 'Pedido mínimo en pesos' },
    ],
    esquema: z.object({
      proveedor: requerido('el proveedor'),
      cuit,
      contacto: opcional,
      telefono_whatsapp: opcional,
      email: opcional,
      canal_envio: z
        .string()
        .trim()
        .optional()
        .transform((v) => v?.toUpperCase() || 'MANUAL')
        .pipe(z.enum(['MANUAL', 'WHATSAPP', 'EMAIL'], { message: 'canal_envio debe ser MANUAL, WHATSAPP o EMAIL' })),
      plazo_entrega_dias: enteroOpcional('El plazo de entrega'),
      dias_pedido: z
        .string()
        .trim()
        .optional()
        .transform((v) => (v ? v.split(/[|,\s]+/).filter(Boolean).map(Number) : null))
        .refine(
          (d) => !d || d.every((n) => Number.isInteger(n) && n >= 0 && n <= 6),
          'dias_pedido debe tener números de 0 a 6',
        ),
      monto_minimo: numeroOpcional('El monto mínimo'),
    }),
  },
  {
    tipo: 'precios',
    etiqueta: '6. Productos por proveedor',
    descripcion:
      'Una fila por cada proveedor de un producto. Si hay más de uno, quien arma el pedido elige a quién comprarle.',
    columnas: [
      { nombre: 'producto', requerida: true, ayuda: 'Producto ya cargado' },
      { nombre: 'presentacion', requerida: true, ayuda: 'Presentación ya cargada' },
      { nombre: 'cuit', requerida: true, ayuda: 'CUIT del proveedor ya cargado' },
      { nombre: 'precio', ayuda: 'Por ejemplo: 1.240,50' },
      { nombre: 'codigo_proveedor', ayuda: 'Código que usa el proveedor' },
      { nombre: 'preferido', ayuda: 'sí o no: se muestra primero al elegir' },
    ],
    esquema: z.object({
      producto: requerido('el producto'),
      presentacion: requerido('la presentación'),
      cuit,
      precio: numeroOpcional('El precio'),
      codigo_proveedor: opcional,
      preferido: siNo('preferido'),
    }),
  },
];

/** Punto y coma y BOM: así Excel en español abre la plantilla en columnas y con acentos. */
export function descargarPlantilla(def: DefinicionImportacion) {
  const contenido = `﻿${def.columnas.map((c) => c.nombre).join(';')}\r\n`;
  const url = URL.createObjectURL(new Blob([contenido], { type: 'text/csv;charset=utf-8' }));
  const enlace = document.createElement('a');
  enlace.href = url;
  enlace.download = `eskemia-${def.tipo}.csv`;
  enlace.click();
  URL.revokeObjectURL(url);
}

/** Excel suele guardar en Windows-1252: si no es UTF-8 válido, se lee con esa codificación. */
export async function leerArchivo(archivo: File): Promise<string> {
  const bytes = await archivo.arrayBuffer();
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder('windows-1252').decode(bytes);
  }
}

export function analizarCsv(def: DefinicionImportacion, texto: string) {
  const crudo = Papa.parse<Record<string, string>>(texto, {
    header: true,
    skipEmptyLines: 'greedy',
    delimitersToGuess: [';', ',', '\t'],
    transformHeader: (h) => h.trim().toLowerCase(),
  });

  const presentes = crudo.meta.fields ?? [];
  const faltantes = def.columnas.filter((c) => c.requerida && !presentes.includes(c.nombre)).map((c) => c.nombre);
  if (faltantes.length > 0) {
    const errores: ErrorFila[] = [{ fila: 0, mensaje: `Al archivo le faltan las columnas: ${faltantes.join(', ')}` }];
    return { filas: [] as FilaImportacion[], errores };
  }

  const filas: FilaImportacion[] = [];
  const errores: ErrorFila[] = [];
  crudo.data.forEach((dato, i) => {
    const fila = i + 2; // La línea 1 es el encabezado.
    const r = def.esquema.safeParse(dato);
    if (r.success) filas.push({ ...r.data, fila });
    else for (const issue of r.error.issues) errores.push({ fila, mensaje: issue.message });
  });
  return { filas, errores };
}

/** Vista previa (aplicar=false) o aplicación, todo o nada, en la organización actual. */
export async function importarCatalogo(
  tipo: TipoImportacion,
  filas: FilaImportacion[],
  aplicar: boolean,
): Promise<ResultadoImportacion> {
  return importar(await organizacionActual(), tipo, filas, aplicar);
}
