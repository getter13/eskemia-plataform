// Piezas compartidas del marketplace móvil.
import { NavLink } from 'react-router-dom';
import { Home, Minus, Plus, ReceiptText, Search, ShieldAlert, ShoppingCart, User } from 'lucide-react';
import { Drawer } from 'vaul';
import { useCarrito, vibrar } from '../lib/carrito';
import { formatoMoneda, type ProductoCatalogo } from '../lib/catalogo';

export function NavCompras() {
  const claseDe = ({ isActive }: { isActive: boolean }) => `mk-nav-item${isActive ? ' activo' : ''}`;
  return (
    <nav className="mk-nav" aria-label="Compras">
      <NavLink className={claseDe} to="/compras" end>
        <Home size={24} /> Inicio
      </NavLink>
      <NavLink className="mk-nav-item" to="/compras?buscar=1">
        <Search size={24} /> Buscar
      </NavLink>
      <NavLink className={claseDe} to="/compras/pedidos">
        <ReceiptText size={24} /> Pedidos
      </NavLink>
      <NavLink className={claseDe} to="/compras/perfil">
        <User size={24} /> Perfil
      </NavLink>
    </nav>
  );
}

export function Stepper({
  etiqueta,
  cantidad,
  alCambiar,
}: {
  etiqueta: string;
  cantidad: number;
  alCambiar: (cantidad: number) => void;
}) {
  return (
    <div className="mk-stepper" role="group" aria-label={`Cantidad de ${etiqueta}`}>
      <button
        className="mk-paso"
        aria-label={cantidad === 1 ? `Quitar ${etiqueta}` : `Restar uno de ${etiqueta}`}
        onClick={(e) => {
          e.stopPropagation();
          alCambiar(cantidad - 1);
        }}
      >
        <Minus size={20} />
      </button>
      <span className="mk-cantidad mono" aria-live="polite">
        {cantidad}
      </span>
      <button
        className="mk-paso"
        aria-label={`Sumar uno de ${etiqueta}`}
        onClick={(e) => {
          e.stopPropagation();
          vibrar();
          alCambiar(cantidad + 1);
        }}
      >
        <Plus size={20} />
      </button>
    </div>
  );
}

export function EtiquetaAprobacion({ producto }: { producto: ProductoCatalogo }) {
  if (producto.regla_modo === 'SIEMPRE') {
    return (
      <span className="etiqueta etiqueta-neutra mk-etiqueta">
        <ShieldAlert size={16} /> Requiere aprobación
      </span>
    );
  }
  if (producto.regla_modo === 'POR_MONTO' && producto.regla_monto_umbral !== null) {
    return (
      <span className="etiqueta etiqueta-neutra mk-etiqueta">
        <ShieldAlert size={16} /> Aprobación si supera {formatoMoneda(producto.regla_monto_umbral)}
      </span>
    );
  }
  return null;
}

/** Elegir proveedor y presentación: cada fila es una oferta. Quien pide decide a quién comprarle. */
export function HojaProducto({ producto, alCerrar }: { producto: ProductoCatalogo | null; alCerrar: () => void }) {
  const lineas = useCarrito((s) => s.lineas);
  const fijarCantidad = useCarrito((s) => s.fijarCantidad);

  return (
    <Drawer.Root open={producto !== null} onOpenChange={(abierto) => !abierto && alCerrar()}>
      <Drawer.Portal>
        <Drawer.Overlay className="mk-hoja-fondo" />
        <Drawer.Content className="mk-hoja" aria-describedby={undefined}>
          <div className="mk-hoja-agarre" />
          {producto && (
            <>
              <Drawer.Title className="mk-hoja-titulo">{producto.nombre}</Drawer.Title>
              {producto.ofertas.length > 1 && (
                <p className="muted">Elegí a qué proveedor comprarle y en qué presentación.</p>
              )}
              <div className="mk-hoja-lista">
                {producto.ofertas.map((o) => {
                  const cantidad = lineas[o.id] ?? 0;
                  const etiqueta = `${producto.nombre} de ${o.proveedor}`;
                  return (
                    <div className="mk-oferta" data-testid="oferta" key={o.id}>
                      <span className="grupo mk-flex">
                        <strong>{o.proveedor}</strong>
                        <span className="muted">{o.presentacion}</span>
                        <span className="mono">{o.precio === null ? 'Sin precio' : formatoMoneda(o.precio)}</span>
                        {o.preferido && producto.ofertas.length > 1 && (
                          <span className="etiqueta mk-etiqueta">Preferido</span>
                        )}
                      </span>
                      {cantidad > 0 ? (
                        <Stepper etiqueta={etiqueta} cantidad={cantidad} alCambiar={(c) => fijarCantidad(o.id, c)} />
                      ) : (
                        <button
                          className="mk-paso mk-agregar"
                          aria-label={`Agregar ${etiqueta}`}
                          onClick={() => {
                            vibrar();
                            fijarCantidad(o.id, 1);
                          }}
                        >
                          <Plus size={20} />
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
              <button className="btn btn-primario ancho mk-boton" onClick={alCerrar}>
                <ShoppingCart size={20} /> Volver al catálogo
              </button>
            </>
          )}
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}
