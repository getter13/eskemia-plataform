-- Eskemia · Semilla de producción: módulos (herramientas) registrados.
--
-- Qué hace: catálogo global de módulos. Idempotente: se reaplica en cada despliegue.
-- Dónde encaja: nucleo.modulos. Cada módulo nuevo agrega su fila acá y su entrada en
-- apps/web/src/modulos/registro.ts. requiere = módulos que tienen que estar habilitados.

insert into nucleo.modulos (codigo, nombre, descripcion, requiere) values
  ('compras', 'Compras', 'Catálogo, pedidos y órdenes de compra con aprobación', '{}'),
  ('recepcion', 'Recepción', 'Recepción de mercadería con control contra remito u orden de compra', '{compras}'),
  ('colab', 'Salas de reuniones', 'Salas con chat de texto dentro de la organización', '{}')
on conflict (codigo) do update
  set nombre = excluded.nombre, descripcion = excluded.descripcion, requiere = excluded.requiere;
