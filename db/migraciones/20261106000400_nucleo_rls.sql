-- Eskemia · Línea base v1 · 04: RLS del núcleo.
--
-- Qué hace: fuerza RLS en todas las tablas de nucleo y define las políticas de lectura.
-- Nadie escribe directo: authenticated solo tiene SELECT; toda escritura pasa por RPC.
-- Dónde encaja: regla no negociable del CLAUDE.md. La política tipo es
--   (select nucleo.es_miembro(organizacion_id))
-- y se combina con las restricciones por sede y permiso que ya tenía el legado.
-- Excepciones sin organizacion_id: cuentas, organizaciones (usa su id), permisos y
-- modulos (catálogos globales), puestos (filas globales con organizacion_id nulo).

/** true si la cuenta dada comparte alguna organización con la cuenta actual (como
 *  miembro activo de esa organización). Permite ver nombres de compañeros. */
create function nucleo.comparte_organizacion(p_cuenta_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from nucleo.membresias yo
    join nucleo.membresias otro on otro.organizacion_id = yo.organizacion_id
    where yo.cuenta_id = (select auth.uid())
      and yo.estado = 'ACTIVA'
      and otro.cuenta_id = p_cuenta_id
  );
$$;

do $$
declare
  v_tabla text;
begin
  foreach v_tabla in array array[
    'cuentas', 'organizaciones', 'perfil_organizacion', 'sedes', 'sectores', 'puestos',
    'membresias', 'permisos', 'roles', 'rol_permisos', 'membresia_roles', 'invitaciones',
    'modulos', 'modulos_habilitados', 'eventos', 'inicio_tarjetas'
  ] loop
    execute format('alter table nucleo.%I enable row level security', v_tabla);
    execute format('alter table nucleo.%I force row level security', v_tabla);
    execute format('revoke all on nucleo.%I from public, anon, authenticated', v_tabla);
    execute format('grant select on nucleo.%I to authenticated', v_tabla);
  end loop;
end;
$$;

create policy cuentas_select on nucleo.cuentas for select to authenticated
  using (id = (select auth.uid()) or nucleo.comparte_organizacion(id));

create policy organizaciones_select on nucleo.organizaciones for select to authenticated
  using ((select nucleo.es_miembro(id)));

create policy perfil_organizacion_select on nucleo.perfil_organizacion for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy sedes_select on nucleo.sedes for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and nucleo.puede_ver_sede(organizacion_id, id));

create policy sectores_select on nucleo.sectores for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy puestos_select on nucleo.puestos for select to authenticated
  using (organizacion_id is null or (select nucleo.es_miembro(organizacion_id)));

-- La propia membresía siempre (incluso suspendida o invitada); las de otros, solo con
-- permiso de gestión de usuarios o de auditoría (como perfiles en el legado).
create policy membresias_select on nucleo.membresias for select to authenticated
  using (
    cuenta_id = (select auth.uid())
    or (
      (select nucleo.es_miembro(organizacion_id))
      and (
        nucleo.tiene_permiso(organizacion_id, 'nucleo.usuarios.gestionar')
        or nucleo.tiene_permiso(organizacion_id, 'recepcion.eventos.ver')
      )
    )
  );

create policy permisos_select on nucleo.permisos for select to authenticated
  using (true);

create policy roles_select on nucleo.roles for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      nucleo.tiene_permiso(organizacion_id, 'nucleo.usuarios.gestionar')
      or nucleo.tiene_permiso(organizacion_id, 'compras.aprobacion.configurar')
    )
  );

create policy rol_permisos_select on nucleo.rol_permisos for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and nucleo.tiene_permiso(organizacion_id, 'nucleo.usuarios.gestionar')
  );

create policy membresia_roles_select on nucleo.membresia_roles for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and (
      exists (
        select 1 from nucleo.membresias m
        where m.id = membresia_roles.membresia_id and m.cuenta_id = (select auth.uid())
      )
      or nucleo.tiene_permiso(organizacion_id, 'nucleo.usuarios.gestionar')
    )
  );

create policy invitaciones_select on nucleo.invitaciones for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and nucleo.tiene_permiso(organizacion_id, 'nucleo.usuarios.gestionar')
  );

create policy modulos_select on nucleo.modulos for select to authenticated
  using (true);

create policy modulos_habilitados_select on nucleo.modulos_habilitados for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)));

create policy eventos_select on nucleo.eventos for select to authenticated
  using (
    (select nucleo.es_miembro(organizacion_id))
    and nucleo.tiene_permiso(organizacion_id, 'recepcion.eventos.ver', sede_id)
    and nucleo.puede_ver_sede(organizacion_id, sede_id)
  );

create policy inicio_tarjetas_select on nucleo.inicio_tarjetas for select to authenticated
  using ((select nucleo.es_miembro(organizacion_id)) and cuenta_id = (select auth.uid()));
