import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronRight, ClipboardList, LogOut, PackagePlus } from 'lucide-react';
import { Encabezado } from '../componentes/Encabezado';
import { Modal } from '../componentes/Modal';
import { db, tienePermiso, type RecepcionLocal } from '../lib/db';
import { ETIQUETA_ESTADO, formatoFechaHora } from '../lib/formato';
import { reabrirRecepcion } from '../lib/operaciones';
import { cerrarSesion, useSesion } from '../lib/sesion';

const ORDEN: RecepcionLocal['estado'][] = ['ABIERTA', 'EN_CONTROL', 'RECHAZADA'];

export function Inicio() {
  const navegar = useNavigate();
  const { perfil } = useSesion();
  const puedeOperar = tienePermiso(perfil, 'recepcion.recepcion.operar');
  const [confirmarSalida, setConfirmarSalida] = useState(false);
  const recepciones =
    useLiveQuery(
      () =>
        db.recepciones
          .where('estado')
          .anyOf(ORDEN)
          .toArray()
          .then((r) => r.sort((a, b) => b.abierta_en.localeCompare(a.abierta_en))),
      [],
    ) ?? [];
  const pendientes = useLiveQuery(() => db.cola.count(), []) ?? 0;

  async function abrir(r: RecepcionLocal) {
    if (r.estado === 'RECHAZADA') {
      await reabrirRecepcion(r.id);
      navegar(`/recepcion/${r.id}/resumen`);
    } else if (r.estado === 'EN_CONTROL') {
      navegar(`/recepcion/${r.id}/resumen`);
    } else {
      navegar(`/recepcion/${r.id}/carga`);
    }
  }

  return (
    <div className="pantalla">
      <Encabezado>
        <span className="muted">{perfil?.nombre}</span>
      </Encabezado>
      <main className="contenido">
        {puedeOperar ? (
          <>
            <button
              className="btn btn-primario btn-grande inicio-cta"
              onClick={() => navegar('/recepcion/nueva')}
            >
              <PackagePlus size={48} /> Nueva recepción
            </button>

            <section className="grupo">
              <h2>Recepciones abiertas</h2>
              {recepciones.length === 0 && <p className="muted">No hay recepciones abiertas.</p>}
              {recepciones.map((r) => (
                <button className="tarjeta tarjeta-tactil" key={r.id} onClick={() => void abrir(r)}>
                  <span className="grupo" style={{ flex: 1 }}>
                    <span className="grilla-nombre">{r.proveedor_nombre}</span>
                    <span className="muted">
                      Remito o factura <span className="mono">{r.nro_remito}</span> ·{' '}
                      {formatoFechaHora(r.abierta_en)}
                    </span>
                    {r.estado === 'RECHAZADA' && r.observacion && (
                      <span className="aviso-error">
                        <AlertTriangle size={20} /> {r.observacion}
                      </span>
                    )}
                  </span>
                  <span className={`etiqueta${r.estado === 'RECHAZADA' ? ' etiqueta-error' : ''}`}>
                    {ETIQUETA_ESTADO[r.estado]}
                  </span>
                  <ChevronRight size={24} />
                </button>
              ))}
            </section>
          </>
        ) : (
          <p className="muted">Tu usuario no tiene habilitada la recepción de mercadería.</p>
        )}
      </main>
      <footer className="barra-acciones">
        {tienePermiso(perfil, 'recepcion.recepcion.validar') && (
          <button className="btn" onClick={() => navegar('/admin')}>
            <ClipboardList size={20} /> Administración
          </button>
        )}
        <span className="espacio" />
        <button
          className="btn btn-texto"
          onClick={() => (pendientes > 0 ? setConfirmarSalida(true) : void cerrarSesion())}
        >
          <LogOut size={20} /> Salir
        </button>
      </footer>
      {confirmarSalida && (
        <Modal titulo="Todavía no podés salir" alCerrar={() => setConfirmarSalida(false)}>
          <p>
            Hay {pendientes} operaciones sin sincronizar. Si salís ahora, se perderían. Esperá a que
            el indicador diga "Sincronizado".
          </p>
        </Modal>
      )}
    </div>
  );
}
