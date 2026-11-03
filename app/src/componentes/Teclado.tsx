import { useState } from 'react';
import { Check, Delete } from 'lucide-react';
import type { TipoMedida } from '../lib/db';
import { unidadCorta } from '../lib/formato';
import { Modal } from './Modal';

/** Teclado propio, para no abrir el de Android ni perder la lectura del escáner. */
export function TecladoCantidad({
  titulo,
  medida,
  inicial,
  permitirCero = false,
  alConfirmar,
  alCerrar,
}: {
  titulo: string;
  medida: TipoMedida;
  inicial?: number | null;
  permitirCero?: boolean;
  alConfirmar: (valor: number) => void;
  alCerrar: () => void;
}) {
  const [texto, setTexto] = useState(
    inicial === null || inicial === undefined ? '' : String(inicial).replace('.', ','),
  );
  const conDecimales = medida === 'PESO';

  function tocar(tecla: string) {
    setTexto((t) => {
      if (tecla === ',') {
        if (!conDecimales || t.includes(',')) return t;
        return t === '' ? '0,' : `${t},`;
      }
      const [, decimales] = t.split(',');
      if (decimales !== undefined && decimales.length >= 3) return t;
      if (t === '0') return tecla;
      return t.length >= 9 ? t : t + tecla;
    });
  }

  const valor = texto === '' ? null : Number(texto.replace(',', '.'));
  const valido = valor !== null && !Number.isNaN(valor) && (permitirCero ? valor >= 0 : valor > 0);

  return (
    <Modal titulo={titulo} alCerrar={alCerrar}>
      <div className="visor" data-testid="visor">
        {texto || '0'} <small>{unidadCorta(medida)}</small>
      </div>
      <div className="teclado">
        {['7', '8', '9', '4', '5', '6', '1', '2', '3'].map((n) => (
          <button className="btn" key={n} onClick={() => tocar(n)}>
            {n}
          </button>
        ))}
        <button className="btn" onClick={() => tocar(',')} disabled={!conDecimales}>
          ,
        </button>
        <button className="btn" onClick={() => tocar('0')}>
          0
        </button>
        <button className="btn" onClick={() => setTexto((t) => t.slice(0, -1))} aria-label="Borrar">
          <Delete size={24} />
        </button>
      </div>
      <button className="btn btn-primario" disabled={!valido} onClick={() => alConfirmar(valor!)}>
        <Check size={24} /> Confirmar
      </button>
    </Modal>
  );
}
