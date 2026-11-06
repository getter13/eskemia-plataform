-- Eskemia · Línea base v1 · 13: vistas de lectura del esquema api.
--
-- Qué hace: expone a PostgREST las lecturas que necesita el front, como vistas
-- security_invoker: RLS de las tablas decide qué filas ve cada cuenta. Las de cada
-- módulo filtran además por nucleo.modulo_habilitado.
-- Dónde encaja: regla "solo api se expone". Las tablas viven en esquemas privados.

-- Núcleo ------------------------------------------------------------------------

/* Organizaciones donde la cuenta es miembro activo: alimenta el selector. */
create view api.mis_organizaciones with (security_invoker = true) as
  select o.id, o.slug, o.nombre, o.descripcion, o.logo_path,
         o.titular_id = (select auth.uid()) as soy_titular,
         m.id as membresia_id, m.estado, m.puesto_id, p.nombre as puesto, m.unida_en
  from nucleo.membresias m
  join nucleo.organizaciones o on o.id = m.organizacion_id
  left join nucleo.puestos p on p.id = m.puesto_id
  where m.cuenta_id = (select auth.uid()) and m.estado = 'ACTIVA';

create view api.mi_cuenta with (security_invoker = true) as
  select c.id, c.nombre, c.apellido, c.alias, c.alias_visible, c.avatar_path,
         c.idioma, c.zona_horaria, c.creada_en
  from nucleo.cuentas c
  where c.id = (select auth.uid());

create view api.sedes with (security_invoker = true) as
  select s.id, s.organizacion_id, s.nombre, s.codigo, s.direccion, s.activa
  from nucleo.sedes s;

create view api.sectores with (security_invoker = true) as
  select s.id, s.organizacion_id, s.nombre, s.activo from nucleo.sectores s;

create view api.puestos with (security_invoker = true) as
  select p.id, p.organizacion_id, p.nombre, p.rol_sugerido, p.orden
  from nucleo.puestos p
  where p.activo;

/* Miembros de la organización (visibles según RLS de membresias y cuentas). */
create view api.miembros with (security_invoker = true) as
  select m.id as membresia_id, m.organizacion_id, m.cuenta_id, m.estado, m.unida_en,
         m.puesto_id, p.nombre as puesto, c.nombre, c.apellido, c.alias, c.avatar_path,
         o.titular_id = m.cuenta_id as es_titular
  from nucleo.membresias m
  join nucleo.organizaciones o on o.id = m.organizacion_id
  left join nucleo.cuentas c on c.id = m.cuenta_id
  left join nucleo.puestos p on p.id = m.puesto_id;

create view api.roles with (security_invoker = true) as
  select r.id, r.organizacion_id, r.nombre, r.tipo, r.nivel_aprobacion,
         r.limite_monto_sin_aprobacion, r.activo, r.es_sistema
  from nucleo.roles r;

create view api.rol_permisos with (security_invoker = true) as
  select rp.organizacion_id, rp.rol_id, rp.permiso_codigo from nucleo.rol_permisos rp;

create view api.permisos with (security_invoker = true) as
  select p.codigo, p.modulo, p.descripcion from nucleo.permisos p;

create view api.membresia_roles with (security_invoker = true) as
  select mr.id, mr.organizacion_id, mr.membresia_id, m.cuenta_id, mr.rol_id, r.nombre as rol,
         mr.sede_id, mr.sector_id
  from nucleo.membresia_roles mr
  join nucleo.membresias m on m.id = mr.membresia_id
  join nucleo.roles r on r.id = mr.rol_id;

create view api.modulos_habilitados with (security_invoker = true) as
  select mh.organizacion_id, mo.codigo, mo.nombre, mo.descripcion, mh.habilitado_en
  from nucleo.modulos_habilitados mh
  join nucleo.modulos mo on mo.codigo = mh.modulo_codigo
  where nucleo.modulo_habilitado(mh.organizacion_id, mo.codigo);

create view api.eventos with (security_invoker = true) as
  select e.id, e.organizacion_id, e.sede_id, e.secuencia, e.entidad, e.entidad_id, e.accion,
         e.payload, e.usuario_id, nucleo.nombre_cuenta(e.usuario_id) as usuario,
         e.dispositivo_id, e.creado_en
  from nucleo.eventos e;

create view api.mi_inicio with (security_invoker = true) as
  select it.organizacion_id, it.tarjeta_codigo, it.orden, it.visible
  from nucleo.inicio_tarjetas it
  where it.cuenta_id = (select auth.uid());

-- Compras -----------------------------------------------------------------------

create view api.rubros with (security_invoker = true) as
  select * from compras.rubros t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.categorias with (security_invoker = true) as
  select * from compras.categorias t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.proveedores with (security_invoker = true) as
  select * from compras.proveedores t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.productos with (security_invoker = true) as
  select * from compras.productos t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.presentaciones with (security_invoker = true) as
  select * from compras.presentaciones t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.producto_codigos with (security_invoker = true) as
  select * from compras.producto_codigos t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.producto_proveedor with (security_invoker = true) as
  select * from compras.producto_proveedor t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.pedidos_compra with (security_invoker = true) as
  select * from compras.pedidos_compra t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.pedido_items with (security_invoker = true) as
  select * from compras.pedido_items t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.ordenes_compra with (security_invoker = true) as
  select * from compras.ordenes_compra t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.oc_items with (security_invoker = true) as
  select * from compras.oc_items t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.oc_saldos with (security_invoker = true) as
  select * from compras.v_oc_saldos t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.reglas_aprobacion with (security_invoker = true) as
  select * from compras.reglas_aprobacion t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

create view api.configuracion_compras with (security_invoker = true) as
  select * from compras.configuracion t where nucleo.modulo_habilitado(t.organizacion_id, 'compras');

-- Recepción ---------------------------------------------------------------------

create view api.recepciones with (security_invoker = true) as
  select * from recepcion.recepciones t where nucleo.modulo_habilitado(t.organizacion_id, 'recepcion');

create view api.recepcion_items with (security_invoker = true) as
  select * from recepcion.recepcion_items t where nucleo.modulo_habilitado(t.organizacion_id, 'recepcion');

create view api.lecturas with (security_invoker = true) as
  select * from recepcion.lecturas t where nucleo.modulo_habilitado(t.organizacion_id, 'recepcion');

create view api.adjuntos with (security_invoker = true) as
  select * from recepcion.adjuntos t where nucleo.modulo_habilitado(t.organizacion_id, 'recepcion');

/* Bandeja del supervisor: una fila por recepción con checklist, semáforo y remito
 * duplicado. Port de public.v_recepciones_bandeja. */
create view api.recepciones_bandeja with (security_invoker = true) as
  select
    r.id,
    r.organizacion_id,
    r.sede_id,
    s.nombre as sede,
    r.estado,
    r.proveedor_id,
    p.nombre as proveedor,
    r.nro_remito,
    r.usuario_id,
    r.abierta_en,
    r.cerrada_en,
    r.validada_por,
    r.validada_en,
    r.observacion,
    (r.abierta_en at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
    coalesce(i.items, 0) as items,
    coalesce(i.items_con_diferencia, 0) as items_con_diferencia,
    c.checklist,
    exists (
      select 1 from recepcion.recepciones otra
      where otra.organizacion_id = r.organizacion_id
        and otra.proveedor_id = r.proveedor_id
        and lower(btrim(otra.nro_remito)) = lower(btrim(r.nro_remito))
        and otra.id <> r.id
    ) as remito_duplicado,
    case
      when not (c.checklist ->> 'completo')::boolean then 'CONTROL_INCOMPLETO'
      when coalesce(i.items_con_diferencia, 0) > 0 then 'CON_DIFERENCIAS'
      else 'OK'
    end as semaforo,
    r.oc_id,
    r.oc_numero
  from recepcion.recepciones r
  join nucleo.sedes s on s.id = r.sede_id
  join compras.proveedores p on p.id = r.proveedor_id
  left join lateral (
    select
      count(*) as items,
      count(*) filter (
        where ri.diferencia <> 0 or (r.oc_id is not null and t.recibida <> t.pedida)
      ) as items_con_diferencia
    from recepcion.recepcion_items ri
    cross join lateral (
      select sum(x.cant_recibida) as recibida, coalesce(sum(x.cant_pedida), 0) as pedida
      from recepcion.recepcion_items x
      where x.recepcion_id = ri.recepcion_id and x.producto_id = ri.producto_id
    ) t
    where ri.recepcion_id = r.id
  ) i on true
  cross join lateral (select recepcion.checklist(r.id) as checklist) c
  where nucleo.modulo_habilitado(r.organizacion_id, 'recepcion');

create view api.resumen_diario with (security_invoker = true) as
  select
    b.organizacion_id,
    b.sede_id,
    b.sede,
    b.fecha,
    count(*) as recepciones,
    count(*) filter (where b.semaforo = 'OK') as ok,
    count(*) filter (where b.semaforo = 'CON_DIFERENCIAS') as con_diferencias,
    count(*) filter (where b.semaforo = 'CONTROL_INCOMPLETO') as control_incompleto,
    count(*) filter (where b.estado in ('ABIERTA', 'EN_CONTROL')) as en_curso,
    count(*) filter (where b.estado in ('CERRADA_OK', 'CERRADA_CON_DIFERENCIAS')) as pendientes_validar,
    count(*) filter (where b.estado in ('VALIDADA', 'INGRESADA_A_SISTEMA')) as validadas,
    count(*) filter (where b.estado = 'RECHAZADA') as rechazadas,
    count(*) filter (where b.remito_duplicado) as remitos_duplicados,
    sum(b.items) as items,
    sum(b.items_con_diferencia) as items_con_diferencia
  from api.recepciones_bandeja b
  group by b.organizacion_id, b.sede_id, b.sede, b.fecha;
