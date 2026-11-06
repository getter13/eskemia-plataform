import { useCallback, useEffect, useRef, useState } from 'react';
import { AlertTriangle, Check, ShieldAlert, Undo2, X } from 'lucide-react';
import { Drawer } from 'vaul';
import { NavCompras } from '../../componentes/compras';
import { formatoMoneda } from '../../lib/catalogo';
import { formatoFechaHora, formatoNumero } from '../../lib/formato';
import { alCambiarOrdenes } from '@eskemia/cliente-api';
import { aprobarOc, motivoAprobacion, rechazarOc, traerBandeja, type OrdenBandeja } from '../../lib/aprobaciones';
import { useSesion } from '../../lib/sesion';

const SEGUNDOS_DESHACER = 5;

interface Aprobacion {
  orden: OrdenBandeja;
  timer: ReturnType<typeof setTimeout>;
}

export function Aprobaciones() {
  const organizacionId = useSesion().perfil?.organizacion_id;
  const [ordenes, setOrdenes] = useState<OrdenBandeja[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [enCurso, setEnCurso] = useState<Aprobacion | null>(null);
  const [aRechazar, setARechazar] = useState<OrdenBandeja | null>(null);
  const [motivo, setMotivo] = useState('');
  const [rechazando, setRechazando] = useState(false);
  const pendiente = useRef<Aprobacion | null>(null);

  const cargar = useCallback(async () => {
    try {
      const lista = await traerBandeja();
      // La que se está por aprobar no reaparece mientras corre el "Deshacer".
      setOrdenes(lista.filter((o) => o.id !== pendiente.current?.orden.id));
      setError(null);
    } catch {
      setError('No se pudo cargar la bandeja. Revisá la conexión.');
    }
  }, []);

  const confirmarPendiente = useCallback(async () => {
    const actual = pendiente.current;
    if (!actual) return;
    clearTimeout(actual.timer);
    pendiente.current = null;
    setEnCurso(null);
    try {
      await aprobarOc(actual.orden.id);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo aprobar la orden.');
    }
    await cargar();
  }, [cargar]);

  useEffect(() => {
    void cargar();
    const dejarDeEscuchar = organizacionId ? alCambiarOrdenes(organizacionId, () => void cargar()) : null;
    return () => {
      dejarDeEscuchar?.();
      // Salir de la pantalla no cancela una aprobación ya pedida.
      void confirmarPendiente();
    };
  }, [cargar, confirmarPendiente, organizacionId]);

  async function aprobar(orden: OrdenBandeja) {
    await confirmarPendiente();
    const aprobacion: Aprobacion = {
      orden,
      timer: setTimeout(() => void confirmarPendiente(), SEGUNDOS_DESHACER * 1000),
    };
    pendiente.current = aprobacion;
    setEnCurso(aprobacion);
    setOrdenes((lista) => lista?.filter((o) => o.id !== orden.id) ?? null);
  }

  function deshacer() {
    const actual = pendiente.current;
    if (!actual) return;
    clearTimeout(actual.timer);
    pendiente.current = null;
    setEnCurso(null);
    setOrdenes((lista) => [...(lista ?? []), actual.orden].sort((a, b) => a.creado_en.localeCompare(b.creado_en)));
  }

  async function rechazar() {
    if (!aRechazar) return;
    setRechazando(true);
    try {
      await rechazarOc(aRechazar.id, motivo);
      setARechazar(null);
      setMotivo('');
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo rechazar la orden.');
      setARechazar(null);
    }
    setRechazando(false);
  }

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <h1 className="mk-titulo">Aprobaciones</h1>
      </header>
      <main className="mk-lista grupo-pedido">
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        {ordenes !== null && ordenes.length === 0 && !enCurso && (
          <div className="mk-vacio">
            <p>No hay órdenes para aprobar.</p>
          </div>
        )}
        {ordenes?.map((o) => (
          <section className="tarjeta grupo mk-orden" data-testid="orden-aprobar" key={o.id}>
            <h2 className="mk-nombre">{o.proveedor}</h2>
            <span className="mono muted">{o.numero}</span>
            <span className="muted">
              {o.emisor} · {o.sede} · {formatoFechaHora(o.creado_en)}
            </span>
            <span className="mk-aviso" data-testid="motivo-aprobacion">
              <ShieldAlert size={16} /> {motivoAprobacion(o)}
            </span>
            {o.items.map((i) => (
              <div className={`mk-linea${i.disparo_aprobacion ? ' mk-linea-disparo' : ''}`} key={i.id}>
                <span className="grupo mk-flex">
                  <span>{i.producto}</span>
                  <span className="muted">
                    {formatoNumero(i.cantidad)} x {i.presentacion}
                  </span>
                  {i.disparo_aprobacion && <span className="etiqueta mk-etiqueta">Dispara la aprobación</span>}
                </span>
                <span className="mono">{formatoMoneda(i.subtotal)}</span>
              </div>
            ))}
            <div className="fila mk-subtotal">
              <span className="mk-flex">Total estimado</span>
              <strong className="mono">{formatoMoneda(o.total_estimado)}</strong>
            </div>
            <div className="mk-decision">
              <button className="btn mk-boton" onClick={() => setARechazar(o)}>
                <X size={20} /> Rechazar OC
              </button>
              <button className="btn btn-primario mk-boton" onClick={() => void aprobar(o)}>
                <Check size={20} /> Aprobar OC
              </button>
            </div>
          </section>
        ))}
      </main>

      {enCurso && (
        <div className="mk-toast" role="status" data-testid="aviso-deshacer">
          <span className="mk-flex">Aprobando {enCurso.orden.numero}</span>
          <button className="btn mk-boton" onClick={deshacer}>
            <Undo2 size={20} /> Deshacer
          </button>
        </div>
      )}
      <NavCompras />

      <Drawer.Root
        open={aRechazar !== null}
        onOpenChange={(abierto) => {
          if (!abierto) setARechazar(null);
        }}
      >
        <Drawer.Portal>
          <Drawer.Overlay className="mk-hoja-fondo" />
          <Drawer.Content className="mk-hoja" aria-describedby={undefined}>
            <div className="mk-hoja-agarre" />
            <Drawer.Title className="mk-hoja-titulo">Rechazar {aRechazar?.numero}</Drawer.Title>
            <label className="grupo">
              <span className="label">Motivo</span>
              <textarea
                className="campo campo-texto"
                rows={3}
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
              />
            </label>
            <button
              className="btn btn-primario ancho mk-boton"
              disabled={!motivo.trim() || rechazando}
              onClick={() => void rechazar()}
            >
              <X size={20} /> Rechazar OC
            </button>
          </Drawer.Content>
        </Drawer.Portal>
      </Drawer.Root>
    </div>
  );
}
