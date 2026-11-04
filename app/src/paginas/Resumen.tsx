import { useEffect, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Navigate, useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, ArrowLeft, Camera, CheckCircle2, Plus } from 'lucide-react';
import { BotonFoto } from '../componentes/BotonFoto';
import { Encabezado } from '../componentes/Encabezado';
import { Modal } from '../componentes/Modal';
import { SelectorProducto } from '../componentes/SelectorProducto';
import { TecladoCantidad } from '../componentes/Teclado';
import { db, type ItemLocal, type Producto, type TipoDiferencia } from '../lib/db';
import { formatoCantidad, formatoFecha, redondear } from '../lib/formato';
import { agregarAdjunto, checklistLocal, diferenciaPedido, fijarControl, iniciarControl } from '../lib/operaciones';

const MOTIVOS: Record<TipoDiferencia, string[]> = {
  FALTANTE: ['No llegó', 'Vino menos de lo indicado', 'Error en el remito'],
  SOBRANTE: ['Enviaron de más', 'Error en el remito'],
  RECHAZO: ['Dañado', 'Vencido o próximo a vencer', 'No coincide con el pedido'],
  NO_PEDIDO: ['Enviaron sin pedirlo', 'Error del proveedor'],
  SUSTITUCION: ['Reemplazo de otro producto', 'Otra marca o presentación'],
};
const ETIQUETA_TIPO: Record<TipoDiferencia, string> = {
  FALTANTE: 'Faltante',
  SOBRANTE: 'Sobrante',
  RECHAZO: 'Rechazo',
  NO_PEDIDO: 'No pedido',
  SUSTITUCION: 'Sustitución',
};

const diferencia = (i: ItemLocal) =>
  i.cant_remito === null ? null : redondear(i.cant_recibida - i.cant_remito);

function verboDiferencia(dif: number) {
  const verbo = dif > 0 ? 'Sobra' : 'Falta';
  return Math.abs(dif) === 1 ? verbo : `${verbo}n`;
}

function tiposPosibles(dif: number, difPedido: number | null): TipoDiferencia[] {
  const extras: TipoDiferencia[] = difPedido === null ? [] : ['SUSTITUCION'];
  const referencia = dif !== 0 ? dif : (difPedido ?? 0);
  if (referencia > 0) return ['SOBRANTE', ...(difPedido === null ? [] : (['NO_PEDIDO'] as TipoDiferencia[])), ...extras];
  return ['FALTANTE', 'RECHAZO', ...extras];
}

function ModalDiferencia({
  item,
  difPedido,
  alCerrar,
}: {
  item: ItemLocal;
  difPedido: number | null;
  alCerrar: () => void;
}) {
  const dif = diferencia(item) ?? 0;
  const tipos = tiposPosibles(dif, difPedido);
  const [tipo, setTipo] = useState<TipoDiferencia>(
    item.tipo_diferencia && tipos.includes(item.tipo_diferencia) ? item.tipo_diferencia : tipos[0],
  );
  const [otro, setOtro] = useState('');

  async function guardar(motivo: string) {
    await fijarControl(
      item.recepcion_id,
      { id: item.producto_id, nombre: item.producto_nombre, tipo_medida: item.tipo_medida },
      item.lote,
      item.vencimiento,
      item.cant_remito,
      tipo,
      motivo,
    );
    alCerrar();
  }

  return (
    <Modal titulo={`Diferencia en ${item.producto_nombre}`} alCerrar={alCerrar}>
      {dif !== 0 && (
        <p>
          {verboDiferencia(dif)}{' '}
          <strong>{formatoCantidad(Math.abs(dif), item.tipo_medida)}</strong> respecto del remito.
        </p>
      )}
      {difPedido !== null && difPedido !== 0 && (
        <p>
          {verboDiferencia(difPedido)}{' '}
          <strong>{formatoCantidad(Math.abs(difPedido), item.tipo_medida)}</strong> respecto de lo pedido.
        </p>
      )}
      {tipos.length > 1 && (
        <div className="fila">
          {tipos.map((t) => (
            <button className="btn btn-seleccion" aria-pressed={tipo === t} key={t} onClick={() => setTipo(t)}>
              {ETIQUETA_TIPO[t]}
            </button>
          ))}
        </div>
      )}
      <div className="grilla">
        {MOTIVOS[tipo].map((m) => (
          <button className="tarjeta tarjeta-tactil" key={m} onClick={() => void guardar(m)}>
            <strong>{m}</strong>
          </button>
        ))}
      </div>
      <label className="grupo">
        <span className="label">Otro motivo</span>
        <input className="campo" value={otro} onChange={(e) => setOtro(e.target.value)} />
      </label>
      <button className="btn" disabled={otro.trim() === ''} onClick={() => void guardar(otro.trim())}>
        Guardar otro motivo
      </button>
      {tipo === 'RECHAZO' && (
        <div>
          <BotonFoto alCapturar={(foto) => void agregarAdjunto(item.recepcion_id, 'RECHAZO', foto, 'jpg', item.key)}>
            <Camera size={24} /> Foto del rechazo (opcional)
          </BotonFoto>
        </div>
      )}
    </Modal>
  );
}

export function Resumen() {
  const { id = '' } = useParams();
  const navegar = useNavigate();
  const [teclado, setTeclado] = useState<ItemLocal | null>(null);
  const [nuevo, setNuevo] = useState<Producto | null>(null);
  const [selector, setSelector] = useState(false);
  const [claveDiferencia, setClaveDiferencia] = useState<string | null>(null);

  const recepcion = useLiveQuery(async () => (await db.recepciones.get(id)) ?? null, [id]);
  const items =
    useLiveQuery(
      () =>
        db.items
          .where('recepcion_id')
          .equals(id)
          .toArray()
          .then((l) => l.sort((a, b) => a.producto_nombre.localeCompare(b.producto_nombre, 'es'))),
      [id],
    ) ?? [];
  const checklist = useLiveQuery(() => checklistLocal(id), [id]);

  useEffect(() => {
    void iniciarControl(id);
  }, [id]);

  if (recepcion === undefined) return null;
  if (!recepcion || (recepcion.estado !== 'ABIERTA' && recepcion.estado !== 'EN_CONTROL')) {
    return <Navigate to="/" replace />;
  }

  const faltan: string[] = [];
  if (checklist) {
    if (!checklist.foto_remito) faltan.push('Falta la foto del remito o factura');
    if (!checklist.tiene_items) faltan.push('No hay productos cargados');
    if (!checklist.cantidades_remito) faltan.push('Falta la cantidad del remito en algún producto');
    if (!checklist.motivos_diferencias) faltan.push('Falta el motivo de alguna diferencia');
    if (!checklist.fotos_manuales) faltan.push('Falta la foto de alguna carga manual');
  }
  const itemDiferencia = items.find((i) => i.key === claveDiferencia) ?? null;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Resumen</h2>
      </Encabezado>
      <main className="contenido">
        <p className="muted">
          {recepcion.proveedor_nombre} · <span className="mono">{recepcion.nro_remito}</span>
          {recepcion.oc_numero && (
            <>
              {' '}
              · Orden <span className="mono" data-testid="oc-numero">{recepcion.oc_numero}</span>
            </>
          )}
        </p>
        {recepcion.observacion && (
          <p className="aviso-error">
            <AlertTriangle size={20} /> Observación: {recepcion.observacion}
          </p>
        )}
        <p>
          {recepcion.oc_id
            ? 'Lo recibido se compara con lo pedido: indicá el motivo de cada diferencia.'
            : 'Cargá la cantidad que figura en el remito para cada producto.'}
        </p>

        <div className="tabla-control">
          {items.map((i) => {
            const dif = diferencia(i);
            const difPedido = diferenciaPedido(items, i.producto_id, !!recepcion.oc_id);
            // Con orden se controla por producto: un motivo cubre todos sus lotes.
            const motivo = recepcion.oc_id
              ? items.find((o) => o.producto_id === i.producto_id && o.motivo_diferencia?.trim())?.motivo_diferencia
              : i.motivo_diferencia?.trim();
            const conMotivo = !!motivo;
            const hayDiferencia = recepcion.oc_id ? (difPedido ?? 0) !== 0 : dif !== null && dif !== 0;
            const controlado = recepcion.oc_id ? !hayDiferencia : dif === 0;
            return (
              <div className="tarjeta fila-control" key={i.key} data-testid="fila-control">
                <span className="grupo">
                  <strong>{i.producto_nombre}</strong>
                  {i.lote && <span className="mono muted">Lote {i.lote}</span>}
                  {i.vencimiento && (
                    <span className="mono muted">Vence {formatoFecha(i.vencimiento)}</span>
                  )}
                  {recepcion.oc_id &&
                    items.every((o) => o.producto_id !== i.producto_id || (o.cant_pedida ?? null) === null) && (
                      <span className="etiqueta etiqueta-alerta">No está en la orden</span>
                    )}
                </span>
                <span className="grupo">
                  <span className="label">Recibido</span>
                  <span className="mono">{formatoCantidad(i.cant_recibida, i.tipo_medida)}</span>
                </span>
                {recepcion.oc_id ? (
                  <span className="grupo">
                    <span className="label">Pedido</span>
                    <span className="mono" data-testid="cant-pedida">
                      {(i.cant_pedida ?? null) === null ? '—' : formatoCantidad(i.cant_pedida!, i.tipo_medida)}
                    </span>
                  </span>
                ) : (
                  <span className="grupo">
                    <span className="label">Remito</span>
                    <button className="btn" onClick={() => setTeclado(i)}>
                      {i.cant_remito === null ? 'Cargar' : formatoCantidad(i.cant_remito, i.tipo_medida)}
                    </button>
                  </span>
                )}
                <span>
                  {controlado && (
                    <span className="etiqueta">
                      <CheckCircle2 size={16} /> Coincide
                    </span>
                  )}
                  {hayDiferencia && (
                    <button
                      className={`btn ancho ${conMotivo ? 'btn-seleccion' : 'btn-alerta'}`}
                      aria-pressed={conMotivo}
                      onClick={() => setClaveDiferencia(i.key)}
                    >
                      <AlertTriangle size={20} />
                      {recepcion.oc_id
                        ? `${verboDiferencia(difPedido!)} ${formatoCantidad(Math.abs(difPedido!), i.tipo_medida)} respecto de lo pedido`
                        : `${verboDiferencia(dif!)} ${formatoCantidad(Math.abs(dif!), i.tipo_medida)} respecto del remito`}
                      {conMotivo ? ` · ${motivo}` : ' · Indicar motivo'}
                    </button>
                  )}
                </span>
              </div>
            );
          })}
        </div>

        {!recepcion.oc_id && (
          <div>
            <button className="btn" onClick={() => setSelector(true)}>
              <Plus size={24} /> Agregar producto del remito que no llegó
            </button>
          </div>
        )}

        {faltan.length > 0 && (
          <ul className="lista-faltantes" data-testid="faltantes">
            {faltan.map((f) => (
              <li key={f}>{f}</li>
            ))}
          </ul>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar(`/recepcion/${id}/carga`)}>
          <ArrowLeft size={24} /> Volver a la carga
        </button>
        <span className="espacio" />
        <button
          className="btn btn-primario"
          disabled={faltan.length > 0 || !checklist}
          onClick={() => navegar(`/recepcion/${id}/cierre`)}
        >
          Continuar a firmas
        </button>
      </footer>

      {teclado && (
        <TecladoCantidad
          titulo={`${teclado.producto_nombre}: cantidad del remito`}
          medida={teclado.tipo_medida}
          inicial={teclado.cant_remito}
          permitirCero
          alCerrar={() => setTeclado(null)}
          alConfirmar={async (valor) => {
            const coincide = redondear(teclado.cant_recibida - valor) === 0;
            await fijarControl(
              id,
              { id: teclado.producto_id, nombre: teclado.producto_nombre, tipo_medida: teclado.tipo_medida },
              teclado.lote,
              teclado.vencimiento,
              valor,
              coincide ? null : teclado.tipo_diferencia,
              coincide ? null : teclado.motivo_diferencia,
            );
            setTeclado(null);
            if (!coincide) setClaveDiferencia(teclado.key);
          }}
        />
      )}
      {selector && (
        <SelectorProducto
          titulo="Producto del remito"
          alCerrar={() => setSelector(false)}
          alElegir={(p) => {
            setSelector(false);
            setNuevo(p);
          }}
        />
      )}
      {nuevo && (
        <TecladoCantidad
          titulo={`${nuevo.nombre}: cantidad del remito`}
          medida={nuevo.tipo_medida}
          alCerrar={() => setNuevo(null)}
          alConfirmar={async (valor) => {
            await fijarControl(id, nuevo, null, null, valor, null, null);
            setClaveDiferencia(`${id}|${nuevo.id}||`);
            setNuevo(null);
          }}
        />
      )}
      {itemDiferencia && (recepcion.oc_id || diferencia(itemDiferencia) !== null) && (
        <ModalDiferencia item={itemDiferencia} difPedido={diferenciaPedido(items, itemDiferencia.producto_id, !!recepcion.oc_id)} alCerrar={() => setClaveDiferencia(null)} />
      )}
    </div>
  );
}
