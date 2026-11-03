import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { Eraser } from 'lucide-react';

export interface PadFirmaRef {
  obtenerImagen: () => Promise<Blob | null>;
}

const TINTA = '#15181d';
// Evita aceptar como firma un toque accidental.
const TRAZOS_MINIMOS = 12;

export const PadFirma = forwardRef<
  PadFirmaRef,
  { titulo: string; alCambiar: (firmado: boolean) => void }
>(function PadFirma({ titulo, alCambiar }, ref) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const puntos = useRef(0);
  const dibujando = useRef(false);
  const [firmado, setFirmado] = useState(false);

  useEffect(() => {
    const c = canvas.current!;
    const escala = window.devicePixelRatio || 1;
    c.width = c.clientWidth * escala;
    c.height = c.clientHeight * escala;
    const ctx = c.getContext('2d')!;
    ctx.scale(escala, escala);
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = TINTA;
  }, []);

  useImperativeHandle(ref, () => ({
    obtenerImagen: () =>
      new Promise((resolve) => {
        if (!firmado) {
          resolve(null);
          return;
        }
        canvas.current!.toBlob((b) => resolve(b), 'image/png');
      }),
  }));

  const posicion = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top] as const;
  };

  function limpiar() {
    const c = canvas.current!;
    c.getContext('2d')!.clearRect(0, 0, c.width, c.height);
    puntos.current = 0;
    setFirmado(false);
    alCambiar(false);
  }

  return (
    <div className="grupo">
      <div className="fila" style={{ justifyContent: 'space-between' }}>
        <h2>{titulo}</h2>
        <button type="button" className="btn" onClick={limpiar}>
          <Eraser size={20} /> Limpiar
        </button>
      </div>
      <canvas
        ref={canvas}
        className="firma"
        aria-label={titulo}
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId);
          dibujando.current = true;
          const ctx = e.currentTarget.getContext('2d')!;
          ctx.beginPath();
          ctx.moveTo(...posicion(e));
        }}
        onPointerMove={(e) => {
          if (!dibujando.current) return;
          const ctx = e.currentTarget.getContext('2d')!;
          ctx.lineTo(...posicion(e));
          ctx.stroke();
          puntos.current += 1;
          if (puntos.current >= TRAZOS_MINIMOS && !firmado) {
            setFirmado(true);
            alCambiar(true);
          }
        }}
        onPointerUp={() => {
          dibujando.current = false;
        }}
        onPointerCancel={() => {
          dibujando.current = false;
        }}
      />
    </div>
  );
});
