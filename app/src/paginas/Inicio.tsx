import { useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Navigate, useNavigate, useSearchParams } from 'react-router-dom';
import { AlertTriangle, ChevronRight, ClipboardList, FileText, FileUp, LogOut, PackagePlus, ShieldCheck, ShoppingCart } from 'lucide-react';
import { Encabezado } from '../componentes/Encabezado';
import { Modal } from '../componentes/Modal';
import { db, tienePermiso, type RecepcionLocal } from '../lib/db';
import { ETIQUETA_ESTADO, formatoFecha, formatoFechaHora } from '../lib/formato';
import { reabrirRecepcion } from '../lib/operaciones';
import { cerrarSesion, useSesion } from '../lib/sesion';

const ETIQUETA_PENDIENTE: Record<string, string> = {
  PENDIENTE_APROBACION: 'En aprobación',
  RECIBIDA_PARCIAL: 'Recibida parcial',
};

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
  const ordenes = useLiveQuery(() => db.pendientes.toArray(), []) ?? [];
  const [parametros] = useSearchParams();
  const puedeComprar = tienePermiso(perfil, 'compras.catalogo.ver');

  // Una orden que ya se está recibiendo en esta tablet sigue desde "Recepciones abiertas".
  const ordenesVisibles = ordenes.filter((o) => !recepciones.some((r) => r.oc_id === o.id));

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

  // Quien compra arranca en el marketplace; el kiosco sigue a un toque desde su perfil.
  if (puedeComprar && !puedeOperar) return <Navigate to="/compras" replace />;
  if (puedeComprar && !parametros.has('kiosco') && !tienePermiso(perfil, 'recepcion.recepcion.validar')) {
    return <Navigate to="/compras" replace />;
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
              <h2>Pendientes de recibir</h2>
              {ordenesVisibles.length === 0 && <p className="muted">No hay órdenes de compra pendientes.</p>}
              {ordenesVisibles.map((o) => (
                <button
                  className="tarjeta tarjeta-tactil"
                  data-testid="oc-pendiente"
                  disabled={!o.se_puede_recibir}
                  key={o.id}
                  onClick={() => navegar(`/recepcion/nueva?oc=${o.id}`)}
                >
                  <span className="grupo" style={{ flex: 1 }}>
                    <span className="grilla-nombre">{o.proveedor}</span>
                    <span className="muted">
                      <span className="mono">{o.numero}</span> · {o.items.filter((i) => i.saldo > 0).length} productos
                      {o.fecha_entrega_estimada && ` · Entrega ${formatoFecha(o.fecha_entrega_estimada)}`}
                    </span>
                    <span className="fila">
                      {o.atrasada && (
                        <span className="etiqueta etiqueta-error">
                          <AlertTriangle size={16} /> Atrasada
                        </span>
                      )}
                      {o.no_enviada && <span className="etiqueta etiqueta-alerta">No enviada</span>}
                      {ETIQUETA_PENDIENTE[o.estado] && (
                        <span className="etiqueta etiqueta-neutra">{ETIQUETA_PENDIENTE[o.estado]}</span>
                      )}
                    </span>
                  </span>
                  {o.se_puede_recibir && <ChevronRight size={24} />}
                </button>
              ))}
            </section>

            <section className="grupo">
              <h2>Recepciones abiertas</h2>
              {recepciones.length === 0 && <p className="muted">No hay recepciones abiertas.</p>}
              {recepciones.map((r) => (
                <button className="tarjeta tarjeta-tactil" key={r.id} onClick={() => void abrir(r)}>
                  <span className="grupo" style={{ flex: 1 }}>
                    <span className="grilla-nombre">{r.proveedor_nombre}</span>
                    <span className="muted">
                      {r.oc_numero && <span className="mono">{r.oc_numero} · </span>}
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
        {puedeComprar && (
          <button className="btn" onClick={() => navegar('/compras')}>
            <ShoppingCart size={20} /> Compras
          </button>
        )}
        {tienePermiso(perfil, 'compras.oc.ver_todas') && (
          <button className="btn" onClick={() => navegar('/compras/oc')}>
            <FileText size={20} /> Órdenes de compra
          </button>
        )}
        {tienePermiso(perfil, 'compras.catalogo.gestionar') && (
          <button className="btn" onClick={() => navegar('/admin/importar')}>
            <FileUp size={20} /> Importar catálogo
          </button>
        )}
        {tienePermiso(perfil, 'compras.aprobacion.configurar') && (
          <button className="btn" onClick={() => navegar('/compras/reglas')}>
            <ShieldCheck size={20} /> Reglas de aprobación
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
