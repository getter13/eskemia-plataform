import { AlertTriangle, CheckCircle2, XCircle } from 'lucide-react';
import type { Semaforo } from '../lib/admin';

const CONFIG = {
  OK: { clase: 'etiqueta', texto: 'OK', Icono: CheckCircle2 },
  CON_DIFERENCIAS: { clase: 'etiqueta etiqueta-alerta', texto: 'Con diferencias', Icono: AlertTriangle },
  CONTROL_INCOMPLETO: { clase: 'etiqueta etiqueta-error', texto: 'Control incompleto', Icono: XCircle },
} as const;

export function EtiquetaSemaforo({ semaforo }: { semaforo: Semaforo }) {
  const { clase, texto, Icono } = CONFIG[semaforo];
  return (
    <span className={clase} data-testid="semaforo">
      <Icono size={16} /> {texto}
    </span>
  );
}
