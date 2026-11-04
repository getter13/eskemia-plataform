import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, CheckCircle2, ChevronLeft, Circle, Download, Mail, MessageCircle, Send, ShieldAlert } from 'lucide-react';
import { NavCompras } from '../../componentes/compras';
import { formatoMoneda } from '../../lib/catalogo';
import { formatoFecha, formatoFechaHora, formatoNumero } from '../../lib/formato';
import {
  ETIQUETA_ESTADO_OC,
  enlaceCorreo,
  enlaceWhatsApp,
  marcarEnviada,
  pasosSeguimiento,
  traerOrden,
  type ItemOrden,
  type OrdenResumen,
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

  const cargar = useCallback(async () => {
    if (!id) return;
    try {
      const r = await traerOrden(id);
      setOrden(r.orden);
      setItems(r.items);
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
        <button className="mk-paso mk-volver" aria-label="Volver a pedidos" onClick={() => navegar('/compras/pedidos')}>
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
    </div>
  );
}
