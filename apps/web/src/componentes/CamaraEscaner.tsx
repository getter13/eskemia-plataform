import { useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader, type IScannerControls } from '@zxing/browser';
import { Modal } from './Modal';

/** Respaldo por si el lector 2D no está disponible. */
export function CamaraEscaner({
  alLeer,
  alCerrar,
}: {
  alLeer: (codigo: string) => void;
  alCerrar: () => void;
}) {
  const video = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let controles: IScannerControls | null = null;
    let activo = true;
    const lector = new BrowserMultiFormatReader();
    lector
      .decodeFromConstraints(
        { video: { facingMode: 'environment' } },
        video.current!,
        (resultado) => {
          if (resultado && activo) {
            activo = false;
            controles?.stop();
            alLeer(resultado.getText());
          }
        },
      )
      .then((c) => {
        controles = c;
        if (!activo) c.stop();
      })
      .catch(() => setError('No se pudo abrir la cámara. Revisá los permisos del navegador.'));
    return () => {
      activo = false;
      controles?.stop();
    };
  }, [alLeer]);

  return (
    <Modal titulo="Escanear con cámara" alCerrar={alCerrar}>
      <video ref={video} className="video-camara" muted playsInline />
      {error ? <p className="aviso-error">{error}</p> : <p className="muted">Apuntá al código de barras.</p>}
    </Modal>
  );
}
