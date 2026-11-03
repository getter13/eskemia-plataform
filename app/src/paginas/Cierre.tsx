import { useRef, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { Navigate, useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, ArrowLeft, CheckCircle2 } from 'lucide-react';
import { Encabezado } from '../componentes/Encabezado';
import { PadFirma, type PadFirmaRef } from '../componentes/PadFirma';
import { db } from '../lib/db';
import { ETIQUETA_ESTADO } from '../lib/formato';
import { cerrarRecepcion } from '../lib/operaciones';

export function Cierre() {
  const { id = '' } = useParams();
  const navegar = useNavigate();
  const receptor = useRef<PadFirmaRef>(null);
  const transportista = useRef<PadFirmaRef>(null);
  const [okReceptor, setOkReceptor] = useState(false);
  const [okTransportista, setOkTransportista] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [resultado, setResultado] = useState<'CERRADA_OK' | 'CERRADA_CON_DIFERENCIAS' | null>(null);

  const recepcion = useLiveQuery(async () => (await db.recepciones.get(id)) ?? null, [id]);
  if (recepcion === undefined) return null;
  if (!recepcion) return <Navigate to="/" replace />;
  // Al cerrar, el estado cambia antes de que se muestre el resultado.
  if (recepcion.estado !== 'EN_CONTROL' && !resultado && !guardando) {
    return <Navigate to="/" replace />;
  }

  if (resultado) {
    return (
      <div className="pantalla">
        <Encabezado />
        <main className="vacio" data-testid="resultado-cierre">
          {resultado === 'CERRADA_OK' ? <CheckCircle2 size={64} /> : <AlertTriangle size={64} />}
          <h1>{ETIQUETA_ESTADO[resultado]}</h1>
          <p>
            {recepcion.proveedor_nombre} · <span className="mono">{recepcion.nro_remito}</span>
          </p>
          <button className="btn btn-primario" onClick={() => navegar('/', { replace: true })}>
            Volver al inicio
          </button>
        </main>
      </div>
    );
  }

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Firmas</h2>
      </Encabezado>
      <main className="contenido estrecho">
        <PadFirma ref={receptor} titulo="Firma del receptor" alCambiar={setOkReceptor} />
        <PadFirma ref={transportista} titulo="Firma del transportista" alCambiar={setOkTransportista} />
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar(`/recepcion/${id}/resumen`)}>
          <ArrowLeft size={24} /> Volver al resumen
        </button>
        <span className="espacio" />
        <button
          className="btn btn-primario"
          disabled={!okReceptor || !okTransportista || guardando}
          onClick={async () => {
            setGuardando(true);
            const [a, b] = await Promise.all([
              receptor.current!.obtenerImagen(),
              transportista.current!.obtenerImagen(),
            ]);
            if (a && b) setResultado(await cerrarRecepcion(id, a, b));
            setGuardando(false);
          }}
        >
          Cerrar recepción
        </button>
      </footer>
    </div>
  );
}
