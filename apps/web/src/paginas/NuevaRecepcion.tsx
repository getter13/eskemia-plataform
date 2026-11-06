import { useEffect, useMemo, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, Camera, Plus, Search } from 'lucide-react';
import { BotonFoto } from '../componentes/BotonFoto';
import { Encabezado } from '../componentes/Encabezado';
import { Modal } from '../componentes/Modal';
import { db, type PendienteRecepcion, type Proveedor } from '../lib/db';
import { formatoCuit } from '../lib/formato';
import { abrirRecepcion, altaProveedor } from '../lib/operaciones';
import { useSesion } from '../lib/sesion';

function ModalProveedor({
  alCrear,
  alCerrar,
}: {
  alCrear: (p: Proveedor) => void;
  alCerrar: () => void;
}) {
  const [nombre, setNombre] = useState('');
  const [cuit, setCuit] = useState('');
  const digitos = cuit.replace(/\D/g, '');
  const valido = nombre.trim() !== '' && digitos.length === 11;

  return (
    <Modal titulo="Nuevo proveedor" alCerrar={alCerrar}>
      <label className="grupo">
        <span className="label">Nombre</span>
        <input className="campo" value={nombre} onChange={(e) => setNombre(e.target.value)} />
      </label>
      <label className="grupo">
        <span className="label">CUIT (11 dígitos)</span>
        <input
          className="campo"
          inputMode="numeric"
          value={cuit}
          onChange={(e) => setCuit(e.target.value)}
        />
      </label>
      <button
        className="btn btn-primario"
        disabled={!valido}
        onClick={async () => {
          const id = await altaProveedor(nombre.trim(), digitos);
          const proveedor = await db.proveedores.get(id);
          if (proveedor) alCrear(proveedor);
        }}
      >
        Guardar proveedor
      </button>
    </Modal>
  );
}

export function NuevaRecepcion() {
  const navegar = useNavigate();
  const { perfil } = useSesion();
  const [busqueda, setBusqueda] = useState('');
  const [proveedor, setProveedor] = useState<Proveedor | null>(null);
  const [nroRemito, setNroRemito] = useState('');
  const [foto, setFoto] = useState<Blob | null>(null);
  const [modal, setModal] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [parametros] = useSearchParams();
  const [oc, setOc] = useState<PendienteRecepcion | null>(null);
  const ordenes = useLiveQuery(() => db.pendientes.toArray(), []) ?? [];
  const ocPedida = parametros.get('oc');

  // Elegida desde Pendientes: la orden ya dice el proveedor, y no se puede cambiar.
  const [buscandoOc, setBuscandoOc] = useState(ocPedida !== null);
  const [ocFija, setOcFija] = useState(false);
  useEffect(() => {
    if (!ocPedida) return;
    void db.pendientes.get(ocPedida).then(async (o) => {
      if (o?.se_puede_recibir) {
        setOc(o);
        setOcFija(true);
        setProveedor((await db.proveedores.get(o.proveedor_id)) ?? { id: o.proveedor_id, nombre: o.proveedor, cuit: '' });
      }
      setBuscandoOc(false);
    });
  }, [ocPedida]);

  const ordenesDelProveedor = ordenes.filter((o) => o.se_puede_recibir && o.proveedor_id === proveedor?.id);
  // Con la orden fija, el proveedor ya está resuelto y arranca por el remito.
  const pasoRemito = ocFija ? 1 : 2;

  const proveedores = useLiveQuery(() => db.proveedores.toArray(), []) ?? [];
  const filtrados = useMemo(() => {
    const q = busqueda.trim().toLowerCase();
    const digitos = q.replace(/\D/g, '');
    return proveedores
      .filter(
        (p) =>
          p.nombre.toLowerCase().includes(q) || (digitos !== '' && p.cuit.includes(digitos)),
      )
      .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'));
  }, [proveedores, busqueda]);

  const vistaPrevia = useMemo(() => (foto ? URL.createObjectURL(foto) : null), [foto]);
  useEffect(
    () => () => {
      if (vistaPrevia) URL.revokeObjectURL(vistaPrevia);
    },
    [vistaPrevia],
  );

  const listo = proveedor !== null && nroRemito.trim() !== '' && foto !== null;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Nueva recepción</h2>
      </Encabezado>
      <main className="contenido estrecho">
        {ocFija && oc && (
          <section className="tarjeta grupo" data-testid="oc-elegida">
            <strong>{oc.proveedor}</strong>
            <span className="mono muted">{oc.numero}</span>
          </section>
        )}

        {!ocFija && !buscandoOc && (
        <>
        <section className="grupo" data-testid="elegir-proveedor">
          <h2>1. Proveedor</h2>
          <div className="fila">
            <Search size={24} />
            <input
              className="campo"
              style={{ flex: 1 }}
              placeholder="Buscar por nombre o CUIT"
              aria-label="Buscar proveedor"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            <button className="btn" onClick={() => setModal(true)}>
              <Plus size={24} /> Nuevo
            </button>
          </div>
          <div className="grilla">
            {filtrados.map((p) => (
              <button
                className="tarjeta tarjeta-tactil"
                aria-pressed={proveedor?.id === p.id}
                key={p.id}
                onClick={() => {
                  setProveedor(p);
                  setOc(null);
                }}
              >
                <span className="grupo">
                  <strong>{p.nombre}</strong>
                  <span className="mono muted">{formatoCuit(p.cuit)}</span>
                </span>
              </button>
            ))}
          </div>
          {filtrados.length === 0 && <p className="muted">No hay proveedores con esa búsqueda.</p>}
        </section>

        {ordenesDelProveedor.length > 0 && (
          <section className="grupo" data-testid="elegir-oc">
            <h2>Orden de compra</h2>
            <p className="muted">Elegí la orden para recibir sobre sus cantidades y detectar las diferencias.</p>
            <div className="grilla">
              {ordenesDelProveedor.map((o) => (
                <button
                  className="tarjeta tarjeta-tactil"
                  aria-pressed={oc?.id === o.id}
                  data-testid="opcion-oc"
                  key={o.id}
                  onClick={() => setOc(o)}
                >
                  <strong className="mono">{o.numero}</strong>
                </button>
              ))}
              <button
                className="tarjeta tarjeta-tactil"
                aria-pressed={oc === null}
                onClick={() => setOc(null)}
              >
                <strong>Sin orden de compra</strong>
              </button>
            </div>
          </section>
        )}
        </>
        )}

        <section className="grupo">
          <h2>{pasoRemito}. Número de remito o factura</h2>
          <input
            className="campo"
            aria-label="Número de remito o factura"
            value={nroRemito}
            onChange={(e) => setNroRemito(e.target.value)}
          />
        </section>

        <section className="grupo">
          <h2>{pasoRemito + 1}. Foto del remito o factura</h2>
          <p className="muted">Es obligatoria: queda como respaldo de la recepción.</p>
          {vistaPrevia && <img className="vista-foto" src={vistaPrevia} alt="Foto del documento" />}
          <div>
            <BotonFoto alCapturar={setFoto}>
              <Camera size={24} /> {foto ? 'Sacar otra foto' : 'Sacar foto'}
            </BotonFoto>
          </div>
        </section>
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/')}>
          <ArrowLeft size={24} /> Cancelar
        </button>
        <span className="espacio" />
        <button
          className="btn btn-primario"
          disabled={!listo || guardando}
          onClick={async () => {
            if (!perfil || !proveedor || !foto) return;
            setGuardando(true);
            const id = await abrirRecepcion(perfil, {
              proveedor_id: proveedor.id,
              proveedor_nombre: proveedor.nombre,
              nro_remito: nroRemito.trim(),
              foto,
              oc,
            });
            navegar(`/recepcion/${id}/carga`, { replace: true });
          }}
        >
          Empezar a cargar
        </button>
      </footer>
      {modal && (
        <ModalProveedor
          alCerrar={() => setModal(false)}
          alCrear={(p) => {
            setProveedor(p);
            setBusqueda('');
            setModal(false);
          }}
        />
      )}
    </div>
  );
}
