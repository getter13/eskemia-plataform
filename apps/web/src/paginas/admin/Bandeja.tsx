import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  AlertTriangle,
  ChevronLeft,
  ChevronRight,
  Download,
  RefreshCw,
  ScanLine,
  Users,
} from 'lucide-react';
import { Encabezado } from '../../componentes/Encabezado';
import { EtiquetaSemaforo } from '../../componentes/EtiquetaSemaforo';
import { descargarCsv, fechaHoy, moverFecha, traerBandeja, type FilaBandeja } from '../../lib/admin';
import { tienePermiso } from '../../lib/db';
import { ETIQUETA_ESTADO, formatoFecha, formatoFechaHora } from '../../lib/formato';
import { useSesion } from '../../lib/sesion';

const INTERVALO_MS = 30_000;

export function Bandeja() {
  const navegar = useNavigate();
  const { perfil } = useSesion();
  const [parametros, setParametros] = useSearchParams();
  const fecha = parametros.get('fecha') ?? fechaHoy();
  const [filas, setFilas] = useState<FilaBandeja[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exportando, setExportando] = useState(false);

  const cargar = useCallback(async () => {
    try {
      setFilas(await traerBandeja(fecha));
      setError(null);
    } catch {
      setError('No se pudo cargar la bandeja. Revisá la conexión.');
    }
  }, [fecha]);

  useEffect(() => {
    setFilas(null);
    void cargar();
    const timer = setInterval(() => void cargar(), INTERVALO_MS);
    return () => clearInterval(timer);
  }, [cargar]);

  const irA = (nueva: string) => setParametros({ fecha: nueva });
  const contar = (s: FilaBandeja['semaforo']) => filas?.filter((f) => f.semaforo === s).length ?? 0;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Bandeja</h2>
      </Encabezado>
      <main className="contenido contenido-admin">
        <div className="fila fila-fecha">
          <button className="btn" aria-label="Día anterior" onClick={() => irA(moverFecha(fecha, -1))}>
            <ChevronLeft size={24} />
          </button>
          <input
            className="campo campo-fecha"
            type="date"
            aria-label="Fecha"
            value={fecha}
            onChange={(e) => e.target.value && irA(e.target.value)}
          />
          <button className="btn" aria-label="Día siguiente" onClick={() => irA(moverFecha(fecha, 1))}>
            <ChevronRight size={24} />
          </button>
          <button className="btn" aria-label="Actualizar" onClick={() => void cargar()}>
            <RefreshCw size={24} />
          </button>
        </div>

        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}

        {filas && (
          <>
            <div className="metricas" data-testid="metricas">
              <div className="tarjeta metrica">
                <span className="label">Recepciones</span>
                <span className="metrica-valor">{filas.length}</span>
              </div>
              <div className="tarjeta metrica">
                <EtiquetaSemaforo semaforo="OK" />
                <span className="metrica-valor">{contar('OK')}</span>
              </div>
              <div className="tarjeta metrica">
                <EtiquetaSemaforo semaforo="CON_DIFERENCIAS" />
                <span className="metrica-valor">{contar('CON_DIFERENCIAS')}</span>
              </div>
              <div className="tarjeta metrica">
                <EtiquetaSemaforo semaforo="CONTROL_INCOMPLETO" />
                <span className="metrica-valor">{contar('CONTROL_INCOMPLETO')}</span>
              </div>
            </div>

            {filas.length === 0 && (
              <p className="muted">No hay recepciones el {formatoFecha(fecha)}.</p>
            )}

            <div className="grupo">
              {filas.map((f) => (
                <button
                  className="tarjeta tarjeta-tactil fila-bandeja"
                  data-testid="fila-bandeja"
                  key={f.id}
                  onClick={() => navegar(`/admin/recepcion/${f.id}?fecha=${fecha}`)}
                >
                  <span className="grupo fila-bandeja-datos">
                    <span className="grilla-nombre">{f.proveedor}</span>
                    <span className="muted">
                      <span className="datos">{f.oc_numero ?? 'Sin OC'}</span> · Remito o factura{' '}
                      <span className="datos">{f.nro_remito}</span> · {f.sede} ·{' '}
                      {formatoFechaHora(f.abierta_en)}
                    </span>
                    {f.remito_duplicado && (
                      <span className="etiqueta etiqueta-alerta" data-testid="alerta-duplicado">
                        <AlertTriangle size={16} /> Remito repetido
                      </span>
                    )}
                  </span>
                  <span className="fila-bandeja-estado">
                    <EtiquetaSemaforo semaforo={f.semaforo} />
                    <span className="etiqueta etiqueta-neutra">{ETIQUETA_ESTADO[f.estado]}</span>
                    <span className="datos muted">
                      {f.items} ítems · {f.items_con_diferencia} con diferencia
                    </span>
                  </span>
                  <ChevronRight size={24} />
                </button>
              ))}
            </div>
          </>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/')}>
          <ScanLine size={24} /> Ir al kiosco
        </button>
        {tienePermiso(perfil, 'nucleo.usuarios.gestionar') && (
          <button className="btn" onClick={() => navegar('/admin/roles')}>
            <Users size={24} /> Usuarios y roles
          </button>
        )}
        <span className="espacio" />
        <button
          className="btn btn-primario"
          disabled={exportando || !filas || filas.length === 0}
          onClick={async () => {
            setExportando(true);
            try {
              await descargarCsv(fecha);
            } catch {
              setError('No se pudo generar el CSV. Revisá la conexión.');
            }
            setExportando(false);
          }}
        >
          <Download size={24} /> Exportar CSV del día
        </button>
      </footer>
    </div>
  );
}
