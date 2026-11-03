import { useEffect, useState, type ReactNode } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { AlertTriangle, CheckCircle2, CloudOff, RefreshCw } from 'lucide-react';
import { db } from '../lib/db';
import { pedirSincronizacion, reintentarErrores } from '../lib/sync';
import { Modal } from './Modal';

const ETIQUETAS_OP: Record<string, string> = {
  registrar_dispositivo: 'Registro de la tablet',
  alta_proveedor: 'Alta de proveedor',
  alta_producto: 'Alta de producto',
  abrir_recepcion: 'Apertura de recepción',
  subir_adjunto: 'Foto o firma',
  registrar_lectura: 'Lectura',
  fijar_control_item: 'Control de ítem',
  iniciar_control: 'Inicio de control',
  cerrar_recepcion: 'Cierre de recepción',
  reabrir_recepcion: 'Reapertura de recepción',
};

function IndicadorSync() {
  const [enLinea, setEnLinea] = useState(navigator.onLine);
  const [abierto, setAbierto] = useState(false);
  const ops = useLiveQuery(() => db.cola.toArray(), []) ?? [];
  const errores = ops.filter((o) => o.estado === 'error');
  const pendientes = ops.length - errores.length;

  useEffect(() => {
    const cambiar = () => setEnLinea(navigator.onLine);
    window.addEventListener('online', cambiar);
    window.addEventListener('offline', cambiar);
    return () => {
      window.removeEventListener('online', cambiar);
      window.removeEventListener('offline', cambiar);
    };
  }, []);

  let contenido: ReactNode;
  if (errores.length > 0) {
    contenido = (
      <>
        <AlertTriangle size={20} /> {errores.length} con error
      </>
    );
  } else if (!enLinea) {
    contenido = (
      <>
        <CloudOff size={20} /> Sin conexión{pendientes > 0 ? ` · ${pendientes} pendientes` : ''}
      </>
    );
  } else if (pendientes > 0) {
    contenido = (
      <>
        <RefreshCw size={20} /> Sincronizando · {pendientes}
      </>
    );
  } else {
    contenido = (
      <>
        <CheckCircle2 size={20} /> Sincronizado
      </>
    );
  }

  return (
    <>
      <button
        className={`sync${errores.length > 0 ? ' error' : ''}`}
        data-testid="sync"
        onClick={() => {
          pedirSincronizacion();
          if (errores.length > 0) setAbierto(true);
        }}
      >
        {contenido}
      </button>
      {abierto && (
        <Modal titulo="Operaciones con error" alCerrar={() => setAbierto(false)}>
          <p>El servidor rechazó estas operaciones. Las demás de esa recepción quedan en espera.</p>
          {errores.map((o) => (
            <div className="tarjeta" key={o.seq}>
              <strong>{ETIQUETAS_OP[o.tipo] ?? o.tipo}</strong>
              <p className="muted">{o.error}</p>
            </div>
          ))}
          <button
            className="btn btn-primario"
            onClick={() => {
              void reintentarErrores();
              setAbierto(false);
            }}
          >
            <RefreshCw size={20} /> Reintentar
          </button>
        </Modal>
      )}
    </>
  );
}

export function Encabezado({ children }: { children?: ReactNode }) {
  return (
    <header className="encabezado">
      <span className="marca">Eskemia</span>
      {children}
      <span className="espacio" />
      <IndicadorSync />
    </header>
  );
}
