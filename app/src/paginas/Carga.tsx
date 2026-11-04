import { useCallback, useEffect, useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Navigate, useNavigate, useParams } from 'react-router-dom';
import {
  AlertTriangle,
  ArrowLeft,
  Camera,
  CheckCircle2,
  Hand,
  Minus,
  Plus,
  ScanLine,
  Video,
} from 'lucide-react';
import { BotonFoto } from '../componentes/BotonFoto';
import { CamaraEscaner } from '../componentes/CamaraEscaner';
import { Encabezado } from '../componentes/Encabezado';
import { Modal } from '../componentes/Modal';
import { SelectorProducto } from '../componentes/SelectorProducto';
import { TecladoCantidad } from '../componentes/Teclado';
import { interpretarCodigo } from '../lib/codigos';
import { db, type ItemLocal, type Producto, type TipoMedida } from '../lib/db';
import { formatoCantidad, formatoFecha, redondear } from '../lib/formato';
import {
  agregarAdjunto,
  ajustarItem,
  altaProducto,
  registrarLectura,
} from '../lib/operaciones';
import { sonidoError, sonidoOk } from '../lib/sonido';

const MOTIVOS_MANUAL = ['Sin código de barras', 'Código dañado', 'El lector no lo lee', 'Otro'];

interface Origen {
  tipo: 'ESCANEO' | 'MANUAL';
  crudo: string | null;
  motivo: string | null;
  foto: Blob | null;
  // Presentación leída por código de barras: cuántas unidades suma cada lectura.
  factor?: number;
  presentacion?: string;
}

type Panel =
  | { tipo: 'ninguno' }
  | { tipo: 'manual' }
  | { tipo: 'camara' }
  | { tipo: 'alta'; crudo: string; gtin: string }
  | { tipo: 'motivo'; producto: Producto }
  | { tipo: 'fotoManual'; producto: Producto; motivo: string }
  | { tipo: 'lote'; producto: Producto; origen: Origen; lote: string; vencimiento: string }
  | {
      tipo: 'cantidad';
      producto: Producto;
      origen: Origen;
      lote: string | null;
      vencimiento: string | null;
    }
  | { tipo: 'total'; item: ItemLocal };

type Aviso = { tipo: 'ok' | 'error'; texto: string } | null;

function Marcador({ titulo, valor }: { titulo: string; valor: string }) {
  return (
    <span className="grupo">
      <span className="label">{titulo}</span>
      <span className="mono">{valor}</span>
    </span>
  );
}

function ModalAltaProducto({
  gtin,
  alCrear,
  alCerrar,
}: {
  gtin: string;
  alCrear: (p: Producto) => void;
  alCerrar: () => void;
}) {
  const [nombre, setNombre] = useState('');
  const [medida, setMedida] = useState<TipoMedida>('UNIDAD');
  const [lote, setLote] = useState(false);
  const [venc, setVenc] = useState(false);

  return (
    <Modal titulo="Producto no cargado" alCerrar={alCerrar}>
      <p>
        Código <span className="mono">{gtin}</span>. Se da de alta como pendiente de validación.
      </p>
      <label className="grupo">
        <span className="label">Nombre, sin tamaño ni envase</span>
        <input
          className="campo"
          autoFocus
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
        />
      </label>
      <div className="grupo">
        <span className="label">Se recibe en</span>
        <div className="fila">
          <button className="btn btn-seleccion" aria-pressed={medida === 'UNIDAD'} onClick={() => setMedida('UNIDAD')}>
            Unidades
          </button>
          <button className="btn btn-seleccion" aria-pressed={medida === 'PESO'} onClick={() => setMedida('PESO')}>
            Kg
          </button>
        </div>
      </div>
      <div className="fila">
        <button className="btn btn-seleccion" aria-pressed={lote} onClick={() => setLote(!lote)}>
          Requiere lote
        </button>
        <button className="btn btn-seleccion" aria-pressed={venc} onClick={() => setVenc(!venc)}>
          Requiere vencimiento
        </button>
      </div>
      <button
        className="btn btn-primario"
        disabled={nombre.trim() === ''}
        onClick={async () => {
          alCrear(
            await altaProducto({
              nombre: nombre.trim(),
              gtin,
              tipo_medida: medida,
              requiere_lote: lote,
              requiere_vencimiento: venc,
            }),
          );
        }}
      >
        Guardar producto
      </button>
    </Modal>
  );
}

function ModalMotivo({
  producto,
  alElegir,
  alCerrar,
}: {
  producto: Producto;
  alElegir: (motivo: string) => void;
  alCerrar: () => void;
}) {
  const [otro, setOtro] = useState<string | null>(null);
  return (
    <Modal titulo={`¿Por qué se carga a mano ${producto.nombre}?`} alCerrar={alCerrar}>
      {otro === null ? (
        <div className="grilla">
          {MOTIVOS_MANUAL.map((m) => (
            <button
              className="tarjeta tarjeta-tactil"
              key={m}
              onClick={() => (m === 'Otro' ? setOtro('') : alElegir(m))}
            >
              <strong>{m}</strong>
            </button>
          ))}
        </div>
      ) : (
        <>
          <label className="grupo">
            <span className="label">Motivo</span>
            <input className="campo" autoFocus value={otro} onChange={(e) => setOtro(e.target.value)} />
          </label>
          <button className="btn btn-primario" disabled={otro.trim() === ''} onClick={() => alElegir(otro.trim())}>
            Continuar
          </button>
        </>
      )}
    </Modal>
  );
}

function ModalLote({
  panel,
  alConfirmar,
  alCerrar,
}: {
  panel: Extract<Panel, { tipo: 'lote' }>;
  alConfirmar: (lote: string | null, vencimiento: string | null) => void;
  alCerrar: () => void;
}) {
  const { producto } = panel;
  const [lote, setLote] = useState(panel.lote);
  const [vencimiento, setVencimiento] = useState(panel.vencimiento);
  const valido =
    (!producto.requiere_lote || lote.trim() !== '') &&
    (!producto.requiere_vencimiento || vencimiento !== '');

  return (
    <Modal titulo={producto.nombre} alCerrar={alCerrar}>
      {producto.requiere_lote && (
        <label className="grupo">
          <span className="label">Lote</span>
          <input className="campo" autoFocus value={lote} onChange={(e) => setLote(e.target.value)} />
        </label>
      )}
      {producto.requiere_vencimiento && (
        <label className="grupo">
          <span className="label">Vencimiento</span>
          <input
            className="campo"
            type="date"
            value={vencimiento}
            onChange={(e) => setVencimiento(e.target.value)}
          />
        </label>
      )}
      <button
        className="btn btn-primario"
        disabled={!valido}
        onClick={() =>
          alConfirmar(
            producto.requiere_lote ? lote.trim() : null,
            producto.requiere_vencimiento ? vencimiento : null,
          )
        }
      >
        Continuar
      </button>
    </Modal>
  );
}

export function Carga() {
  const { id = '' } = useParams();
  const navegar = useNavigate();
  const entrada = useRef<HTMLInputElement>(null);
  const [panel, setPanel] = useState<Panel>({ tipo: 'ninguno' });
  const [aviso, setAviso] = useState<Aviso>(null);
  const [activoKey, setActivoKey] = useState<string | null>(null);

  const recepcion = useLiveQuery(async () => (await db.recepciones.get(id)) ?? null, [id]);
  const items =
    useLiveQuery(
      () =>
        db.items
          .where('recepcion_id')
          .equals(id)
          .toArray()
          .then((l) => l.sort((a, b) => b.orden - a.orden)),
      [id],
    ) ?? [];
  const activo = items.find((i) => i.key === activoKey) ?? null;

  // Foco permanente, salvo cuando el operario escribe en un campo de un panel.
  useEffect(() => {
    const enfocar = () => {
      const actual = document.activeElement;
      const escribiendo =
        actual instanceof HTMLInputElement && actual !== entrada.current && actual.type !== 'file';
      if (!escribiendo) entrada.current?.focus({ preventScroll: true });
    };
    enfocar();
    const timer = setInterval(enfocar, 300);
    document.addEventListener('click', enfocar);
    // En captura: la primera tecla del lector ya entra al campo, y su Enter no activa un botón.
    window.addEventListener('keydown', enfocar, true);
    return () => {
      clearInterval(timer);
      document.removeEventListener('click', enfocar);
      window.removeEventListener('keydown', enfocar, true);
    };
  }, []);

  const montarEntrada = useCallback((el: HTMLInputElement | null) => {
    entrada.current = el;
    el?.focus({ preventScroll: true });
  }, []);

  useEffect(() => {
    if (!aviso) return;
    const timer = setTimeout(() => setAviso(null), 3000);
    return () => clearTimeout(timer);
  }, [aviso]);

  const avisarError = useCallback((texto: string) => {
    sonidoError();
    setAviso({ tipo: 'error', texto });
  }, []);

  const guardar = useCallback(
    async (
      producto: Producto,
      origen: Origen,
      cantidad: number,
      lote: string | null,
      vencimiento: string | null,
    ) => {
      const item = await registrarLectura({
        recepcion_id: id,
        producto,
        cantidad,
        tipo: origen.tipo,
        valor_crudo: origen.crudo,
        lote,
        vencimiento,
        motivo: origen.motivo,
      });
      if (!item) {
        avisarError('La cantidad no puede quedar negativa');
        return;
      }
      if (origen.foto) await agregarAdjunto(id, 'MANUAL', origen.foto, 'jpg', item.key);
      sonidoOk();
      setActivoKey(item.key);
      const conOrden = !!(await db.recepciones.get(id))?.oc_id;
      const pedido = await db.items
        .where('recepcion_id')
        .equals(id)
        .filter((i) => i.producto_id === producto.id && (i.cant_pedida ?? null) !== null)
        .count();
      const total = formatoCantidad(item.cant_recibida, producto.tipo_medida);
      setAviso(
        conOrden && pedido === 0
          ? { tipo: 'error', texto: `${producto.nombre}: no está en la orden de compra` }
          : {
              tipo: 'ok',
              texto: `${producto.nombre}${origen.presentacion ? ` (${origen.presentacion})` : ''}: ${total}`,
            },
      );
      setPanel({ tipo: 'ninguno' });
    },
    [id, avisarError],
  );

  /** Con lote y vencimiento resueltos, guarda o pide la cantidad según el formato. */
  const continuar = useCallback(
    async (producto: Producto, origen: Origen, lote: string | null, vencimiento: string | null) => {
      // Una presentación con factor ya dice la cantidad: una bolsa de 25 kg no se pesa.
      const factor = origen.factor ?? 1;
      if ((producto.tipo_medida === 'PESO' && factor === 1) || origen.tipo === 'MANUAL') {
        setPanel({ tipo: 'cantidad', producto, origen, lote, vencimiento });
        return;
      }
      await guardar(producto, origen, factor, lote, vencimiento);
    },
    [guardar],
  );

  const resolverProducto = useCallback(
    async (
      producto: Producto,
      origen: Origen,
      leido: { lote: string | null; vencimiento: string | null } = { lote: null, vencimiento: null },
    ) => {
      const pideDatos = producto.requiere_lote || producto.requiere_vencimiento;
      if (!pideDatos) {
        await continuar(producto, origen, null, null);
        return;
      }
      const lote = producto.requiere_lote ? leido.lote : null;
      const venc = producto.requiere_vencimiento ? leido.vencimiento : null;
      const completo =
        (!producto.requiere_lote || lote) && (!producto.requiere_vencimiento || venc);
      if (completo) {
        await continuar(producto, origen, lote, venc);
        return;
      }
      // Misma línea que se venía cargando: no vuelve a preguntar el lote.
      const actual = await db.items.get(activoKey ?? '');
      if (actual?.producto_id === producto.id && origen.tipo === 'ESCANEO') {
        await continuar(producto, origen, actual.lote, actual.vencimiento);
        return;
      }
      setPanel({
        tipo: 'lote',
        producto,
        origen,
        lote: lote ?? '',
        vencimiento: venc ?? '',
      });
    },
    [activoKey, continuar],
  );

  const procesarLectura = useCallback(
    async (crudo: string) => {
      const texto = crudo.trim();
      if (!texto) return;
      const codigo = interpretarCodigo(texto);
      // Códigos internos o GS1-128 no son GTIN: se buscan tal como se leyeron.
      const registrado = await db.codigos.get(codigo?.gtin14 ?? texto);
      if (!codigo && !registrado) {
        setPanel({ tipo: 'ninguno' });
        avisarError(`Código no válido: ${texto.slice(0, 24)}. Usá la carga manual.`);
        return;
      }
      const producto = registrado
        ? await db.productos.get(registrado.producto_id)
        : await db.productos.where('gtin14').equals(codigo!.gtin14).first();
      if (!producto) {
        sonidoError();
        setAviso({ tipo: 'error', texto: 'Producto no cargado' });
        if (codigo) setPanel({ tipo: 'alta', crudo: texto, gtin: codigo.gtin });
        return;
      }
      setPanel({ tipo: 'ninguno' });
      await resolverProducto(
        producto,
        {
          tipo: 'ESCANEO',
          crudo: texto,
          motivo: null,
          foto: null,
          factor: registrado?.factor,
          presentacion: registrado && registrado.factor !== 1 ? registrado.presentacion : undefined,
        },
        codigo ?? undefined,
      );
    },
    [avisarError, resolverProducto],
  );

  const alLeerCamara = useCallback(
    (codigo: string) => void procesarLectura(codigo),
    [procesarLectura],
  );

  async function ajustar(delta: number) {
    if (!activo) return;
    const nuevo = await ajustarItem(activo, delta);
    if (!nuevo) avisarError('La cantidad no puede quedar negativa');
    else sonidoOk();
  }

  if (recepcion === undefined) return null;
  if (!recepcion || (recepcion.estado !== 'ABIERTA' && recepcion.estado !== 'EN_CONTROL')) {
    return <Navigate to="/" replace />;
  }

  const paso = activo?.tipo_medida === 'PESO' ? 0.5 : 1;

  return (
    <div className="pantalla">
      <Encabezado>
        <span className="muted">
          {recepcion.proveedor_nombre} · <span className="mono">{recepcion.nro_remito}</span>
        </span>
      </Encabezado>

      <input
        ref={montarEntrada}
        className="entrada-escaner"
        data-testid="entrada-escaner"
        aria-label="Lectura del escáner"
        // Evita que Android abra el teclado en pantalla.
        inputMode="none"
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            const valor = e.currentTarget.value;
            e.currentTarget.value = '';
            void procesarLectura(valor);
          }
        }}
      />

      <div className="carga">
        <section className="carga-principal">
          <div className={`estado-lector ${aviso?.tipo ?? ''}`} role="status" data-testid="estado-lector">
            {aviso?.tipo === 'ok' && <CheckCircle2 size={32} />}
            {aviso?.tipo === 'error' && <AlertTriangle size={32} />}
            {!aviso && <ScanLine size={32} />}
            {aviso?.texto ?? 'Listo para escanear'}
          </div>

          {activo ? (
            <div className="tarjeta item-activo" data-testid="item-activo">
              <h1>{activo.producto_nombre}</h1>
              {(activo.cant_pedida ?? null) !== null && (
                <Marcador titulo="Pedido" valor={formatoCantidad(activo.cant_pedida!, activo.tipo_medida)} />
              )}
              {(activo.lote || activo.vencimiento) && (
                <div className="fila">
                  {activo.lote && <Marcador titulo="Lote" valor={activo.lote} />}
                  {activo.vencimiento && (
                    <Marcador titulo="Vencimiento" valor={formatoFecha(activo.vencimiento)} />
                  )}
                </div>
              )}
              <div className="selector-cantidad">
                <button className="btn" aria-label="Restar" onClick={() => void ajustar(-paso)}>
                  <Minus size={48} />
                </button>
                <button className="cantidad-valor" onClick={() => setPanel({ tipo: 'total', item: activo })}>
                  {formatoCantidad(activo.cant_recibida, activo.tipo_medida)}
                  <small>Tocá para escribir el total</small>
                </button>
                <button className="btn" aria-label="Sumar" onClick={() => void ajustar(paso)}>
                  <Plus size={48} />
                </button>
              </div>
            </div>
          ) : (
            <div className="vacio">
              <ScanLine size={64} />
              <h2>Escaneá el primer producto</h2>
              <p>Si no tiene código, usá la carga manual.</p>
            </div>
          )}
        </section>

        <aside className="carga-lista">
          <h2>Productos ({items.length})</h2>
          {items.map((i) => (
            <button
              className="tarjeta tarjeta-tactil fila-item"
              aria-pressed={i.key === activoKey}
              key={i.key}
              onClick={() => setActivoKey(i.key)}
            >
              <span className="grupo">
                <strong>{i.producto_nombre}</strong>
                {i.lote && <span className="mono muted">Lote {i.lote}</span>}
                {(i.cant_pedida ?? null) !== null && (
                  <span className="mono muted">Pedido {formatoCantidad(i.cant_pedida!, i.tipo_medida)}</span>
                )}
              </span>
              <span className="mono">{formatoCantidad(i.cant_recibida, i.tipo_medida)}</span>
            </button>
          ))}
        </aside>
      </div>

      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/')}>
          <ArrowLeft size={24} /> Inicio
        </button>
        <button className="btn" onClick={() => setPanel({ tipo: 'manual' })}>
          <Hand size={24} /> Carga manual
        </button>
        <button className="btn" onClick={() => setPanel({ tipo: 'camara' })}>
          <Video size={24} /> Escanear con cámara
        </button>
        <span className="espacio" />
        <button
          className="btn btn-primario"
          onClick={() => navegar(`/recepcion/${id}/resumen`)}
        >
          Ir al resumen
        </button>
      </footer>

      {panel.tipo === 'camara' && (
        <CamaraEscaner alLeer={alLeerCamara} alCerrar={() => setPanel({ tipo: 'ninguno' })} />
      )}
      {panel.tipo === 'manual' && (
        <SelectorProducto
          titulo="Elegí una categoría"
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alElegir={(producto) => setPanel({ tipo: 'motivo', producto })}
        />
      )}
      {panel.tipo === 'motivo' && (
        <ModalMotivo
          producto={panel.producto}
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alElegir={(motivo) => setPanel({ tipo: 'fotoManual', producto: panel.producto, motivo })}
        />
      )}
      {panel.tipo === 'fotoManual' && (
        <Modal titulo={`Foto de ${panel.producto.nombre}`} alCerrar={() => setPanel({ tipo: 'ninguno' })}>
          <p>La foto es obligatoria en la carga manual.</p>
          <BotonFoto
            primario
            alCapturar={(foto) =>
              void resolverProducto(panel.producto, {
                tipo: 'MANUAL',
                crudo: null,
                motivo: panel.motivo,
                foto,
              })
            }
          >
            <Camera size={24} /> Sacar foto
          </BotonFoto>
        </Modal>
      )}
      {panel.tipo === 'alta' && (
        <ModalAltaProducto
          gtin={panel.gtin}
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alCrear={(producto) =>
            void resolverProducto(producto, {
              tipo: 'ESCANEO',
              crudo: panel.crudo,
              motivo: null,
              foto: null,
            })
          }
        />
      )}
      {panel.tipo === 'lote' && (
        <ModalLote
          panel={panel}
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alConfirmar={(lote, vencimiento) =>
            void continuar(panel.producto, panel.origen, lote, vencimiento)
          }
        />
      )}
      {panel.tipo === 'cantidad' && (
        <TecladoCantidad
          titulo={`${panel.producto.nombre}: cantidad`}
          medida={panel.producto.tipo_medida}
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alConfirmar={(valor) =>
            void guardar(panel.producto, panel.origen, valor, panel.lote, panel.vencimiento)
          }
        />
      )}
      {panel.tipo === 'total' && (
        <TecladoCantidad
          titulo={`${panel.item.producto_nombre}: total recibido`}
          medida={panel.item.tipo_medida}
          inicial={panel.item.cant_recibida}
          permitirCero
          alCerrar={() => setPanel({ tipo: 'ninguno' })}
          alConfirmar={async (valor) => {
            const delta = redondear(valor - panel.item.cant_recibida);
            if (delta !== 0) await ajustarItem(panel.item, delta);
            sonidoOk();
            setPanel({ tipo: 'ninguno' });
          }}
        />
      )}
    </div>
  );
}
