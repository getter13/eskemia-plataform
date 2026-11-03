import { Navigate, Route, Routes } from 'react-router-dom';
import { ProveedorSesion, cerrarSesion, useSesion } from './lib/sesion';
import { Carga } from './paginas/Carga';
import { Cierre } from './paginas/Cierre';
import { Inicio } from './paginas/Inicio';
import { Login } from './paginas/Login';
import { NuevaRecepcion } from './paginas/NuevaRecepcion';
import { Resumen } from './paginas/Resumen';

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
      <Route path="/recepcion/nueva" element={<NuevaRecepcion />} />
      <Route path="/recepcion/:id/carga" element={<Carga />} />
      <Route path="/recepcion/:id/resumen" element={<Resumen />} />
      <Route path="/recepcion/:id/cierre" element={<Cierre />} />
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
