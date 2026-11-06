// Eskemia · Comprobante PDF de la orden de compra para el proveedor.
//
// Qué hace: arma el PDF con @react-pdf. Usa Manrope (los .woff de @fontsource, porque
// react-pdf no lee woff2) y los colores de tokens.json, así el PDF sigue a la marca sin
// valores sueltos. Las medidas van en puntos de PDF, no en tokens CSS: por eso el lint de
// tokens lo lista como excepción.
// Dónde encaja: este módulo y su librería bajan solo al generar un PDF (import dinámico).
import { Document, Font, Page, StyleSheet, Text, View, pdf } from '@react-pdf/renderer';
import tokens from '@eskemia/tokens/tokens.json';
import manrope500 from '@fontsource/manrope/files/manrope-latin-500-normal.woff?url';
import manrope800 from '@fontsource/manrope/files/manrope-latin-800-normal.woff?url';
import { formatearMonto, formatoFecha, formatoFechaHora, formatoNumero } from './formato';
import type { ItemOrden, OrdenResumen } from './ordenes';

Font.register({
  family: 'Manrope',
  fonts: [
    { src: manrope500, fontWeight: 500 },
    { src: manrope800, fontWeight: 800 },
  ],
});

/** Color de marca por nombre de token (tokens.json). */
const color = (nombre: string) => tokens.color.tokens.find((t) => t.name === nombre)?.value ?? 'black';

const e = StyleSheet.create({
  pagina: { padding: 40, fontSize: 10, color: color('ink'), fontFamily: 'Manrope', fontWeight: 500 },
  marca: { fontSize: 16, color: color('brand'), fontWeight: 800, marginBottom: 16 },
  titulo: { fontSize: 18, fontWeight: 800, marginBottom: 4 },
  dato: { color: color('ink-muted'), marginBottom: 2 },
  bloque: { marginTop: 16, marginBottom: 16 },
  fila: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: color('line'), paddingVertical: 5 },
  encabezado: { fontWeight: 800, borderBottomColor: color('ink') },
  destacado: { fontWeight: 800 },
  producto: { flex: 3, paddingRight: 8 },
  presentacion: { flex: 2, paddingRight: 8 },
  numero: { flex: 1, textAlign: 'right' },
  total: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 12, fontWeight: 800, fontSize: 12 },
});

function DocumentoOrden({ orden, items }: { orden: OrdenResumen; items: ItemOrden[] }) {
  const proveedor = orden.proveedores;
  return (
    <Document title={`Orden de compra ${orden.numero}`}>
      <Page size="A4" style={e.pagina}>
        <Text style={e.marca}>Eskemia</Text>
        <Text style={e.titulo}>Orden de compra {orden.numero}</Text>
        <Text style={e.dato}>Emitida: {formatoFechaHora(orden.creado_en)}</Text>
        {orden.fecha_entrega_estimada && (
          <Text style={e.dato}>Entrega estimada: {formatoFecha(orden.fecha_entrega_estimada)}</Text>
        )}

        {proveedor && (
          <View style={e.bloque}>
            <Text style={e.destacado}>{proveedor.nombre}</Text>
            <Text style={e.dato}>CUIT {proveedor.cuit}</Text>
            {proveedor.codigo && <Text style={e.dato}>ID {proveedor.codigo}</Text>}
          </View>
        )}

        <View style={[e.fila, e.encabezado]}>
          <Text style={e.producto}>Producto</Text>
          <Text style={e.presentacion}>Presentación</Text>
          <Text style={e.numero}>Cantidad</Text>
          <Text style={e.numero}>Precio</Text>
          <Text style={e.numero}>Subtotal</Text>
        </View>
        {items.map((i) => (
          <View style={e.fila} key={i.id} wrap={false}>
            <View style={e.producto}>
              <Text>{i.producto_nombre}</Text>
              {i.sku && <Text style={e.dato}>SKU {i.sku}</Text>}
            </View>
            <Text style={e.presentacion}>{i.presentacion_nombre}</Text>
            <Text style={e.numero}>{formatoNumero(i.cantidad)}</Text>
            <Text style={e.numero}>{i.precio_unitario === null ? '-' : formatearMonto(i.precio_unitario)}</Text>
            <Text style={e.numero}>{formatearMonto(i.subtotal)}</Text>
          </View>
        ))}
        <View style={e.total}>
          <Text>Total estimado: {formatearMonto(orden.total_estimado)}</Text>
        </View>
      </Page>
    </Document>
  );
}

export function generarPdfOrden(orden: OrdenResumen, items: ItemOrden[]): Promise<Blob> {
  return pdf(<DocumentoOrden orden={orden} items={items} />).toBlob();
}
