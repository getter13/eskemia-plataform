import { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, ChevronRight, CloudOff, Search } from 'lucide-react';
import { formatearMonto, normalizar } from '../../lib/catalogo';
import { formatoFecha, formatoFechaHora } from '../../lib/formato';
import { ETIQUETA_ESTADO_OC, estaAtrasada, useOrdenes, type EstadoOc, type OrdenResumen } from '../../lib/ordenes';

const FILTROS: Array<{ clave: string; etiqueta: string; coincide: (o: OrdenResumen) => boolean }> = [
  { clave: 'todas', etiqueta: 'Todas', coincide: () => true },
  { clave: 'aprobacion', etiqueta: 'En aprobación', coincide: (o) => o.estado === 'PENDIENTE_APROBACION' },
  {
    clave: 'esperando',
    etiqueta: 'Por recibir',
    coincide: (o) => (['APROBADA', 'ENVIADA', 'RECIBIDA_PARCIAL'] as EstadoOc[]).includes(o.estado),
  },
  { clave: 'atrasadas', etiqueta: 'Atrasadas', coincide: estaAtrasada },
  { clave: 'recibidas', etiqueta: 'Recibidas', coincide: (o) => o.estado === 'RECIBIDA' || o.estado === 'CERRADA' },
  { clave: 'canceladas', etiqueta: 'Rechazadas y anuladas', coincide: (o) => o.estado === 'RECHAZADA' || o.estado === 'ANULADA' },
];

export function Tablero() {
  const navegar = useNavigate();
  const { ordenes, sinConexion } = useOrdenes();
  const [filtro, setFiltro] = useState('todas');
  const [busqueda, setBusqueda] = useState('');

  const visibles = useMemo(() => {
    const elegido = FILTROS.find((f) => f.clave === filtro) ?? FILTROS[0];
    const texto = normalizar(busqueda);
    return (ordenes ?? []).filter(
      (o) =>
        elegido.coincide(o) &&
        (!texto || normalizar(`${o.numero} ${o.proveedores?.nombre ?? ''} ${o.proveedores?.codigo ?? ''}`).includes(texto)),
    );
  }, [ordenes, filtro, busqueda]);

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera">
        <h1 className="mk-titulo">Órdenes de compra</h1>
        <label className="mk-buscador">
          <Search size={20} />
          <span className="solo-lector">Buscar orden</span>
          <input
            type="search"
            placeholder="Número o proveedor"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
          />
        </label>
        <div className="mk-chips" role="group" aria-label="Filtrar por estado">
          {FILTROS.map((f) => (
            <button className="mk-chip" aria-pressed={filtro === f.clave} key={f.clave} onClick={() => setFiltro(f.clave)}>
              {f.etiqueta}
            </button>
          ))}
        </div>
        {sinConexion && (
          <p className="mk-aviso muted" role="status">
            <CloudOff size={16} /> Sin conexión: estados de la última actualización.
          </p>
        )}
      </header>
      <main className="mk-lista grupo-pedido">
        {ordenes !== null && visibles.length === 0 && (
          <div className="mk-vacio">
            <p>{ordenes.length === 0 ? 'Todavía no hay órdenes de compra.' : 'Ninguna orden coincide con el filtro.'}</p>
            {ordenes.length > 0 && (
              <button
                className="btn"
                onClick={() => {
                  setFiltro('todas');
                  setBusqueda('');
                }}
              >
                Ver todas las órdenes
              </button>
            )}
          </div>
        )}
        {visibles.map((o) => (
          <Link className="mk-tarjeta mk-enlace" data-testid="orden-tablero" key={o.id} to={`/compras/oc/${o.id}`}>
            <span className="grupo mk-flex">
              <strong>{o.proveedores?.nombre}</strong>
              <span className="datos muted">{o.numero}</span>
              <span className="muted">
                {formatoFechaHora(o.creado_en)}
                {o.fecha_entrega_estimada && ` · Entrega ${formatoFecha(o.fecha_entrega_estimada)}`}
              </span>
              <span className="fila mk-etiquetas">
                <span className="etiqueta etiqueta-neutra mk-etiqueta">{ETIQUETA_ESTADO_OC[o.estado]}</span>
                {estaAtrasada(o) && (
                  <span className="etiqueta etiqueta-error mk-etiqueta">
                    <AlertTriangle size={16} /> Atrasada
                  </span>
                )}
              </span>
            </span>
            <span className="datos">{formatearMonto(o.total_estimado)}</span>
            <ChevronRight size={20} />
          </Link>
        ))}
      </main>
      <footer className="mk-pie">
        <button className="btn mk-boton" onClick={() => navegar('/')}>
          <ChevronLeft size={20} /> Volver al inicio
        </button>
      </footer>
    </div>
  );
}
