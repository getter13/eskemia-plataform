import { lazy, Suspense, type ReactNode } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { tienePermiso } from './lib/db';
import { ProveedorSesion, cerrarSesion, useSesion } from './lib/sesion';
import { Inicio } from './paginas/Inicio';
import { Login } from './paginas/Login';

// Cada módulo baja solo cuando se usa: el kiosco y el celular no cargan lo que no abren.
const Carga = lazy(() => import('./paginas/Carga').then((m) => ({ default: m.Carga })));
const Cierre = lazy(() => import('./paginas/Cierre').then((m) => ({ default: m.Cierre })));
const NuevaRecepcion = lazy(() => import('./paginas/NuevaRecepcion').then((m) => ({ default: m.NuevaRecepcion })));
const Resumen = lazy(() => import('./paginas/Resumen').then((m) => ({ default: m.Resumen })));
const Bandeja = lazy(() => import('./paginas/admin/Bandeja').then((m) => ({ default: m.Bandeja })));
const Detalle = lazy(() => import('./paginas/admin/Detalle').then((m) => ({ default: m.Detalle })));
const Importar = lazy(() => import('./paginas/admin/Importar').then((m) => ({ default: m.Importar })));
const Roles = lazy(() => import('./paginas/admin/Roles').then((m) => ({ default: m.Roles })));
const Reglas = lazy(() => import('./paginas/compras/Reglas').then((m) => ({ default: m.Reglas })));
const Marketplace = lazy(() => import('./paginas/compras/Marketplace').then((m) => ({ default: m.Marketplace })));
const Pedido = lazy(() => import('./paginas/compras/Pedido').then((m) => ({ default: m.Pedido })));
const Pedidos = lazy(() => import('./paginas/compras/Secciones').then((m) => ({ default: m.Pedidos })));
const Aprobaciones = lazy(() => import('./paginas/compras/Aprobaciones').then((m) => ({ default: m.Aprobaciones })));
const Tablero = lazy(() => import('./paginas/compras/Tablero').then((m) => ({ default: m.Tablero })));
const Orden = lazy(() => import('./paginas/compras/Orden').then((m) => ({ default: m.Orden })));
const PerfilCompras = lazy(() => import('./paginas/compras/Secciones').then((m) => ({ default: m.PerfilCompras })));

/** Alcanza con tener uno de los permisos. */
function Requiere({ permiso, children }: { permiso: string | string[]; children: ReactNode }) {
  const { perfil } = useSesion();
  const permisos = Array.isArray(permiso) ? permiso : [permiso];
  return permisos.some((p) => tienePermiso(perfil, p)) ? children : <Navigate to="/" replace />;
}

const OPERAR = 'recepcion.recepcion.operar';
const VALIDAR = 'recepcion.recepcion.validar';
const CATALOGO = 'compras.catalogo.ver';
const VER_ORDENES = 'compras.oc.ver_todas';

function Rutas() {
  const { cargando, session, perfil, errorPerfil } = useSesion();

  if (cargando) {
    return (
      <div className="vacio">
        <span className="marca">Eskemia</span>
      </div>
    );
  }
  if (!session) return <Login />;
  if (!perfil) {
    return (
      <div className="vacio">
        <h2>{errorPerfil ?? 'No se pudo cargar el perfil.'}</h2>
        <button className="btn" onClick={() => void cerrarSesion()}>
          Salir
        </button>
      </div>
    );
  }

  return (
    <Suspense fallback={<div className="vacio"><span className="marca">Eskemia</span></div>}>
    <Routes>
      <Route path="/" element={<Inicio />} />
      <Route path="/recepcion/nueva" element={<Requiere permiso={OPERAR}><NuevaRecepcion /></Requiere>} />
      <Route path="/recepcion/:id/carga" element={<Requiere permiso={OPERAR}><Carga /></Requiere>} />
      <Route path="/recepcion/:id/resumen" element={<Requiere permiso={OPERAR}><Resumen /></Requiere>} />
      <Route path="/recepcion/:id/cierre" element={<Requiere permiso={OPERAR}><Cierre /></Requiere>} />
      <Route path="/admin" element={<Requiere permiso={VALIDAR}><Bandeja /></Requiere>} />
      <Route path="/admin/recepcion/:id" element={<Requiere permiso={VALIDAR}><Detalle /></Requiere>} />
      <Route path="/compras" element={<Requiere permiso={CATALOGO}><Marketplace /></Requiere>} />
      <Route path="/compras/pedido" element={<Requiere permiso={CATALOGO}><Pedido /></Requiere>} />
      <Route path="/compras/pedidos" element={<Requiere permiso={CATALOGO}><Pedidos /></Requiere>} />
      <Route path="/compras/aprobaciones" element={<Requiere permiso="compras.oc.aprobar"><Aprobaciones /></Requiere>} />
      <Route path="/compras/oc" element={<Requiere permiso={VER_ORDENES}><Tablero /></Requiere>} />
      <Route
        path="/compras/oc/:id"
        element={<Requiere permiso={[CATALOGO, VER_ORDENES, 'compras.oc.aprobar']}><Orden /></Requiere>}
      />
      <Route path="/compras/perfil" element={<Requiere permiso={CATALOGO}><PerfilCompras /></Requiere>} />
      <Route
        path="/compras/reglas"
        element={<Requiere permiso="compras.aprobacion.configurar"><Reglas /></Requiere>}
      />
      <Route
        path="/admin/importar"
        element={<Requiere permiso="compras.catalogo.gestionar"><Importar /></Requiere>}
      />
      <Route
        path="/admin/roles"
        element={<Requiere permiso="nucleo.usuarios.gestionar"><Roles /></Requiere>}
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    </Suspense>
  );
}

export function App() {
  return (
    <ProveedorSesion>
      <Rutas />
    </ProveedorSesion>
  );
}
