import { useRef, useState, type ReactNode } from 'react';
import { comprimirFoto } from '../lib/imagen';

/** Abre directamente la cámara trasera de la tablet. */
export function BotonFoto({
  alCapturar,
  children,
  primario = false,
}: {
  alCapturar: (foto: Blob) => void;
  children: ReactNode;
  primario?: boolean;
}) {
  const entrada = useRef<HTMLInputElement>(null);
  const [error, setError] = useState<string | null>(null);

  return (
    <>
      <input
        ref={entrada}
        type="file"
        accept="image/*"
        capture="environment"
        hidden
        data-testid="entrada-foto"
        onChange={async (e) => {
          const archivo = e.target.files?.[0];
          e.target.value = '';
          if (!archivo) return;
          try {
            setError(null);
            alCapturar(await comprimirFoto(archivo));
          } catch {
            setError('No se pudo procesar la foto. Probá de nuevo.');
          }
        }}
      />
      <button
        type="button"
        className={`btn${primario ? ' btn-primario' : ''}`}
        onClick={() => entrada.current?.click()}
      >
        {children}
      </button>
      {error && <p className="aviso-error">{error}</p>}
    </>
  );
}
