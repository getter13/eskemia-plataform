import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { ArrowLeft, ChevronRight, FolderOpen } from 'lucide-react';
import { db, type Producto } from '../lib/db';
import { unidadCorta } from '../lib/formato';
import { Modal } from './Modal';

const SIN_CATEGORIA = '__sin_categoria__';

/** Navegación táctil: categoría y luego producto. No se tipea ningún código. */
export function SelectorProducto({
  titulo,
  alElegir,
  alCerrar,
}: {
  titulo: string;
  alElegir: (producto: Producto) => void;
  alCerrar: () => void;
}) {
  const [categoria, setCategoria] = useState<string | null>(null);
  const categorias = useLiveQuery(() => db.categorias.orderBy('orden').toArray(), []) ?? [];
  const productos = useLiveQuery(() => db.productos.toArray(), []) ?? [];

  const sinCategoria = productos.filter((p) => !p.categoria_id);
  const visibles = (categoria === SIN_CATEGORIA
    ? sinCategoria
    : productos.filter((p) => p.categoria_id === categoria)
  ).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));

  const nombreCategoria =
    categoria === SIN_CATEGORIA
      ? 'Sin categoría'
      : categorias.find((c) => c.id === categoria)?.nombre;

  return (
    <Modal titulo={categoria ? (nombreCategoria ?? titulo) : titulo} alCerrar={alCerrar}>
      {categoria === null ? (
        <div className="grilla">
          {categorias.map((c) => (
            <button className="tarjeta tarjeta-tactil" key={c.id} onClick={() => setCategoria(c.id)}>
              <FolderOpen size={32} />
              <span className="grilla-nombre">{c.nombre}</span>
            </button>
          ))}
          {sinCategoria.length > 0 && (
            <button className="tarjeta tarjeta-tactil" onClick={() => setCategoria(SIN_CATEGORIA)}>
              <FolderOpen size={32} />
              <span className="grilla-nombre">Sin categoría</span>
            </button>
          )}
        </div>
      ) : (
        <>
          <button className="btn" onClick={() => setCategoria(null)}>
            <ArrowLeft size={24} /> Volver a categorías
          </button>
          <div className="grilla">
            {visibles.map((p) => (
              <button className="tarjeta tarjeta-tactil" key={p.id} onClick={() => alElegir(p)}>
                <span className="grupo" style={{ flex: 1 }}>
                  <span className="grilla-nombre">{p.nombre}</span>
                  <span className="muted">En {unidadCorta(p.tipo_medida)}</span>
                </span>
                <ChevronRight size={24} />
              </button>
            ))}
          </div>
        </>
      )}
    </Modal>
  );
}
