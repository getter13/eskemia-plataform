-- Eskemia · Semilla: catálogo de tarjetas del Inicio (idempotente).
--
-- Qué hace: registra las tarjetas que cada módulo ofrece para el Inicio, con el permiso
-- que exigen. Es el conjunto inicial; cada módulo nuevo suma las suyas acá y en
-- apps/web (modulos/registro.ts), con el mismo código.
-- Dónde encaja: db/scripts/aplicar.sh la corre después de las migraciones. Validación
-- en nucleo.tarjeta_elegible (migración 20261106001500).

insert into nucleo.tarjetas_inicio (codigo, modulo, permiso_codigo, titulo) values
  ('nucleo.usuarios',        'nucleo',    'nucleo.usuarios.gestionar',      'Usuarios'),
  ('nucleo.perfil_empresa',  'nucleo',    'nucleo.organizacion.configurar', 'Perfil de empresa'),
  ('colab.salas',            'colab',     null,                             'Salas de reuniones'),
  ('compras.pedido',         'compras',   'compras.pedido.crear',           'Nuevo pedido'),
  ('compras.pendientes',     'compras',   'compras.oc.aprobar',             'Órdenes para aprobar'),
  ('compras.tablero',        'compras',   'compras.oc.ver_todas',           'Tablero de órdenes'),
  ('recepcion.hoy',          'recepcion', 'recepcion.recepcion.operar',     'Recepción de hoy'),
  ('recepcion.pendientes',   'recepcion', 'recepcion.pendientes.ver',       'Pendientes de recepción'),
  ('recepcion.por_validar',  'recepcion', 'recepcion.recepcion.validar',    'Recepciones por validar')
on conflict (codigo) do update
  set modulo = excluded.modulo, permiso_codigo = excluded.permiso_codigo, titulo = excluded.titulo;
