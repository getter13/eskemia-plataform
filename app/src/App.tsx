import type { ReactNode } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { tienePermiso } from './lib/db';
import { ProveedorSesion, cerrarSesion, useSesion } from './lib/sesion';
import { Bandeja } from './paginas/admin/Bandeja';
import { Detalle } from './paginas/admin/Detalle';
import { Importar } from './paginas/admin/Importar';
import { Roles } from './paginas/admin/Roles';
import { Carga } from './paginas/Carga';
import { Cierre } from './paginas/Cierre';
import { Inicio } from './paginas/Inicio';
import { Login } from './paginas/Login';
import { NuevaRecepcion } from './paginas/NuevaRecepcion';
import { Resumen } from './paginas/Resumen';

function Requiere({ permiso, children }: { permiso: string; children: ReactNode }) {
  const { perfil } = useSesion();
  return tienePermiso(perfil, permiso) ? children : <Navigate to="/" replace />;
}

const OPERAR = 'recepcion.recepcion.operar';
const VALIDAR = 'recepcion.recepcion.validar';

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
    <Routes>
      <Route path="/" element={<Inicio />} />
      <Route path="/recepcion/nueva" element={<Requiere permiso={OPERAR}><NuevaRecepcion /></Requiere>} />
      <Route path="/recepcion/:id/carga" element={<Requiere permiso={OPERAR}><Carga /></Requiere>} />
      <Route path="/recepcion/:id/resumen" element={<Requiere permiso={OPERAR}><Resumen /></Requiere>} />
      <Route path="/recepcion/:id/cierre" element={<Requiere permiso={OPERAR}><Cierre /></Requiere>} />
      <Route path="/admin" element={<Requiere permiso={VALIDAR}><Bandeja /></Requiere>} />
      <Route path="/admin/recepcion/:id" element={<Requiere permiso={VALIDAR}><Detalle /></Requiere>} />
      <Route
        path="/admin/importar"
        element={<Requiere permiso="compras.catalogo.gestionar"><Importar /></Requiere>}
      />
      <Route
        path="/admin/roles"
        element={<Requiere permiso="admin.usuarios.gestionar"><Roles /></Requiere>}
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export function App() {
  return (
    <ProveedorSesion>
      <Rutas />
    </ProveedorSesion>
  );
}
