import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, Plus, X } from 'lucide-react';
import { Encabezado } from '../../componentes/Encabezado';
import { Modal } from '../../componentes/Modal';
import {
  asignarRol,
  crearRol,
  fijarPermisoRol,
  quitarRol,
  traerDatosRoles,
  type DatosRoles,
  type Rol,
  type Usuario,
} from '../../lib/roles';

function TarjetaUsuario({
  usuario,
  datos,
  ejecutar,
}: {
  usuario: Usuario;
  datos: DatosRoles;
  ejecutar: (accion: () => Promise<void>) => Promise<void>;
}) {
  const [rolId, setRolId] = useState('');
  const [sedeId, setSedeId] = useState('');
  const asignaciones = datos.asignaciones.filter((a) => a.user_id === usuario.user_id);

  return (
    <div className="tarjeta grupo" data-testid="usuario">
      <strong>
        {usuario.nombre}
        {!usuario.activo && ' · Inactivo'}
      </strong>
      {asignaciones.length === 0 && <p className="muted">Sin roles: no puede operar.</p>}
      {asignaciones.map((a) => (
        <div className="fila" key={a.id}>
          <span className="espacio-flex">
            {datos.roles.find((r) => r.id === a.rol_id)?.nombre ?? 'Rol inactivo'} ·{' '}
            {datos.sedes.find((s) => s.id === a.sede_id)?.nombre ?? 'Todas las sedes'}
          </span>
          <button className="btn btn-texto" onClick={() => void ejecutar(() => quitarRol(a.id))}>
            <X size={20} /> Quitar rol
          </button>
        </div>
      ))}
      <div className="fila">
        <label className="grupo espacio-flex">
          <span className="label">Rol</span>
          <select className="campo campo-texto" value={rolId} onChange={(e) => setRolId(e.target.value)}>
            <option value="">Elegí un rol</option>
            {datos.roles.map((r) => (
              <option key={r.id} value={r.id}>
                {r.nombre}
              </option>
            ))}
          </select>
        </label>
        <label className="grupo espacio-flex">
          <span className="label">Sede</span>
          <select className="campo campo-texto" value={sedeId} onChange={(e) => setSedeId(e.target.value)}>
            <option value="">Todas las sedes</option>
            {datos.sedes.map((s) => (
              <option key={s.id} value={s.id}>
                {s.nombre}
              </option>
            ))}
          </select>
        </label>
        <button
          className="btn"
          disabled={!rolId}
          onClick={() =>
            void ejecutar(async () => {
              await asignarRol(usuario.user_id, rolId, sedeId || null);
              setRolId('');
            })
          }
        >
          <Plus size={20} /> Asignar rol
        </button>
      </div>
    </div>
  );
}

function ModalPermisos({
  rol,
  datos,
  ejecutar,
  alCerrar,
}: {
  rol: Rol;
  datos: DatosRoles;
  ejecutar: (accion: () => Promise<void>) => Promise<void>;
  alCerrar: () => void;
}) {
  return (
    <Modal titulo={`Permisos de ${rol.nombre}`} alCerrar={alCerrar}>
      <div className="grupo">
        {datos.permisos.map((p) => (
          <label className="fila-permiso" key={p.codigo}>
            <input
              type="checkbox"
              checked={rol.permisos.includes(p.codigo)}
              onChange={(e) => {
                const activo = e.target.checked;
                void ejecutar(() => fijarPermisoRol(rol.id, p.codigo, activo));
              }}
            />
            <span className="grupo">
              <span>{p.descripcion}</span>
              <span className="mono muted">{p.codigo}</span>
            </span>
          </label>
        ))}
      </div>
    </Modal>
  );
}

export function Roles() {
  const navegar = useNavigate();
  const [datos, setDatos] = useState<DatosRoles | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [rolAbiertoId, setRolAbiertoId] = useState<string | null>(null);
  const [nombreRol, setNombreRol] = useState('');
  const [nivelRol, setNivelRol] = useState('0');

  const cargar = useCallback(async () => {
    try {
      setDatos(await traerDatosRoles());
      setError(null);
    } catch {
      setError('No se pudieron cargar los roles. Revisá la conexión.');
    }
  }, []);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const ejecutar = useCallback(
    async (accion: () => Promise<void>) => {
      try {
        await accion();
        await cargar();
      } catch (e) {
        setError(e instanceof Error ? e.message : 'No se pudo guardar el cambio.');
      }
    },
    [cargar],
  );

  const rolAbierto = datos?.roles.find((r) => r.id === rolAbiertoId);

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Usuarios y roles</h2>
      </Encabezado>
      <main className="contenido contenido-admin">
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        {datos && (
          <>
            <section className="grupo">
              <h2>Usuarios</h2>
              {datos.usuarios.map((u) => (
                <TarjetaUsuario key={u.user_id} usuario={u} datos={datos} ejecutar={ejecutar} />
              ))}
            </section>

            <section className="grupo">
              <h2>Roles</h2>
              {datos.roles.map((r) => (
                <button
                  className="tarjeta tarjeta-tactil"
                  data-testid="rol"
                  key={r.id}
                  onClick={() => setRolAbiertoId(r.id)}
                >
                  <span className="espacio-flex">{r.nombre}</span>
                  <span className="mono muted">
                    Nivel {r.nivel_aprobacion} · {r.permisos.length} permisos
                  </span>
                </button>
              ))}
              <div className="fila">
                <label className="grupo espacio-flex">
                  <span className="label">Nombre del rol</span>
                  <input
                    className="campo campo-texto"
                    value={nombreRol}
                    onChange={(e) => setNombreRol(e.target.value)}
                  />
                </label>
                <label className="grupo">
                  <span className="label">Nivel de aprobación</span>
                  <input
                    className="campo campo-texto"
                    type="number"
                    min={0}
                    value={nivelRol}
                    onChange={(e) => setNivelRol(e.target.value)}
                  />
                </label>
                <button
                  className="btn"
                  disabled={!nombreRol.trim()}
                  onClick={() =>
                    void ejecutar(async () => {
                      await crearRol(nombreRol, Number(nivelRol) || 0);
                      setNombreRol('');
                      setNivelRol('0');
                    })
                  }
                >
                  <Plus size={20} /> Crear rol
                </button>
              </div>
            </section>
          </>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/admin')}>
          <ChevronLeft size={24} /> Volver a la bandeja
        </button>
      </footer>
      {datos && rolAbierto && (
        <ModalPermisos
          rol={rolAbierto}
          datos={datos}
          ejecutar={ejecutar}
          alCerrar={() => setRolAbiertoId(null)}
        />
      )}
    </div>
  );
}
