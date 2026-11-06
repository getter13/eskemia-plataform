// Eskemia · Genera tokens.css desde tokens.json (sistema de diseño v2).
//
// Qué hace: lee paquetes/tokens/tokens.json (fuente de verdad, aprobada por el CEO) y
// escribe tokens.css con variables CSS nombradas por USO: colores, familias, escala
// tipográfica, espaciado, radios y sombras. Suma los objetivos táctiles de la tabla
// "Estética v2" del CLAUDE.md, que no viven en tokens.json.
// Dónde encaja: Etapa 3b. tokens.css se commitea y NO se edita a mano; el CI regenera y
// falla si difiere. Uso: pnpm --filter @eskemia/tokens generar

import { readFileSync, writeFileSync } from 'node:fs';

interface Token {
  name: string;
  value: string;
  usage?: string;
}
interface EstiloTexto {
  name: string;
  fontSize: string;
  lineHeight: string;
  fontWeight: number;
  letterSpacing?: string;
}
interface Fuente {
  color: { tokens: Token[] };
  type: { families: Record<string, string>; groups: Array<{ styles: EstiloTexto[] }> };
  spacing: { tokens: Token[] };
  radius: { tokens: Token[] };
  shadow: { tokens: Token[] };
}

/** Objetivos táctiles mínimos (CLAUDE.md, Estética v2, fila "Táctil"). */
const TACTILES: Token[] = [
  { name: 'tactil-escritorio', value: '44px' },
  { name: 'tactil-movil', value: '48px' },
  { name: 'tactil-kiosco', value: '56px' },
];

const raiz = new URL('../', import.meta.url);
const fuente = JSON.parse(readFileSync(new URL('tokens.json', raiz), 'utf8')) as Fuente;

/** Una línea de variable, con el uso como comentario cuando lo hay. */
const variable = (t: Token) => `  --${t.name}: ${t.value};${t.usage ? ` /* ${t.usage.replaceAll('*/', '')} */` : ''}`;

const lineas: string[] = [
  '/* Eskemia · Tokens del sistema de diseño v2.',
  ' * GENERADO por paquetes/tokens/scripts/generar.ts desde tokens.json. No editar a mano. */',
  '',
  ':root {',
  '  /* Color */',
  ...fuente.color.tokens.map(variable),
  '',
  '  /* Familias: --font-data lleva cifras tabulares (ver .datos en la app). */',
  ...Object.entries(fuente.type.families).map(([uso, familia]) => `  --font-${uso}: ${familia};`),
  '',
  '  /* Escala tipográfica */',
  ...fuente.type.groups.flatMap((g) =>
    g.styles.flatMap((e) => [
      `  --text-${e.name}-size: ${e.fontSize};`,
      `  --text-${e.name}-line: ${e.lineHeight};`,
      `  --text-${e.name}-weight: ${e.fontWeight};`,
      `  --text-${e.name}-tracking: ${e.letterSpacing ?? 'normal'};`,
    ]),
  ),
  '',
  '  /* Espaciado */',
  ...fuente.spacing.tokens.map(variable),
  '',
  '  /* Radios */',
  ...fuente.radius.tokens.map(variable),
  '',
  '  /* Sombras */',
  ...fuente.shadow.tokens.map(variable),
  '',
  '  /* Objetivos táctiles */',
  ...TACTILES.map(variable),
  '}',
  '',
];

writeFileSync(new URL('tokens.css', raiz), lineas.join('\n'));
console.log(`tokens.css generado (${lineas.length} líneas).`);
