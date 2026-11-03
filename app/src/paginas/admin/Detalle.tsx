import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { AlertTriangle, ArrowLeft, Check, CheckCircle2, X, XCircle } from 'lucide-react';
import { Encabezado } from '../../componentes/Encabezado';
import { EtiquetaSemaforo } from '../../componentes/EtiquetaSemaforo';
import { Modal } from '../../componentes/Modal';
import {
  ETIQUETAS_CHECKLIST,
  rechazarRecepcion,
  traerDetalle,
  validarRecepcion,
  type AdjuntoDetalle,
  type Detalle as DatosDetalle,
  type EventoDetalle,
} from '../../lib/admin';
import type { TipoAdjunto } from '../../lib/db';
import {
  ETIQUETA_ESTADO,
  formatoCantidad,
  formatoCuit,
  formatoFecha,
  formatoFechaHora,
} from '../../lib/formato';

const ETIQUETA_ADJUNTO: Record<TipoAdjunto, string> = {
  REMITO: 'Remito o factura',
  MANUAL: 'Carga manual',
  RECHAZO: 'Rechazo',
  FIRMA_RECEPTOR: 'Firma del receptor',
  FIRMA_TRANSPORTISTA: 'Firma del transportista',
};

const ETIQUETA_DIFERENCIA = { FALTANTE: 'Faltante', SOBRANTE: 'Sobrante', RECHAZO: 'Rechazo' };

function describirEvento(e: EventoDetalle): { titulo: string; detalle: string | null } {
  const p = e.payload;
  const texto = (v: unknown) => (typeof v === 'string' && v.trim() !== '' ? v : null);
  if (e.accion === 'abierta') return { titulo: 'Recepción abierta', detalle: texto(p.nro_remito) };
  if (e.accion === 'control_item') {
    return { titulo: 'Control de ítem', detalle: texto(p.motivo) };
  }
  if (e.accion.startsWith('estado:')) {
    const estado = e.accion.slice(7) as keyof typeof ETIQUETA_ESTADO;
    return { titulo: `Estado: ${ETIQUETA_ESTADO[estado] ?? estado}`, detalle: texto(p.observacion) };
  }
  if (e.accion.startsWith('adjunto:')) {
    const tipo = e.accion.slice(8) as TipoAdjunto;
    return { titulo: `Adjunto: ${ETIQUETA_ADJUNTO[tipo] ?? tipo}`, detalle: null };
  }
  if (e.accion.startsWith('lectura:')) {
    const manual = e.accion.endsWith('MANUAL');
    return {
      titulo: manual ? 'Carga manual' : 'Lectura de escáner',
      detalle: [texto(p.valor_crudo), texto(p.motivo)].filter(Boolean).join(' · ') || null,
    };
  }
  return { titulo: e.accion, detalle: null };
}

function Celda({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <span className="grupo-compacto">
      <span className="label">{titulo}</span>
      <span>{children}</span>
    </span>
  );
}

function ModalDecision({
  tipo,
  alConfirmar,
  alCerrar,
}: {
  tipo: 'validar' | 'rechazar';
  alConfirmar: (observacion: string) => Promise<void>;
  alCerrar: () => void;
}) {
  const [observacion, setObservacion] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const rechazo = tipo === 'rechazar';

  return (
    <Modal titulo={rechazo ? 'Rechazar recepción' : 'Validar recepción'} alCerrar={alCerrar}>
      {rechazo && <p>La recepción vuelve a operación con esta observación para que la corrijan.</p>}
      <label className="grupo">
        <span className="label">Observación{rechazo ? ' (obligatoria)' : ' (opcional)'}</span>
        <textarea
          className="campo campo-texto"
          rows={3}
          autoFocus
          value={observacion}
          onChange={(e) => setObservacion(e.target.value)}
        />
      </label>
      {error && (
        <p className="aviso-error" role="alert">
          <AlertTriangle size={20} /> {error}
        </p>
      )}
      <button
        className="btn btn-primario"
        disabled={enviando || (rechazo && observacion.trim() === '')}
        onClick={async () => {
          setEnviando(true);
          setError(null);
          try {
            await alConfirmar(observacion.trim());
          } catch (e) {
            setError(e instanceof Error ? e.message : 'No se pudo completar la operación.');
            setEnviando(false);
          }
        }}
      >
        {rechazo ? 'Confirmar rechazo' : 'Confirmar validación'}
      </button>
    </Modal>
  );
}

function GaleriaAdjuntos({ adjuntos }: { adjuntos: AdjuntoDetalle[] }) {
  const [ampliado, setAmpliado] = useState<AdjuntoDetalle | null>(null);
  return (
    <>
      <div className="galeria">
        {adjuntos.map((a) => (
          <button
            className="tarjeta galeria-item"
            key={a.id}
            data-testid="adjunto"
            onClick={() => setAmpliado(a)}
            disabled={!a.url}
          >
            {a.url ? (
              <img src={a.url} alt={ETIQUETA_ADJUNTO[a.tipo]} loading="lazy" />
            ) : (
              <span className="muted">Sin vista previa</span>
            )}
            <strong>{ETIQUETA_ADJUNTO[a.tipo]}</strong>
            {a.anulado_en && (
              <span className="etiqueta etiqueta-neutra">Reemplazada</span>
            )}
          </button>
        ))}
      </div>
      {ampliado?.url && (
        <Modal titulo={ETIQUETA_ADJUNTO[ampliado.tipo]} alCerrar={() => setAmpliado(null)}>
          <img className="imagen-ampliada" src={ampliado.url} alt={ETIQUETA_ADJUNTO[ampliado.tipo]} />
        </Modal>
      )}
    </>
  );
}

export function Detalle() {
  const { id = '' } = useParams();
  const [parametros] = useSearchParams();
  const navegar = useNavigate();
  const [datos, setDatos] = useState<DatosDetalle | null | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [decision, setDecision] = useState<'validar' | 'rechazar' | null>(null);

  const cargar = useCallback(async () => {
    try {
      setDatos(await traerDetalle(id));
      setError(null);
    } catch {
      setError('No se pudo cargar la recepción. Revisá la conexión.');
    }
  }, [id]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const fecha = parametros.get('fecha');
  const volver = () => navegar(fecha ? `/admin?fecha=${fecha}` : '/admin');

  const r = datos?.recepcion;
  const cerrada = r?.estado === 'CERRADA_OK' || r?.estado === 'CERRADA_CON_DIFERENCIAS';
  const bloqueada = !r?.checklist.completo;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Detalle</h2>
      </Encabezado>
      <main className="contenido contenido-admin">
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        {datos === null && <p className="muted">Esta recepción no existe o no tenés acceso.</p>}

        {datos && r && (
          <>
            <section className="grupo">
              <h1>{r.proveedor}</h1>
              <div className="fila">
                <EtiquetaSemaforo semaforo={r.semaforo} />
                <span className="etiqueta etiqueta-neutra" data-testid="estado-recepcion">
                  {ETIQUETA_ESTADO[r.estado]}
                </span>
                {r.remito_duplicado && (
                  <span className="etiqueta etiqueta-alerta" data-testid="alerta-duplicado">
                    <AlertTriangle size={16} /> Remito repetido
                  </span>
                )}
              </div>
              <div className="fila-datos">
                <Celda titulo="Remito o factura">
                  <span className="mono">{r.nro_remito}</span>
                </Celda>
                {datos.cuit && (
                  <Celda titulo="CUIT">
                    <span className="mono">{formatoCuit(datos.cuit)}</span>
                  </Celda>
                )}
                <Celda titulo="Sede">{r.sede}</Celda>
                <Celda titulo="Operario">{datos.usuarios[r.usuario_id] ?? '—'}</Celda>
                <Celda titulo="Abierta">{formatoFechaHora(r.abierta_en)}</Celda>
                <Celda titulo="Cerrada">{r.cerrada_en ? formatoFechaHora(r.cerrada_en) : '—'}</Celda>
                {r.validada_en && (
                  <Celda titulo="Validada">
                    {formatoFechaHora(r.validada_en)}
                    {r.validada_por ? ` · ${datos.usuarios[r.validada_por] ?? ''}` : ''}
                  </Celda>
                )}
              </div>
              {r.observacion && (
                <p className="tarjeta" data-testid="observacion">
                  <span className="label">Observación</span>
                  {r.observacion}
                </p>
              )}
            </section>

            <section className="grupo">
              <h2>Checklist de validación</h2>
              <ul className="checklist" data-testid="checklist">
                {ETIQUETAS_CHECKLIST.map(([clave, etiqueta]) => (
                  <li key={clave} className={r.checklist[clave] ? '' : 'falta'}>
                    {r.checklist[clave] ? <CheckCircle2 size={24} /> : <XCircle size={24} />}
                    {etiqueta}
                    {!r.checklist[clave] && ' · Falta'}
                  </li>
                ))}
              </ul>
            </section>

            <section className="grupo">
              <h2>Ítems ({datos.items.length})</h2>
              {datos.items.map((i) => (
                <div className="tarjeta" key={i.id} data-testid="item-detalle">
                  <div className="fila">
                    <strong>{i.productos.nombre}</strong>
                    {i.productos.pendiente_validacion && (
                      <span className="etiqueta etiqueta-alerta">Producto pendiente de validar</span>
                    )}
                    {i.diferencia !== null && Number(i.diferencia) !== 0 && (
                      <span className="etiqueta etiqueta-alerta">
                        <AlertTriangle size={16} />
                        {i.tipo_diferencia ? ETIQUETA_DIFERENCIA[i.tipo_diferencia] : 'Diferencia'}
                      </span>
                    )}
                  </div>
                  <div className="fila-datos">
                    {i.productos.gtin && (
                      <Celda titulo="GTIN">
                        <span className="mono">{i.productos.gtin}</span>
                      </Celda>
                    )}
                    <Celda titulo="Remito">
                      {i.cant_remito === null
                        ? '—'
                        : formatoCantidad(Number(i.cant_remito), i.productos.tipo_medida)}
                    </Celda>
                    <Celda titulo="Recibido">
                      {formatoCantidad(Number(i.cant_recibida), i.productos.tipo_medida)}
                    </Celda>
                    <Celda titulo="Diferencia">
                      {i.diferencia === null
                        ? '—'
                        : formatoCantidad(Number(i.diferencia), i.productos.tipo_medida)}
                    </Celda>
                    {i.lote && <Celda titulo="Lote">{i.lote}</Celda>}
                    {i.vencimiento && <Celda titulo="Vencimiento">{formatoFecha(i.vencimiento)}</Celda>}
                    {i.motivo_diferencia && <Celda titulo="Motivo">{i.motivo_diferencia}</Celda>}
                  </div>
                </div>
              ))}
            </section>

            <section className="grupo">
              <h2>Fotos y firmas ({datos.adjuntos.length})</h2>
              <GaleriaAdjuntos adjuntos={datos.adjuntos} />
            </section>

            <section className="grupo">
              <h2>Lecturas crudas ({datos.lecturas.length})</h2>
              <div className="lista-densa" data-testid="lecturas">
                {datos.lecturas.map((l) => (
                  <div className="fila-densa" key={l.id}>
                    <span className="muted">{formatoFechaHora(l.leido_en)}</span>
                    <span>{l.tipo === 'MANUAL' ? 'Manual' : 'Escaneo'}</span>
                    <strong>{l.productos.nombre}</strong>
                    <span className="mono">
                      {Number(l.cantidad) > 0 ? '+' : ''}
                      {formatoCantidad(Number(l.cantidad), l.productos.tipo_medida)}
                    </span>
                    <span className="mono muted texto-corte">{l.valor_crudo ?? l.motivo ?? ''}</span>
                  </div>
                ))}
              </div>
            </section>

            <section className="grupo">
              <h2>Línea de tiempo ({datos.eventos.length})</h2>
              <ol className="linea-tiempo" data-testid="linea-tiempo">
                {datos.eventos.map((e) => {
                  const { titulo, detalle } = describirEvento(e);
                  return (
                    <li key={e.id}>
                      <strong>{titulo}</strong>
                      <span className="muted">
                        {formatoFechaHora(e.creado_en)}
                        {e.usuario_id ? ` · ${datos.usuarios[e.usuario_id] ?? ''}` : ''}
                      </span>
                      {detalle && <span className="texto-corte">{detalle}</span>}
                      <span className="mono muted">#{e.secuencia} · {e.hash.slice(0, 12)}</span>
                    </li>
                  );
                })}
              </ol>
            </section>
          </>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={volver}>
          <ArrowLeft size={24} /> Volver a la bandeja
        </button>
        <span className="espacio" />
        {cerrada && (
          <>
            <button className="btn" onClick={() => setDecision('rechazar')}>
              <X size={24} /> Rechazar
            </button>
            <button
              className="btn btn-primario"
              disabled={bloqueada}
              onClick={() => setDecision('validar')}
            >
              <Check size={24} /> Validar
            </button>
          </>
        )}
      </footer>
      {decision && r && (
        <ModalDecision
          tipo={decision}
          alCerrar={() => setDecision(null)}
          alConfirmar={async (observacion) => {
            if (decision === 'validar') await validarRecepcion(r.id, observacion);
            else await rechazarRecepcion(r.id, observacion);
            setDecision(null);
            await cargar();
          }}
        />
      )}
    </div>
  );
}
