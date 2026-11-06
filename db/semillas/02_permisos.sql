-- Eskemia · Semilla de producción: catálogo global de permisos.
--
-- Qué hace: códigos de permiso que consultan las RPC y el front (nunca nombres de rol).
-- Idempotente. Los 17 del legado (admin.* pasó a nucleo.*) + nucleo.organizacion.configurar.
-- Dónde encaja: nucleo.permisos. El rol Admin semilla recibe todos los que existan al
-- crear la organización.

insert into nucleo.permisos (codigo, modulo, descripcion) values
  ('nucleo.organizacion.configurar', 'nucleo', 'Editar el perfil de empresa, las sedes y los módulos'),
  ('nucleo.usuarios.gestionar', 'nucleo', 'Usuarios, roles y permisos'),
  ('nucleo.eventos.verificar', 'nucleo', 'Verificar la cadena de hash de eventos'),
  ('compras.aprobacion.configurar', 'compras', 'Editar reglas de aprobación'),
  ('compras.catalogo.gestionar', 'compras', 'Alta y edición de productos, códigos, proveedores, precios e importación'),
  ('compras.catalogo.ver', 'compras', 'Ver marketplace'),
  ('compras.oc.anular', 'compras', 'Anular órdenes de compra sin recepciones'),
  ('compras.oc.aprobar', 'compras', 'Aprobar o rechazar órdenes de compra, hasta su nivel de aprobación'),
  ('compras.oc.cerrar_saldo', 'compras', 'Cerrar saldo pendiente'),
  ('compras.oc.ver_todas', 'compras', 'Ver órdenes de compra de otros usuarios'),
  ('compras.pedido.crear', 'compras', 'Armar y confirmar pedidos'),
  ('recepcion.eventos.ver', 'recepcion', 'Ver la línea de tiempo de eventos y quiénes actuaron'),
  ('recepcion.pendientes.ver', 'recepcion', 'Ver lista de órdenes de compra pendientes'),
  ('recepcion.pendientes.ver_en_aprobacion', 'recepcion', 'Ver también órdenes aún no aprobadas'),
  ('recepcion.precios.ver', 'recepcion', 'Ver precios en órdenes de compra'),
  ('recepcion.recepcion.marcar_ingresada', 'recepcion', 'Marcar una recepción validada como ingresada a sistema'),
  ('recepcion.recepcion.operar', 'recepcion', 'Operar el kiosco'),
  ('recepcion.recepcion.validar', 'recepcion', 'Validar o rechazar recepciones')
on conflict (codigo) do update set modulo = excluded.modulo, descripcion = excluded.descripcion;
