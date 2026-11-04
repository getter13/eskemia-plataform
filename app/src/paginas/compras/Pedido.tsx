import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, ShieldAlert, Truck } from 'lucide-react';
import { NavCompras, Stepper } from '../../componentes/compras';
import { useCarrito } from '../../lib/carrito';
import {
  agruparPedido,
  evaluarOrden,
  formatoMoneda,
  useCatalogo,
  type EvaluacionOrden,
  type GrupoProveedor,
} from '../../lib/catalogo';
import { useSesion } from '../../lib/sesion';

const ESPERA_EVALUACION_MS = 400;

function TarjetaOrden({ grupo, sedeId }: { grupo: GrupoProveedor; sedeId: string }) {
  const fijarCantidad = useCarrito((s) => s.fijarCantidad);
  const [evaluacion, setEvaluacion] = useState<EvaluacionOrden | null>(null);
  const firma = grupo.lineas.map((l) => `${l.oferta.id}:${l.cantidad}`).join('|');

  useEffect(() => {
    let vigente = true;
    const timer = setTimeout(() => {
      void evaluarOrden(sedeId, grupo).then((r) => {
        if (vigente) setEvaluacion(r);
      });
    }, ESPERA_EVALUACION_MS);
    return () => {
      vigente = false;
      clearTimeout(timer);
    };
    // La firma resume el grupo: se recalcula en cada render aunque no cambie.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [firma, sedeId]);

  const minimo = grupo.montoMinimo;
  const faltaMinimo = minimo !== null && grupo.subtotal < minimo;

  return (
    <section className="tarjeta grupo mk-orden" data-testid="orden">
      <h2 className="mk-nombre">{grupo.proveedor}</h2>
      {grupo.lineas.map((l) => (
        <div className="mk-linea" key={l.oferta.id}>
          <span className="grupo mk-flex">
            <span>{l.producto.nombre}</span>
            <span className="muted">{l.oferta.presentacion}</span>
            <span className="mono">{l.oferta.precio === null ? 'Sin precio' : formatoMoneda(l.subtotal)}</span>
          </span>
          <Stepper etiqueta={l.producto.nombre} cantidad={l.cantidad} alCambiar={(c) => fijarCantidad(l.oferta.id, c)} />
        </div>
      ))}
      <div className="fila mk-subtotal">
        <span className="mk-flex">Subtotal</span>
        <strong className="mono">{formatoMoneda(grupo.subtotal)}</strong>
      </div>
      {minimo !== null && (
        <div className="grupo">
          <div
            className="mk-progreso"
            role="progressbar"
            aria-label="Pedido mínimo"
            aria-valuemin={0}
            aria-valuemax={minimo}
            aria-valuenow={Math.min(grupo.subtotal, minimo)}
          >
            <span style={{ width: `${minimo > 0 ? Math.min(100, (grupo.subtotal / minimo) * 100) : 100}%` }} />
          </div>
          <span className="muted">
            {faltaMinimo
              ? `Faltan ${formatoMoneda(minimo - grupo.subtotal)} para el mínimo de ${formatoMoneda(minimo)}`
              : `Alcanza el mínimo de ${formatoMoneda(minimo)}`}
          </span>
        </div>
      )}
      {grupo.plazoEntregaDias !== null && (
        <span className="muted mk-aviso">
          <Truck size={16} /> Entrega estimada: {grupo.plazoEntregaDias}{' '}
          {grupo.plazoEntregaDias === 1 ? 'día' : 'días'}
        </span>
      )}
      {grupo.sinPrecio && (
        <span className="mk-aviso">
          <AlertTriangle size={16} /> Hay productos sin precio: el total puede ser mayor.
        </span>
      )}
      {evaluacion?.estado === 'PENDIENTE_APROBACION' && (
        <span className="mk-aviso" data-testid="va-a-aprobacion">
          <ShieldAlert size={16} /> Esta orden va a aprobación.
        </span>
      )}
    </section>
  );
}

export function Pedido() {
  const navegar = useNavigate();
  const { perfil } = useSesion();
  const { productos, sinConexion } = useCatalogo(perfil?.sede_id);
  const lineas = useCarrito((s) => s.lineas);
  const quitar = useCarrito((s) => s.quitar);
  const { grupos, noDisponibles } = useMemo(() => agruparPedido(productos ?? [], lineas), [productos, lineas]);
  const total = grupos.reduce((n, g) => n + g.subtotal, 0);

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <button className="mk-paso mk-volver" aria-label="Volver al catálogo" onClick={() => navegar('/compras')}>
          <ChevronLeft size={24} />
        </button>
        <h1 className="mk-titulo">Tu pedido</h1>
      </header>
      <main className="mk-lista grupo-pedido">
        {sinConexion && (
          <p className="muted">Sin conexión: la aprobación de cada orden se revisa al confirmar.</p>
        )}
        {productos !== null && noDisponibles.length > 0 && (
          <div className="tarjeta grupo" role="status">
            <p>
              {noDisponibles.length === 1
                ? 'Un producto del pedido ya no está disponible.'
                : `${noDisponibles.length} productos del pedido ya no están disponibles.`}
            </p>
            <div>
              <button className="btn" onClick={() => quitar(noDisponibles)}>
                Quitar del pedido
              </button>
            </div>
          </div>
        )}
        {productos !== null && grupos.length === 0 && (
          <div className="mk-vacio">
            <p>Todavía no agregaste productos.</p>
            <button className="btn" onClick={() => navegar('/compras')}>
              Ir al catálogo
            </button>
          </div>
        )}
        {perfil && grupos.map((g) => <TarjetaOrden grupo={g} sedeId={perfil.sede_id} key={g.proveedorId} />)}
      </main>
      {grupos.length > 0 && (
        <footer className="mk-pie">
          <div className="fila">
            <span className="mk-flex">
              Total · {grupos.length} {grupos.length === 1 ? 'orden de compra' : 'órdenes de compra'}
            </span>
            <strong className="mono">{formatoMoneda(total)}</strong>
          </div>
          {/* confirmar_pedido llega en la etapa 6. */}
          <button className="btn btn-primario ancho mk-boton" disabled>
            Confirmar pedido
          </button>
          <span className="muted">La confirmación todavía no está disponible.</span>
        </footer>
      )}
      <NavCompras />
    </div>
  );
}
