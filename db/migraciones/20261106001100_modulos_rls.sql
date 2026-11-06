-- Eskemia · Línea base v1 · 11: RLS de Compras y Recepción.
--
-- Qué hace: fuerza RLS en las tablas de los dos módulos y porta las políticas de lectura
-- del legado (alcance por sede y por permiso), siempre sobre
-- (select nucleo.es_miembro(organizacion_id)).
-- Dónde encaja: igual que 04 para el núcleo. Solo SELECT para authenticated; escriben
-- las RPC. compras.secuencias no tiene política: nadie la lee fuera de las RPC.
-- El filtro por módulo habilitado lo aplican las vistas de api (migración 13).

do $$
declare
  v_tabla text;
begin
  foreach v_tabla in array array[
    'compras.rubros', 'compras.sector_rubros', 'compras.categorias', 'compras.proveedores',
    'compras.productos', 'compras.presentaciones', 'compras.producto_codigos',
    'compras.producto_proveedor', 'compras.precios_historial', 'compras.pedidos_compra',
    'compras.pedido_items', 'compras.ordenes_compra', 'compras.oc_items',
    'compras.reglas_aprobacion', 'compras.secuencias', 'compras.configuracion',
    'recepcion.dispositivos', 'recepcion.recepciones', 'recepcion.recepcion_items',
    'recepcion.lecturas', 'recepcion.adjuntos'
  ] loop
    execute format('alter table %s enable row level security', v_tabla);
    execute format('alter table %s force row level security', v_tabla);
    execute format('revoke all on %s from public, anon, authenticated', v_tabla);
    if v_tabla <> 'compras.secuencias' then
      execute format('grant select on %s to authenticated', v_tabla);
    end if;
  end loop;
end;
$$;

-- Compras: catálogo -------------------------------------------------------------

create policy rubros_select on compras.rubros for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy sector_rubros_select on compras.sector_rubros for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy categorias_select on compras.categorias for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy proveedores_select on compras.proveedores for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy productos_select on compras.productos for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy presentaciones_select on compras.presentaciones for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy producto_codigos_select on compras.producto_codigos for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy producto_proveedor_select on compras.producto_proveedor for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      nucleo.tiene_permiso(organizacion_id, 'compras.catalogo.ver')
      or nucleo.tiene_permiso(organizacion_id, 'compras.catalogo.gestionar')
      or nucleo.tiene_permiso(organizacion_id, 'recepcion.precios.ver')
    )
  );

create policy precios_historial_select on compras.precios_historial for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      nucleo.tiene_permiso(organizacion_id, 'compras.catalogo.gestionar')
      or nucleo.tiene_permiso(organizacion_id, 'recepcion.precios.ver')
    )
  );

-- Compras: pedidos y órdenes ----------------------------------------------------

create policy pedidos_compra_select on compras.pedidos_compra for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      usuario_id = (select auth.uid())
      or nucleo.tiene_permiso(organizacion_id, 'compras.oc.ver_todas', sede_id)
    )
  );

create policy pedido_items_select on compras.pedido_items for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and exists (select 1 from compras.pedidos_compra p where p.id = pedido_items.pedido_id)
  );

create policy ordenes_compra_select on compras.ordenes_compra for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      usuario_id = (select auth.uid())
      or nucleo.tiene_permiso(organizacion_id, 'compras.oc.ver_todas', sede_id)
      or nucleo.tiene_permiso(organizacion_id, 'compras.oc.aprobar', sede_id)
    )
  );

create policy oc_items_select on compras.oc_items for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and exists (select 1 from compras.ordenes_compra o where o.id = oc_items.oc_id)
  );

create policy reglas_aprobacion_select on compras.reglas_aprobacion for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      nucleo.tiene_permiso(organizacion_id, 'compras.aprobacion.configurar')
      or nucleo.tiene_permiso(organizacion_id, 'compras.oc.aprobar')
    )
  );

create policy configuracion_select on compras.configuracion for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

-- Recepción ---------------------------------------------------------------------

create policy dispositivos_select on recepcion.dispositivos for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy recepciones_select on recepcion.recepciones for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy recepcion_items_select on recepcion.recepcion_items for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy lecturas_select on recepcion.lecturas for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));

create policy adjuntos_select on recepcion.adjuntos for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, sede_id));
