import { Link } from 'react-router-dom';
import { ClipboardList, FileUp, LogOut, ScanLine, ShieldCheck, Users } from 'lucide-react';
import { NavCompras } from '../../componentes/compras';
import { tienePermiso } from '../../lib/db';
import { cerrarSesion, useSesion } from '../../lib/sesion';

export function Pedidos() {
  return (
    <div className="pantalla mk-pantalla">
      <header className="mk-cabecera mk-cabecera-titulo">
        <h1 className="mk-titulo">Pedidos</h1>
      </header>
      <main className="mk-lista">
        <div className="mk-vacio">
          <p>Acá vas a ver el seguimiento de cada orden de compra.</p>
          <Link className="btn" to="/compras">
            Ir al catálogo
          </Link>
        </div>
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
        <button className="btn btn-texto mk-boton mk-acceso" onClick={() => void cerrarSesion()}>
          <LogOut size={20} /> Salir
        </button>
      </main>
      <NavCompras />
    </div>
  );
}
