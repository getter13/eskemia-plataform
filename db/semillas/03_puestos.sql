-- Eskemia · Semilla de producción: puestos genéricos (PROVISORIOS).
--
-- Qué hace: catálogo global (organizacion_id nulo) para el desplegable de bienvenida.
-- Lista genérica aprobada como provisoria en el plan; se reemplaza cuando haya una
-- definitiva. rol_sugerido es el nombre de un rol semilla. Idempotente.
-- Dónde encaja: nucleo.puestos.

insert into nucleo.puestos (organizacion_id, nombre, rol_sugerido, orden) values
  (null, 'Dueño/a o socio/a', 'Admin', 1),
  (null, 'Gerencia', 'Gerente', 2),
  (null, 'Administración', 'Administración', 3),
  (null, 'Compras', 'Comprador', 4),
  (null, 'Depósito', 'Supervisor de recepción', 5),
  (null, 'Recepción de mercadería', 'Operario de recepción', 6),
  (null, 'Producción/cocina', 'Comprador', 7),
  (null, 'Ventas/atención', null, 8),
  (null, 'Otro', null, 9)
on conflict (organizacion_id, nombre) do update
  set rol_sugerido = excluded.rol_sugerido, orden = excluded.orden;
