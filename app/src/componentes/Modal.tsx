import type { ReactNode } from 'react';
import { X } from 'lucide-react';

export function Modal({
  titulo,
  alCerrar,
  children,
}: {
  titulo: string;
  alCerrar?: () => void;
  children: ReactNode;
}) {
  return (
    <div className="fondo-modal">
      <div className="modal" role="dialog" aria-modal="true" aria-label={titulo}>
        <div className="modal-titulo">
          <h2>{titulo}</h2>
          {alCerrar && (
            <button className="btn btn-texto" onClick={alCerrar} aria-label="Cerrar">
              <X size={24} />
            </button>
          )}
        </div>
        {children}
      </div>
    </div>
  );
}
