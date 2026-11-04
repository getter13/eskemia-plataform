# Guion de prueba: de la compra a la recepción

Recorre el criterio de salida del MVP (`docs/plan-compras.md` §9) con los datos demo. Toma unos 15 minutos.

## Antes de empezar

Una sola vez, desde la raíz del repo, para crear los usuarios de prueba que faltan. Las contraseñas quedan en `.env.local`:

```bash
node supabase/scripts/crear-usuarios-prueba.mjs
```

| Usuario | Rol | Para qué |
|---|---|---|
| `comprador@eskemia.test` | Comprador | Arma el pedido |
| `encargado@eskemia.test` | Encargado de compras (nivel 1) | Aprueba |
| `operario@eskemia.test` | Operario de recepción | Recibe |
| `admin@eskemia.test` | Admin | Revisa el tablero y el back |

Los datos demo ya están cargados: `supabase/seed-compras-demo.sql` (40 productos, 3 proveedores, 3 reglas).

**Reglas demo:** Proteínas siempre requiere aprobación; Con alcohol, si supera $ 50.000 (nivel 2); Limpieza nunca.

## Códigos para escanear

| Producto | Código | Suma |
|---|---|---|
| Yerba mate, caja | `17799000000010` | 12 unidades |
| Yerba mate, unidad | `7799000000013` | 1 unidad |
| Gaseosa cola, caja | `17799000000140` | 12 unidades |
| Gaseosa cola, unidad | `7799000000143` | 1 unidad |
| Carne picada | `7799000002109` | Pide los kilos |

Sin lector físico, tipeá el código en el navegador y apretá Enter en la pantalla de carga: el campo del escáner tiene el foco.

## 1. Comprador: armar el pedido

Entrá como `comprador@eskemia.test`, en el celular o a 375 px.

1. Buscá **yreba**, con el error de tipeo: tiene que aparecer Yerba mate.
2. Agregá **2** de Yerba mate (Alimentos Demo del Sur).
3. Tocá el "+" de **Carne picada**. Tiene dos proveedores, así que no se agrega hasta que elijas: elegí Distribuidora Demo Norte y dejá **5**.
4. Agregá **3** de Gaseosa cola (Lácteos Demo SA).
5. **Ver pedido** muestra 3 proveedores. La orden de carne avisa "Esta orden va a aprobación".
6. **Confirmar pedido**.

**Esperado en Pedidos:** 3 órdenes. La de Distribuidora Demo Norte, *En aprobación*; las otras dos, *Aprobada*.

## 2. Encargado: aprobar

Entrá como `encargado@eskemia.test`, en **Aprobar**.

1. La orden de carne muestra el motivo: "Regla de la categoría: siempre se aprueba. Nivel 1".
2. **Aprobar OC**, luego **Deshacer** dentro de los 5 segundos: la orden vuelve a la bandeja.
3. **Aprobar OC** de nuevo y esperá.

**Esperado:** la bandeja queda vacía y, para el comprador, la orden pasa a *Aprobada* sin recargar.

## 3. Operario: recibir completa, escaneando cajas

Entrá como `operario@eskemia.test`. Las órdenes aparecen en **Pendientes de recibir** con la etiqueta *No recibido* (hasta 20 segundos después de aprobarse).

1. Tocá la orden de **Alimentos Demo del Sur**. Tiene que mostrar el proveedor y la OC fijos, y pedir solo número de remito y foto.
2. **Empezar a cargar** y escaneá dos veces `17799000000010`: cada lectura suma 12.
3. **Ir al resumen**.

**Esperado:** Yerba mate, recibido 24, pedido 24, *Coincide*. No se pide remito.

4. Firmá y cerrá: *Cerrada OK*. La orden sale de Pendientes.

## 4. Operario: recibir de menos y agregar algo no pedido

1. Tocá la orden de **Lácteos Demo SA** y escaneá una caja `17799000000140`. Son 12 de las 36 pedidas.
2. Escaneá `7799000000013`: Yerba mate no está en esta orden, y el kiosco lo avisa.
3. **Ir al resumen**.

**Esperado:**

- Gaseosa cola: "Faltan 24 unidades respecto de lo pedido · Indicar motivo".
- Yerba mate: "No está en la orden" y "Sobra 1 unidad respecto de lo pedido".
- No se puede pasar a firmas hasta indicar los dos motivos.

4. Indicá los motivos (Faltante; No pedido), firmá y cerrá: *Cerrada con diferencias*.

**Esperado en Pendientes:** la orden sigue, como *Recibida parcial*. Al abrirla de nuevo, Gaseosa cola precarga solo las 24 que faltan.

## 5. Admin: tablero y back

Entrá como `admin@eskemia.test`.

1. **Órdenes de compra:** filtrá por estado y buscá por número.
2. Abrí la de Lácteos Demo SA: "12 de 36 · Falta 24" y su recepción.
3. **Cerrar saldo pendiente**, con motivo. La orden pasa a *Cerrada* y sale de Pendientes.
4. Abrí la de Distribuidora Demo Norte, que no tiene recepciones, y **Anular orden**, con motivo.
5. **Administración** (la bandeja de recepciones): la recepción de Lácteos Demo SA aparece *Con diferencias* y muestra su OC; el detalle muestra Pedido, Recibido y Diferencia.

## 6. Sin señal (opcional)

En el celular, en modo avión:

1. Abrí el marketplace: el catálogo carga igual, con el aviso "Sin conexión".
2. Armá un pedido y confirmalo: queda "Se confirma al volver la señal".
3. Volvé a tener señal: aparece la orden, una sola.

## Si algo no coincide

Anotá el paso y lo que viste. Los datos son de prueba: las órdenes y recepciones se pueden volver a generar, pero los `eventos` no se borran.
