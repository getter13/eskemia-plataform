import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, Ban, CheckCircle2, ChevronLeft, Circle, CircleSlash, Download, Mail, MessageCircle, Send, ShieldAlert } from 'lucide-react';
import { Drawer } from 'vaul';
import { NavCompras } from '../../componentes/compras';
import { formatoMoneda } from '../../lib/catalogo';
import { tienePermiso } from '../../lib/db';
import { ETIQUETA_ESTADO, formatoFecha, formatoFechaHora, formatoNumero } from '../../lib/formato';
import { useSesion } from '../../lib/sesion';
import {
  ETIQUETA_ESTADO_OC,
  anularOc,
  cerrarSaldoOc,
  enlaceCorreo,
  enlaceWhatsApp,
  marcarEnviada,
  pasosSeguimiento,
  traerOrden,
  type ItemOrden,
  type OrdenResumen,
  type RecepcionDeOrden,
  type SaldoOrden,
} from '../../lib/ordenes';

async function descargarPdf(orden: OrdenResumen, items: ItemOrden[]) {
  const { generarPdfOrden } = await import('../../lib/ordenPdf');
  const blob = await generarPdfOrden(orden, items);
  const url = URL.createObjectURL(blob);
  const enlace = document.createElement('a');
  enlace.href = url;
  enlace.download = `${orden.numero}.pdf`;
  enlace.click();
  URL.revokeObjectURL(url);
}

export function Orden() {
  const navegar = useNavigate();
  const { id } = useParams();
  const [orden, setOrden] = useState<OrdenResumen | null>(null);
  const [items, setItems] = useState<ItemOrden[]>([]);
  const [cargada, setCargada] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [generando, setGenerando] = useState(false);
  const { perfil } = useSesion();
  const [saldos, setSaldos] = useState<SaldoOrden[]>([]);
  const [recepciones, setRecepciones] = useState<RecepcionDeOrden[]>([]);
  const [accion, setAccion] = useState<'anular' | 'cerrar' | null>(null);
  const [motivo, setMotivo] = useState('');
  const [decidiendo, setDecidiendo] = useState(false);

  const cargar = useCallback(async () => {
    if (!id) return;
    try {
      const r = await traerOrden(id);
      setOrden(r.orden);
      setItems(r.items);
      setSaldos(r.saldos);
      setRecepciones(r.recepciones);
      setError(null);
    } catch {
      setError('No se pudo cargar la orden. Revisá la conexión.');
    }
    setCargada(true);
  }, [id]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const whatsapp = orden && enlaceWhatsApp(orden, items);
  const correo = orden && enlaceCorreo(orden, items);
  const puedeEnviar = orden?.estado === 'APROBADA';
  const seCompartio = orden && orden.estado !== 'PENDIENTE_APROBACION' && orden.estado !== 'RECHAZADA' && orden.estado !== 'ANULADA';

  const conRecepciones = recepciones.some((r) => r.estado !== 'RECHAZADA');
  const puedeAnular =
    tienePermiso(perfil, 'compras.oc.anular') &&
    (orden?.estado === 'APROBADA' || orden?.estado === 'ENVIADA') &&
    !conRecepciones;
  const puedeCerrar = tienePermiso(perfil, 'compras.oc.cerrar_saldo') && orden?.estado === 'RECIBIDA_PARCIAL';

  async function decidir() {
    if (!orden || !accion) return;
    setDecidiendo(true);
    try {
      await (accion === 'anular' ? anularOc : cerrarSaldoOc)(orden.id, motivo);
      setMotivo('');
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo guardar el cambio.');
    }
    setAccion(null);
    setDecidiendo(false);
  }

  async function marcar(canal: 'MANUAL' | 'WHATSAPP' | 'EMAIL') {
    if (!orden) return;
    try {
      await marcarEnviada(orden.id, canal);
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo marcar como enviada.');
    }
  }

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <button className="mk-paso mk-volver" aria-label="Volver" onClick={() => navegar(-1)}>
          <ChevronLeft size={24} />
        </button>
        <h1 className="mk-titulo mono mk-numero">{orden?.numero ?? 'Orden de compra'}</h1>
      </header>
      <main className="mk-lista grupo-pedido">
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        {cargada && !orden && !error && (
          <div className="mk-vacio">
            <p>No encontramos esta orden.</p>
          </div>
        )}
        {orden && (
          <>
            <section className="tarjeta grupo mk-orden">
              <h2 className="mk-nombre">{orden.proveedores?.nombre}</h2>
              <span className="etiqueta etiqueta-neutra mk-etiqueta" data-testid="estado-orden">
                {ETIQUETA_ESTADO_OC[orden.estado]}
              </span>
              {orden.fecha_entrega_estimada && (
                <span className="muted">Entrega estimada: {formatoFecha(orden.fecha_entrega_estimada)}</span>
              )}
              {orden.motivo_rechazo && (
                <span className="aviso-error">
                  <AlertTriangle size={16} /> {orden.motivo_rechazo}
                </span>
              )}
              {orden.motivo_cierre && (
                <span className="mk-aviso" data-testid="motivo-cierre">
                  <AlertTriangle size={16} /> {orden.motivo_cierre}
                </span>
              )}
            </section>

            <section className="tarjeta grupo mk-orden" aria-label="Seguimiento">
              <h2 className="mk-nombre">Seguimiento</h2>
              <ol className="mk-seguimiento">
                {pasosSeguimiento(orden).map((p) => (
                  <li key={p.etiqueta} className={p.hecho ? 'hecho' : ''}>
                    {p.hecho ? <CheckCircle2 size={20} /> : <Circle size={20} />}
                    <span className="grupo">
                      <span>{p.etiqueta}</span>
                      {p.fecha && <span className="muted mono">{formatoFechaHora(p.fecha)}</span>}
                    </span>
                  </li>
                ))}
              </ol>
            </section>

            <section className="tarjeta grupo mk-orden">
              <h2 className="mk-nombre">Productos</h2>
              {items.map((i) => (
                <div className="mk-linea" key={i.id}>
                  <span className="grupo mk-flex">
                    <span>{i.producto_nombre}</span>
                    <span className="muted">
                      {formatoNumero(i.cantidad)} x {i.presentacion_nombre}
                    </span>
                    {i.disparo_aprobacion && (
                      <span className="mk-aviso">
                        <ShieldAlert size={16} /> Requiere aprobación
                      </span>
                    )}
                  </span>
                  <span className="mono">{formatoMoneda(i.subtotal)}</span>
                </div>
              ))}
              <div className="fila mk-subtotal">
                <span className="mk-flex">Total estimado</span>
                <strong className="mono">{formatoMoneda(orden.total_estimado)}</strong>
              </div>
            </section>

            {recepciones.length > 0 && (
              <section className="tarjeta grupo mk-orden" data-testid="saldos">
                <h2 className="mk-nombre">Pedido y recibido</h2>
                {saldos.map((s) => {
                  const pedido = Number(s.cant_pedida);
                  const recibido = Number(s.cant_recibida);
                  return (
                    <div className="mk-linea" key={s.producto_id}>
                      <span className="mk-flex">{s.producto_nombre}</span>
                      <span className="mono">
                        {formatoNumero(recibido)} de {formatoNumero(pedido)}
                        {recibido !== pedido && ` · ${recibido < pedido ? 'Falta' : 'Sobra'} ${formatoNumero(Math.abs(pedido - recibido))}`}
                      </span>
                    </div>
                  );
                })}
                <h2 className="mk-nombre">Recepciones</h2>
                {recepciones.map((r) => (
                  <div className="mk-linea" key={r.id}>
                    <span className="grupo mk-flex">
                      <span className="mono">{r.nro_remito}</span>
                      <span className="muted">{formatoFechaHora(r.abierta_en)}</span>
                    </span>
                    <span className="etiqueta etiqueta-neutra mk-etiqueta">{ETIQUETA_ESTADO[r.estado]}</span>
                  </div>
                ))}
              </section>
            )}

            {seCompartio && (
              <section className="tarjeta grupo mk-orden">
                <h2 className="mk-nombre">Enviar al proveedor</h2>
                {whatsapp && (
                  <a className="btn mk-boton mk-acceso" href={whatsapp} target="_blank" rel="noreferrer">
                    <MessageCircle size={20} /> Compartir por WhatsApp
                  </a>
                )}
                {correo && (
                  <a className="btn mk-boton mk-acceso" href={correo}>
                    <Mail size={20} /> Enviar por correo
                  </a>
                )}
                {!whatsapp && !correo && (
                  <p className="muted">Este proveedor no tiene WhatsApp ni correo cargados. Descargá el PDF para enviárselo.</p>
                )}
                <button
                  className="btn mk-boton mk-acceso"
                  disabled={generando}
                  onClick={async () => {
                    setGenerando(true);
                    try {
                      await descargarPdf(orden, items);
                    } catch {
                      setError('No se pudo generar el PDF. Revisá la conexión y volvé a intentar.');
                    }
                    setGenerando(false);
                  }}
                >
                  <Download size={20} /> {generando ? 'Generando el PDF…' : 'Descargar PDF'}
                </button>
              </section>
            )}

            {(puedeAnular || puedeCerrar) && (
              <section className="grupo">
                {puedeCerrar && (
                  <button className="btn mk-boton mk-acceso" onClick={() => setAccion('cerrar')}>
                    <CircleSlash size={20} /> Cerrar saldo pendiente
                  </button>
                )}
                {puedeAnular && (
                  <button className="btn mk-boton mk-acceso" onClick={() => setAccion('anular')}>
                    <Ban size={20} /> Anular orden
                  </button>
                )}
              </section>
            )}
          </>
        )}
      </main>
      {puedeEnviar && (
        <footer className="mk-pie">
          <button
            className="btn btn-primario ancho mk-boton"
            onClick={() => void marcar(whatsapp ? 'WHATSAPP' : correo ? 'EMAIL' : 'MANUAL')}
          >
            <Send size={20} /> Marcar como enviada
          </button>
        </footer>
      )}
      <NavCompras />
      <Drawer.Root
        open={accion !== null}
        onOpenChange={(abierto) => {
          if (!abierto) setAccion(null);
        }}
      >
        <Drawer.Portal>
          <Drawer.Overlay className="mk-hoja-fondo" />
          <Drawer.Content className="mk-hoja" aria-describedby={undefined}>
            <div className="mk-hoja-agarre" />
            <Drawer.Title className="mk-hoja-titulo">
              {accion === 'anular' ? 'Anular la orden' : 'Cerrar el saldo pendiente'}
            </Drawer.Title>
            <p className="muted">
              {accion === 'anular'
                ? 'La orden deja de estar pendiente en Recepción. No se puede deshacer.'
                : 'Lo que falta deja de esperarse y la orden sale de Recepción. No se puede deshacer.'}
            </p>
            <label className="grupo">
              <span className="label">Motivo</span>
              <textarea className="campo campo-texto" rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
            </label>
            <button
              className="btn btn-primario ancho mk-boton"
              data-testid="confirmar-accion-oc"
              disabled={!motivo.trim() || decidiendo}
              onClick={() => void decidir()}
            >
              {accion === 'anular' ? `Anular ${orden?.numero}` : `Cerrar saldo de ${orden?.numero}`}
            </button>
          </Drawer.Content>
        </Drawer.Portal>
      </Drawer.Root>
    </div>
  );
}
