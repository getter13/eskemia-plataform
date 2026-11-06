import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useVirtualizer } from '@tanstack/react-virtual';
import { AlertTriangle, CloudOff, Plus, Search, ShoppingCart } from 'lucide-react';
import { EtiquetaAprobacion, HojaProducto, NavCompras, Stepper } from '../../componentes/compras';
import { useCarrito, vibrar } from '../../lib/carrito';
import {
  agruparPedido,
  filtrarCatalogo,
  formatearMonto,
  rubrosDe,
  useCatalogo,
  type ProductoCatalogo,
} from '../../lib/catalogo';
import { useSesion } from '../../lib/sesion';

function TarjetaProducto({
  producto,
  alAbrir,
}: {
  producto: ProductoCatalogo;
  alAbrir: (p: ProductoCatalogo) => void;
}) {
  const lineas = useCarrito((s) => s.lineas);
  const fijarCantidad = useCarrito((s) => s.fijarCantidad);
  const ofertas = producto.ofertas;
  const enPedido = ofertas.find((o) => lineas[o.id]);
  const mostrada = enPedido ?? ofertas[0];
  const varias = ofertas.length > 1;
  const precios = ofertas.flatMap((o) => (o.precio === null ? [] : [o.precio]));

  return (
    <article className="mk-tarjeta" data-testid="producto" onClick={() => alAbrir(producto)}>
      <div className="grupo mk-flex">
        <h3 className="mk-nombre">{producto.nombre}</h3>
        {varias && !enPedido ? (
          <>
            <span className="muted">{ofertas.length} proveedores: elegí a quién comprarle</span>
            {precios.length > 0 && <span className="datos">Desde {formatearMonto(Math.min(...precios))}</span>}
          </>
        ) : (
          <>
            <span className="muted">
              {mostrada.presentacion} · {mostrada.proveedor}
            </span>
            <span className="datos">{mostrada.precio === null ? 'Sin precio' : formatearMonto(mostrada.precio)}</span>
          </>
        )}
        <EtiquetaAprobacion producto={producto} />
      </div>
      {enPedido ? (
        <Stepper
          etiqueta={producto.nombre}
          cantidad={lineas[enPedido.id]}
          alCambiar={(c) => fijarCantidad(enPedido.id, c)}
        />
      ) : (
        <button
          className="mk-paso mk-agregar"
          aria-label={varias ? `Elegir proveedor de ${producto.nombre}` : `Agregar ${producto.nombre}`}
          onClick={(e) => {
            e.stopPropagation();
            if (varias) {
              alAbrir(producto);
            } else {
              vibrar();
              fijarCantidad(ofertas[0].id, 1);
            }
          }}
        >
          <Plus size={20} />
        </button>
      )}
    </article>
  );
}

export function Marketplace() {
  const navegar = useNavigate();
  const { perfil } = useSesion();
  const [parametros, setParametros] = useSearchParams();
  const { productos, sinConexion, error } = useCatalogo(perfil?.sede_id);
  const lineas = useCarrito((s) => s.lineas);
  const [busqueda, setBusqueda] = useState('');
  const [rubroId, setRubroId] = useState<string | null>(null);
  const [abierto, setAbierto] = useState<ProductoCatalogo | null>(null);
  const contenedor = useRef<HTMLDivElement>(null);
  const buscador = useRef<HTMLInputElement>(null);

  const quiereBuscar = parametros.get('buscar') === '1';
  useEffect(() => {
    if (!quiereBuscar) return;
    buscador.current?.focus();
    setParametros({}, { replace: true });
  }, [quiereBuscar, setParametros]);

  const rubros = useMemo(() => rubrosDe(productos ?? []), [productos]);
  const visibles = useMemo(
    () => filtrarCatalogo(productos ?? [], busqueda, rubroId),
    [productos, busqueda, rubroId],
  );
  const { grupos } = useMemo(() => agruparPedido(productos ?? [], lineas), [productos, lineas]);
  const items = grupos.reduce((n, g) => n + g.lineas.length, 0);
  const total = grupos.reduce((n, g) => n + g.subtotal, 0);

  const virtual = useVirtualizer({
    count: visibles.length,
    getScrollElement: () => contenedor.current,
    estimateSize: () => 120,
    overscan: 6,
  });

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera">
        <label className="mk-buscador">
          <Search size={20} />
          <span className="solo-lector">Buscar en el catálogo</span>
          <input
            ref={buscador}
            type="search"
            placeholder="Buscar producto, SKU o proveedor"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
          />
        </label>
        {rubros.length > 0 && (
          <div className="mk-chips" role="group" aria-label="Filtrar por rubro">
            <button className="mk-chip" aria-pressed={rubroId === null} onClick={() => setRubroId(null)}>
              Todos
            </button>
            {rubros.map((r) => (
              <button className="mk-chip" aria-pressed={rubroId === r.id} key={r.id} onClick={() => setRubroId(r.id)}>
                {r.nombre}
              </button>
            ))}
          </div>
        )}
        {sinConexion && (
          <p className="mk-aviso muted" role="status">
            <CloudOff size={16} /> Sin conexión: precios de la última actualización.
          </p>
        )}
      </header>

      <div className="mk-lista" ref={contenedor}>
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        {productos === null && !error && (
          <div className="grupo" aria-hidden="true">
            {[0, 1, 2, 3].map((i) => (
              <div className="mk-esqueleto" key={i} />
            ))}
          </div>
        )}
        {productos !== null && visibles.length === 0 && (
          <div className="mk-vacio">
            <p>{productos.length === 0 ? 'Todavía no hay productos para pedir.' : 'No encontramos ese producto.'}</p>
            {productos.length > 0 && (
              <button
                className="btn"
                onClick={() => {
                  setBusqueda('');
                  setRubroId(null);
                }}
              >
                Ver todo el catálogo
              </button>
            )}
          </div>
        )}
        <div style={{ height: virtual.getTotalSize(), position: 'relative' }}>
          {virtual.getVirtualItems().map((fila) => (
            <div
              key={visibles[fila.index].producto_id}
              data-index={fila.index}
              ref={virtual.measureElement}
              className="mk-fila"
              style={{ transform: `translateY(${fila.start}px)` }}
            >
              <TarjetaProducto producto={visibles[fila.index]} alAbrir={setAbierto} />
            </div>
          ))}
        </div>
      </div>

      {items > 0 && (
        <button className="mk-barra-pedido" data-testid="barra-pedido" onClick={() => navegar('/compras/pedido')}>
          <ShoppingCart size={24} />
          <span className="mk-flex">
            {grupos.length} {grupos.length === 1 ? 'proveedor' : 'proveedores'} · {items}{' '}
            {items === 1 ? 'ítem' : 'ítems'} · {formatearMonto(total)}
          </span>
          <strong>Ver pedido</strong>
        </button>
      )}
      <NavCompras />
      <HojaProducto producto={abierto} alCerrar={() => setAbierto(null)} />
    </div>
  );
}
