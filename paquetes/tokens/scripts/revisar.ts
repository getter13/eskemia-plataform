// Eskemia · Lint de tokens (estética v2).
//
// Qué hace: recorre los .css y .tsx de las carpetas indicadas y falla si encuentra
// valores escritos a mano donde la estética v2 exige un token: colores (hex, rgb, hsl),
// familias tipográficas, tamaños de letra, radios, sombras y espaciados en px.
// Dónde encaja: CLAUDE.md, "Tokens, no valores". Corre en el CI (job web) y con
// `pnpm --filter @eskemia/tokens revisar`. Excepciones explícitas abajo, con su motivo.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

/** Archivos que no son UI de la app y por eso no usan tokens. */
const EXCEPCIONES: Record<string, string> = {
  'lib/ordenPdf.tsx': 'PDF generado con @react-pdf: usa las fuentes y medidas del PDF, no CSS',
};

/** Reglas: qué se busca y qué se sugiere usar. */
const REGLAS: Array<{ nombre: string; patron: RegExp; sugerencia: string }> = [
  { nombre: 'color', patron: /#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\(/, sugerencia: 'var(--surface-100), var(--ink)…' },
  { nombre: 'familia', patron: /font-family\s*:\s*(?!\s*var\(--font-|\s*inherit)/, sugerencia: 'var(--font-ui) o var(--font-data)' },
  { nombre: 'familia', patron: /fontFamily\s*:/, sugerencia: 'una clase con var(--font-ui) o var(--font-data)' },
  { nombre: 'tamaño de letra', patron: /font-size\s*:\s*[^;]*\d+(?:px|rem|em)/, sugerencia: 'var(--text-body-size)…' },
  {
    nombre: 'tipografía abreviada',
    patron: /(?:^|[\s;{])font\s*:\s*(?!\s*inherit)[^;]*(?:\d+(?:px|rem|em)|(?<!var\()--font-(?!ui|data))/,
    sugerencia: 'font: var(--text-body-weight) var(--text-body-size)/var(--text-body-line) var(--font-ui)',
  },
  { nombre: 'familia', patron: /var\(--font-(?!ui\)|data\))/, sugerencia: 'var(--font-ui) o var(--font-data)' },
  { nombre: 'monoespaciada', patron: /monospace|ui-monospace/, sugerencia: 'var(--font-data) con cifras tabulares (sin monoespaciada)' },
  { nombre: 'radio', patron: /border-radius\s*:\s*[^;]*\d+px/, sugerencia: 'var(--radius-card)…' },
  { nombre: 'sombra', patron: /box-shadow\s*:\s*(?!\s*(?:var\(--shadow-|none|inherit))/, sugerencia: 'var(--shadow-card)…' },
  {
    nombre: 'espaciado',
    patron: /\b(?:padding|margin|gap|row-gap|column-gap)(?:-[a-z]+)?\s*:\s*[^;]*\b(?:[3-9]|\d{2,})px/,
    sugerencia: 'var(--space-2)…',
  },
];

function archivos(dir: string): string[] {
  return readdirSync(dir).flatMap((nombre) => {
    const ruta = join(dir, nombre);
    if (statSync(ruta).isDirectory()) return archivos(ruta);
    return /\.(css|tsx)$/.test(nombre) ? [ruta] : [];
  });
}

const carpetas = process.argv.slice(2);
if (carpetas.length === 0) {
  console.error('Uso: node scripts/revisar.ts <carpeta> [carpeta…]');
  process.exit(2);
}

const hallazgos: string[] = [];
for (const carpeta of carpetas) {
  for (const archivo of archivos(carpeta)) {
    const corto = relative(carpeta, archivo).replaceAll('\\', '/');
    if (corto in EXCEPCIONES) continue;
    readFileSync(archivo, 'utf8')
      .split('\n')
      .forEach((linea, i) => {
        if (/^\s*(\/\/|\*|\/\*)/.test(linea)) return;
        for (const regla of REGLAS) {
          if (regla.patron.test(linea)) {
            hallazgos.push(`${corto}:${i + 1}  ${regla.nombre} escrito a mano → usá ${regla.sugerencia}\n    ${linea.trim()}`);
          }
        }
      });
  }
}

if (hallazgos.length > 0) {
  console.error(hallazgos.join('\n'));
  console.error(`\n${hallazgos.length} valor(es) fuera de tokens.`);
  process.exit(1);
}
console.log('Tokens: sin valores escritos a mano.');
