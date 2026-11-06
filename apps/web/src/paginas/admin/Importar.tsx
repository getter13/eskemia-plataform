import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, CheckCircle2, ChevronLeft, Download, Upload } from 'lucide-react';
import { Encabezado } from '../../componentes/Encabezado';
import { formatoNumero } from '../../lib/formato';
import {
  IMPORTACIONES,
  analizarCsv,
  descargarPlantilla,
  importarCatalogo,
  leerArchivo,
  type ErrorFila,
  type FilaImportacion,
  type ResultadoImportacion,
} from '../../lib/importacion';

const ERRORES_VISIBLES = 100;

export function Importar() {
  const navegar = useNavigate();
  const [tipo, setTipo] = useState(IMPORTACIONES[0].tipo);
  const [archivoClave, setArchivoClave] = useState(0);
  const [filas, setFilas] = useState<FilaImportacion[]>([]);
  const [errores, setErrores] = useState<ErrorFila[]>([]);
  const [previa, setPrevia] = useState<ResultadoImportacion | null>(null);
  const [aplicado, setAplicado] = useState<ResultadoImportacion | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const def = IMPORTACIONES.find((d) => d.tipo === tipo) ?? IMPORTACIONES[0];

  function limpiar() {
    setFilas([]);
    setErrores([]);
    setPrevia(null);
    setArchivoClave((c) => c + 1);
  }

  async function elegirArchivo(archivo: File | undefined) {
    setPrevia(null);
    setAplicado(null);
    setErrores([]);
    setFilas([]);
    if (!archivo) return;
    setOcupado(true);
    try {
      const analisis = analizarCsv(def, await leerArchivo(archivo));
      setFilas(analisis.filas);
      if (analisis.errores.length > 0) {
        setErrores(analisis.errores);
        return;
      }
      if (analisis.filas.length === 0) {
        setErrores([{ fila: 0, mensaje: 'El archivo no tiene filas para importar.' }]);
        return;
      }
      const resultado = await importarCatalogo(def.tipo, analisis.filas, false);
      setErrores(resultado.errores);
      setPrevia(resultado);
    } catch (e) {
      setErrores([{ fila: 0, mensaje: e instanceof Error ? e.message : 'No se pudo revisar el archivo.' }]);
    } finally {
      setOcupado(false);
    }
  }

  async function importar() {
    setOcupado(true);
    try {
      const resultado = await importarCatalogo(def.tipo, filas, true);
      if (resultado.aplicado) {
        limpiar();
        setAplicado(resultado);
      } else {
        setErrores(resultado.errores);
        setPrevia(null);
      }
    } catch (e) {
      setErrores([{ fila: 0, mensaje: e instanceof Error ? e.message : 'No se pudo importar el archivo.' }]);
    } finally {
      setOcupado(false);
    }
  }

  const listo = previa !== null && errores.length === 0;

  return (
    <div className="pantalla">
      <Encabezado>
        <h2>Importar catálogo</h2>
      </Encabezado>
      <main className="contenido contenido-admin">
        <label className="grupo">
          <span className="label">Qué querés importar</span>
          <select
            className="campo campo-texto"
            value={tipo}
            onChange={(e) => {
              setTipo(e.target.value as typeof tipo);
              setAplicado(null);
              limpiar();
            }}
          >
            {IMPORTACIONES.map((d) => (
              <option key={d.tipo} value={d.tipo}>
                {d.etiqueta}
              </option>
            ))}
          </select>
        </label>

        <section className="tarjeta grupo">
          <p>{def.descripcion}</p>
          <ul className="lista-columnas">
            {def.columnas.map((c) => (
              <li key={c.nombre}>
                <span className="datos">{c.nombre}</span>
                {c.requerida ? ' (obligatoria)' : ''}: <span className="muted">{c.ayuda}</span>
              </li>
            ))}
          </ul>
          <div>
            <button className="btn" onClick={() => descargarPlantilla(def)}>
              <Download size={20} /> Descargar plantilla
            </button>
          </div>
        </section>

        <label className="grupo">
          <span className="label">Archivo CSV</span>
          <input
            className="campo campo-texto"
            key={archivoClave}
            type="file"
            accept=".csv,text/csv"
            disabled={ocupado}
            onChange={(e) => void elegirArchivo(e.target.files?.[0])}
          />
        </label>

        {ocupado && <p className="muted" role="status">Revisando el archivo…</p>}

        {errores.length > 0 && (
          <section className="grupo" role="alert">
            <p className="aviso-error">
              <AlertTriangle size={20} /> No se importó nada. Corregí{' '}
              {errores.length === 1 ? 'este error' : `estos ${formatoNumero(errores.length)} errores`} y volvé a elegir el
              archivo.
            </p>
            <ul className="lista-columnas">
              {errores.slice(0, ERRORES_VISIBLES).map((e, i) => (
                <li key={i}>
                  {e.fila > 0 && <span className="datos">Fila {e.fila}: </span>}
                  {e.mensaje}
                </li>
              ))}
            </ul>
            {errores.length > ERRORES_VISIBLES && (
              <p className="muted">Se muestran los primeros {ERRORES_VISIBLES}.</p>
            )}
          </section>
        )}

        {listo && (
          <p role="status">
            Archivo revisado: {formatoNumero(previa.creados)} para crear y {formatoNumero(previa.actualizados)} para
            actualizar.
          </p>
        )}

        {aplicado && (
          <p className="etiqueta" role="status">
            <CheckCircle2 size={16} /> Importación terminada: {formatoNumero(aplicado.creados)} creados y{' '}
            {formatoNumero(aplicado.actualizados)} actualizados.
          </p>
        )}
      </main>
      <footer className="barra-acciones">
        <button className="btn" onClick={() => navegar('/')}>
          <ChevronLeft size={24} /> Volver al inicio
        </button>
        <span className="espacio" />
        <button className="btn btn-primario" disabled={!listo || ocupado} onClick={() => void importar()}>
          <Upload size={24} /> Importar {listo ? `${formatoNumero(filas.length)} filas` : 'archivo'}
        </button>
      </footer>
    </div>
  );
}
