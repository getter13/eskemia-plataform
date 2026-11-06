// Comprobante de la orden para el proveedor. Este módulo y su librería bajan solo al generar un PDF.
import { Document, Page, StyleSheet, Text, View, pdf } from '@react-pdf/renderer';
import { formatearMonto } from './catalogo';
import { formatoFecha, formatoFechaHora, formatoNumero } from './formato';
import type { ItemOrden, OrdenResumen } from './ordenes';

const TINTA = '#15181d';
const SECUNDARIO = '#5b6068';
const LINEA = '#d5d2c8';
const MARCA = '#0e5e5a';

const e = StyleSheet.create({
  pagina: { padding: 40, fontSize: 10, color: TINTA, fontFamily: 'Helvetica' },
  marca: { fontSize: 16, color: MARCA, fontFamily: 'Helvetica-Bold', marginBottom: 16 },
  titulo: { fontSize: 18, fontFamily: 'Helvetica-Bold', marginBottom: 4 },
  dato: { color: SECUNDARIO, marginBottom: 2 },
  bloque: { marginTop: 16, marginBottom: 16 },
  fila: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: LINEA, paddingVertical: 5 },
  encabezado: { fontFamily: 'Helvetica-Bold', borderBottomColor: TINTA },
  producto: { flex: 3, paddingRight: 8 },
  presentacion: { flex: 2, paddingRight: 8 },
  numero: { flex: 1, textAlign: 'right' },
  total: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 12, fontFamily: 'Helvetica-Bold', fontSize: 12 },
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
            <Text style={{ fontFamily: 'Helvetica-Bold' }}>{proveedor.nombre}</Text>
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
