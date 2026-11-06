import { useCallback, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, ChevronLeft, Plus, Save, X } from 'lucide-react';
import { Encabezado } from '../../componentes/Encabezado';
import { formatoNumero } from '../../lib/formato';
import { aNumero } from '../../lib/importacion';
import {
  fijarAutoaprobacion,
  fijarLimiteRol,
  guardarRegla,
  quitarRegla,
  traerDatosReglas,
  type AlcanceRegla,
  type DatosReglas,
  type ModoRegla,
  type OpcionCatalogo,
  type ReglaAprobacion,
  type RolLimite,
} from '../../lib/reglas';

const ETIQUETA_ALCANCE: Record<AlcanceRegla, string> = {
  EMPRESA: 'Toda la empresa',
  RUBRO: 'Rubro',
  CATEGORIA: 'Categoría',
  PRODUCTO: 'Producto',
};
const ORDEN_ALCANCE: AlcanceRegla[] = ['EMPRESA', 'RUBRO', 'CATEGORIA', 'PRODUCTO'];

function describirRegla(r: ReglaAprobacion) {
  if (r.modo === 'NUNCA') return 'No requiere aprobación';
  const nivel = `nivel ${r.nivel_requerido}`;
  if (r.modo === 'SIEMPRE') return `Requiere aprobación siempre, ${nivel}`;
  return `Requiere aprobación si supera $ ${formatoNumero(r.monto_umbral ?? 0)}, ${nivel}`;
}

function FilaLimite({
  rol,
  ejecutar,
}: {
  rol: RolLimite;
  ejecutar: (accion: () => Promise<void>) => Promise<void>;
}) {
  const inicial = rol.limite_monto_sin_aprobacion === null ? '' : formatoNumero(rol.limite_monto_sin_aprobacion);
  const [valor, setValor] = useState(inicial);
  const invalido = valor.trim() !== '' && !(aNumero(valor) >= 0);

  return (
    <div className="fila">
      <label className="grupo espacio-flex">
        <span className="label">{rol.nombre}</span>
        <input
          className="campo campo-texto"
          inputMode="decimal"
          placeholder="Sin límite"
          aria-invalid={invalido}
          value={valor}
          onChange={(e) => setValor(e.target.value)}
        />
      </label>
      <button
        className="btn"
        disabled={invalido || valor === inicial}
        onClick={() => void ejecutar(() => fijarLimiteRol(rol.id, valor.trim() === '' ? null : aNumero(valor)))}
      >
        <Save size={20} /> Guardar límite
      </button>
    </div>
  );
}

export function Reglas() {
  const navegar = useNavigate();
  const [datos, setDatos] = useState<DatosReglas | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [alcance, setAlcance] = useState<AlcanceRegla>('RUBRO');
  const [destino, setDestino] = useState('');
  const [modo, setModo] = useState<ModoRegla>('SIEMPRE');
  const [monto, setMonto] = useState('');
  const [nivel, setNivel] = useState('1');

  const cargar = useCallback(async () => {
    try {
      setDatos(await traerDatosReglas());
      setError(null);
    } catch {
      setError('No se pudo cargar la configuración. Revisá la conexión.');
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

  const opciones: OpcionCatalogo[] =
    alcance === 'RUBRO'
      ? (datos?.rubros ?? [])
      : alcance === 'CATEGORIA'
        ? (datos?.categorias ?? [])
        : alcance === 'PRODUCTO'
          ? (datos?.productos ?? [])
          : [];

  const nombreDestino = (r: ReglaAprobacion) => {
    const lista = r.alcance === 'RUBRO' ? datos?.rubros : r.alcance === 'CATEGORIA' ? datos?.categorias : datos?.productos;
    return lista?.find((o) => o.id === r.alcance_id)?.nombre ?? 'Inactivo';
  };

  const reglas = [...(datos?.reglas ?? [])].sort(
    (a, b) => ORDEN_ALCANCE.indexOf(a.alcance) - ORDEN_ALCANCE.indexOf(b.alcance),
  );
  const montoValido = modo !== 'POR_MONTO' || aNumero(monto) >= 0;
  const puedeGuardar = (alcance === 'EMPRESA' || !!destino) && montoValido;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Reglas de aprobación</h2>
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
              <h2>Reglas</h2>
              <p className="muted">
                Por cada producto manda la regla más específica: producto, categoría, rubro y por último empresa. Sin
                reglas, las órdenes no requieren aprobación.
              </p>
              {reglas.length === 0 && <p className="muted">Todavía no hay reglas activas.</p>}
              {reglas.map((r) => (
                <div className="tarjeta fila" data-testid="regla" key={r.id}>
                  <span className="grupo espacio-flex">
                    <strong>
                      {r.alcance === 'EMPRESA'
                        ? ETIQUETA_ALCANCE.EMPRESA
                        : `${ETIQUETA_ALCANCE[r.alcance]}: ${nombreDestino(r)}`}
                    </strong>
                    <span className="muted">{describirRegla(r)}</span>
                  </span>
                  <button className="btn btn-texto" onClick={() => void ejecutar(() => quitarRegla(r))}>
                    <X size={20} /> Quitar regla
                  </button>
                </div>
              ))}
            </section>

            <section className="tarjeta grupo">
              <h2>Agregar o cambiar una regla</h2>
              <div className="fila">
                <label className="grupo espacio-flex">
                  <span className="label">Se aplica a</span>
                  <select
                    className="campo campo-texto"
                    value={alcance}
                    onChange={(e) => {
                      setAlcance(e.target.value as AlcanceRegla);
                      setDestino('');
                    }}
                  >
                    {ORDEN_ALCANCE.map((a) => (
                      <option key={a} value={a}>
                        {ETIQUETA_ALCANCE[a]}
                      </option>
                    ))}
                  </select>
                </label>
                {alcance !== 'EMPRESA' && (
                  <label className="grupo espacio-flex">
                    <span className="label">{ETIQUETA_ALCANCE[alcance]}</span>
                    <select className="campo campo-texto" value={destino} onChange={(e) => setDestino(e.target.value)}>
                      <option value="">Elegí una opción</option>
                      {opciones.map((o) => (
                        <option key={o.id} value={o.id}>
                          {o.nombre}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
              </div>
              <div className="fila">
                <label className="grupo espacio-flex">
                  <span className="label">Aprobación</span>
                  <select
                    className="campo campo-texto"
                    value={modo}
                    onChange={(e) => setModo(e.target.value as ModoRegla)}
                  >
                    <option value="SIEMPRE">Siempre</option>
                    <option value="POR_MONTO">Por monto</option>
                    <option value="NUNCA">Nunca</option>
                  </select>
                </label>
                {modo === 'POR_MONTO' && (
                  <label className="grupo espacio-flex">
                    <span className="label">Si el subtotal supera ($)</span>
                    <input
                      className="campo campo-texto"
                      inputMode="decimal"
                      value={monto}
                      onChange={(e) => setMonto(e.target.value)}
                    />
                  </label>
                )}
                {modo !== 'NUNCA' && (
                  <label className="grupo espacio-flex">
                    <span className="label">Nivel del aprobador</span>
                    <input
                      className="campo campo-texto"
                      type="number"
                      min={1}
                      value={nivel}
                      onChange={(e) => setNivel(e.target.value)}
                    />
                  </label>
                )}
              </div>
              <div>
                <button
                  className="btn btn-primario"
                  disabled={!puedeGuardar}
                  onClick={() =>
                    void ejecutar(async () => {
                      await guardarRegla(
                        alcance,
                        alcance === 'EMPRESA' ? null : destino,
                        modo,
                        modo === 'POR_MONTO' ? aNumero(monto) : null,
                        Number(nivel) || 1,
                      );
                      setDestino('');
                      setMonto('');
                    })
                  }
                >
                  <Plus size={20} /> Guardar regla
                </button>
              </div>
            </section>

            <section className="tarjeta grupo">
              <h2>Autoaprobación</h2>
              <label className="fila-permiso">
                <input
                  type="checkbox"
                  checked={datos.permitirAutoaprobacion}
                  onChange={(e) => {
                    const permitir = e.target.checked;
                    void ejecutar(() => fijarAutoaprobacion(permitir));
                  }}
                />
                <span>Quien tiene nivel suficiente puede aprobar sus propias órdenes</span>
              </label>
            </section>

            <section className="tarjeta grupo">
              <h2>Límite por rol</h2>
              <p className="muted">
                Monto máximo de una orden que el rol puede emitir sin aprobación. Vacío: el rol no tiene límite propio.
              </p>
              {datos.roles.map((r) => (
                <FilaLimite key={`${r.id}-${r.limite_monto_sin_aprobacion}`} rol={r} ejecutar={ejecutar} />
              ))}
            </section>
          </>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/')}>
          <ChevronLeft size={24} /> Volver al inicio
        </button>
      </footer>
    </div>
  );
}
