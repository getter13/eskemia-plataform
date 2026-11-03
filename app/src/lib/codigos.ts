export interface CodigoLeido {
  gtin: string;
  gtin14: string;
  lote: string | null;
  vencimiento: string | null;
}

export function gtinValido(gtin: string): boolean {
  if (!/^(\d{8}|\d{12,14})$/.test(gtin)) return false;
  const digitos = [...gtin].map(Number);
  const verificador = digitos.pop()!;
  const suma = digitos.reverse().reduce((s, d, i) => s + d * (i % 2 === 0 ? 3 : 1), 0);
  return (10 - (suma % 10)) % 10 === verificador;
}

export function aGtin14(gtin: string): string {
  return gtin.padStart(14, '0');
}

function fechaGs1(aammdd: string): string {
  const anio = `20${aammdd.slice(0, 2)}`;
  const mes = aammdd.slice(2, 4);
  let dia = aammdd.slice(4, 6);
  // En GS1, día 00 significa fin de mes.
  if (dia === '00') {
    dia = String(new Date(Number(anio), Number(mes), 0).getDate()).padStart(2, '0');
  }
  return `${anio}-${mes}-${dia}`;
}

const GS = '\x1d';
const LARGO_FIJO: Record<string, number> = { '01': 14, '11': 6, '13': 6, '15': 6, '17': 6 };
const VARIABLES = new Set(['10', '21']);

/** Interpreta EAN/UPC y códigos GS1 2D. Devuelve null si no se reconoce un GTIN válido. */
export function interpretarCodigo(crudo: string): CodigoLeido | null {
  let s = crudo.trim().replace(/^\][A-Za-z]\d/, '');

  if (/^\d+$/.test(s) && (s.length === 8 || (s.length >= 12 && s.length <= 14))) {
    return gtinValido(s) ? { gtin: s, gtin14: aGtin14(s), lote: null, vencimiento: null } : null;
  }

  // GS1 legible: (01)...(17)...(10)...
  s = s.replace(/\((\d{2})\)/g, `${GS}$1`).replace(new RegExp(`^${GS}+`), '');

  let gtin14: string | null = null;
  let lote: string | null = null;
  let vencimiento: string | null = null;
  let i = 0;
  while (i < s.length) {
    if (s[i] === GS) {
      i++;
      continue;
    }
    const ai = s.slice(i, i + 2);
    i += 2;
    if (LARGO_FIJO[ai]) {
      const valor = s.slice(i, i + LARGO_FIJO[ai]);
      i += LARGO_FIJO[ai];
      if (ai === '01') gtin14 = valor;
      if (ai === '17' && /^\d{6}$/.test(valor)) vencimiento = fechaGs1(valor);
    } else if (VARIABLES.has(ai)) {
      const fin = s.indexOf(GS, i);
      const valor = fin === -1 ? s.slice(i) : s.slice(i, fin);
      i = fin === -1 ? s.length : fin;
      if (ai === '10') lote = valor;
    } else {
      break;
    }
  }

  if (!gtin14 || !gtinValido(gtin14)) return null;
  return { gtin: gtin14.startsWith('0') ? gtin14.slice(1) : gtin14, gtin14, lote, vencimiento };
}
