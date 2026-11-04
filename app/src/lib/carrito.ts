// Pedido en armado. Vive solo en el dispositivo: cerrar la app no lo borra.
// Guarda oferta y cantidad; los precios se leen siempre del catálogo vigente.
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface EstadoCarrito {
  /** Cantidad por oferta (producto + proveedor + presentación). */
  lineas: Record<string, number>;
  fijarCantidad: (ofertaId: string, cantidad: number) => void;
  quitar: (ofertaIds: string[]) => void;
  vaciar: () => void;
}

export const useCarrito = create<EstadoCarrito>()(
  persist(
    (set) => ({
      lineas: {},
      fijarCantidad: (ofertaId, cantidad) =>
        set(({ lineas }) => {
          const nuevas = { ...lineas };
          if (cantidad > 0) nuevas[ofertaId] = cantidad;
          else delete nuevas[ofertaId];
          return { lineas: nuevas };
        }),
      quitar: (ofertaIds) =>
        set(({ lineas }) => {
          const nuevas = { ...lineas };
          for (const id of ofertaIds) delete nuevas[id];
          return { lineas: nuevas };
        }),
      vaciar: () => set({ lineas: {} }),
    }),
    { name: 'eskemia-carrito' },
  ),
);

/** Vibración corta al agregar, donde el dispositivo la permite. */
export function vibrar() {
  if (typeof navigator.vibrate === 'function') navigator.vibrate(10);
}
