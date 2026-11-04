import { useEffect, useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Link, useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronRight, ClipboardList, CloudOff, FileUp, LogOut, RefreshCw, ScanLine, ShieldCheck, Users } from 'lucide-react';
import { NavCompras } from '../../componentes/compras';
import { formatoMoneda } from '../../lib/catalogo';
import { db, tienePermiso } from '../../lib/db';
import { formatoFechaHora } from '../../lib/formato';
import { ETIQUETA_ESTADO_OC, recuperarPedido, useOrdenes, type ResumenEnCola } from '../../lib/ordenes';
import { cerrarSesion, useSesion } from '../../lib/sesion';
import { pedirSincronizacion } from '../../lib/sync';

export function Pedidos() {
  const navegar = useNavigate();
  const { ordenes, sinConexion, recargar } = useOrdenes();
  const enCola =
    useLiveQuery(() => db.cola.where('estado').anyOf('pendiente', 'error').toArray(), [])?.filter(
      (o) => o.tipo === 'confirmar_pedido',
    ) ?? [];

  // Cuando sale de la cola, el pedido ya es una orden: se actualiza la lista.
  const cantidadEnCola = enCola.length;
  const anterior = useRef(0);
  useEffect(() => {
    if (cantidadEnCola < anterior.current) void recargar();
    anterior.current = cantidadEnCola;
  }, [cantidadEnCola, recargar]);

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <h1 className="mk-titulo">Pedidos</h1>
      </header>
      <main className="mk-lista grupo-pedido">
        {sinConexion && (
          <p className="mk-aviso muted" role="status">
            <CloudOff size={16} /> Sin conexión: estados de la última actualización.
          </p>
        )}

        {enCola.map((op) => {
          const resumen = op.args.resumen as ResumenEnCola;
          return (
            <section className="tarjeta grupo mk-orden" data-testid="pedido-en-cola" key={op.seq}>
              <strong>{resumen.proveedores.join(', ')}</strong>
              <span className="mono">{formatoMoneda(resumen.total)}</span>
              {op.estado === 'pendiente' ? (
                <span className="mk-aviso">
                  <RefreshCw size={16} /> Se confirma al volver la señal.
                </span>
              ) : (
                <>
                  <span className="aviso-error">
                    <AlertTriangle size={16} /> {op.error?.replace(/^[A-Z_]+:\s*/, '')}
                  </span>
                  <div className="fila">
                    <button
                      className="btn mk-boton"
                      onClick={async () => {
                        await recuperarPedido(op.seq!);
                        navegar('/compras/pedido');
                      }}
                    >
                      Corregir el pedido
                    </button>
                  </div>
                </>
              )}
            </section>
          );
        })}

        {ordenes?.map((o) => (
          <Link className="mk-tarjeta mk-enlace" data-testid="orden-resumen" key={o.id} to={`/compras/oc/${o.id}`}>
            <span className="grupo mk-flex">
              <strong>{o.proveedores?.nombre}</strong>
              <span className="mono muted">{o.numero}</span>
              <span className="muted">{formatoFechaHora(o.creado_en)}</span>
              <span className="etiqueta etiqueta-neutra mk-etiqueta">{ETIQUETA_ESTADO_OC[o.estado]}</span>
            </span>
            <span className="mono">{formatoMoneda(o.total_estimado)}</span>
            <ChevronRight size={20} />
          </Link>
        ))}

        {ordenes !== null && ordenes.length === 0 && enCola.length === 0 && (
          <div className="mk-vacio">
            <p>Todavía no hiciste pedidos.</p>
            <Link className="btn" to="/compras">
              Ir al catálogo
            </Link>
          </div>
        )}
      </main>
      <NavCompras />
    </div>
  );
}

const ACCESOS = [
  { permiso: 'recepcion.recepcion.operar', ruta: '/?kiosco=1', etiqueta: 'Kiosco de recepción', Icono: ScanLine },
  { permiso: 'recepcion.recepcion.validar', ruta: '/admin', etiqueta: 'Bandeja de recepciones', Icono: ClipboardList },
  { permiso: 'compras.aprobacion.configurar', ruta: '/compras/reglas', etiqueta: 'Reglas de aprobación', Icono: ShieldCheck },
  { permiso: 'compras.catalogo.gestionar', ruta: '/admin/importar', etiqueta: 'Importar catálogo', Icono: FileUp },
  { permiso: 'admin.usuarios.gestionar', ruta: '/admin/roles', etiqueta: 'Usuarios y roles', Icono: Users },
];

export function PerfilCompras() {
  const { perfil } = useSesion();
  const pendientes = useLiveQuery(() => db.cola.count(), []) ?? 0;
  const [aviso, setAviso] = useState(false);

  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <h1 className="mk-titulo">{perfil?.nombre}</h1>
      </header>
      <main className="mk-lista grupo-pedido">
        {ACCESOS.filter((a) => tienePermiso(perfil, a.permiso)).map(({ ruta, etiqueta, Icono }) => (
          <Link className="btn mk-boton mk-acceso" key={ruta} to={ruta}>
            <Icono size={20} /> {etiqueta}
          </Link>
        ))}
        {aviso && pendientes > 0 && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> Hay {pendientes} operaciones sin enviar. Si salís ahora se perderían: esperá a
            tener señal.
          </p>
        )}
        <button
          className="btn btn-texto mk-boton mk-acceso"
          onClick={() => {
            if (pendientes > 0) {
              setAviso(true);
              pedirSincronizacion();
            } else {
              void cerrarSesion();
            }
          }}
        >
          <LogOut size={20} /> Salir
        </button>
      </main>
      <NavCompras />
    </div>
  );
}
