// Eskemia · Miembros, roles y permisos de una organización.
//
// Qué hace: lee el equipo y sus roles, y administra roles por RPC (crear, fijar permisos,
// asignar y quitar). Cada RPC exige nucleo.usuarios.gestionar y escribe en eventos.
// Dónde encaja: dominio "miembros" de la Etapa 3. Invitaciones y suspensión se suman en
// la Etapa 9.

import { cliente, rpcLibre } from './cliente';
import { exigir, sinError } from './errores';
import { sedes, type Sede } from './organizaciones';

/** Permiso del catálogo global. */
export interface Permiso {
  codigo: string;
  modulo: string;
  descripcion: string;
}

/** Rol de la organización con sus permisos. */
export interface Rol {
  id: string;
  nombre: string;
  nivel_aprobacion: number;
  es_sistema: boolean;
  permisos: string[];
}

/** Rol asignado a una cuenta, en una sede o en todas (sede nula). */
export interface Asignacion {
  id: string;
  cuenta_id: string;
  rol_id: string;
  sede_id: string | null;
}

/** Persona del equipo. */
export interface Miembro {
  cuenta_id: string;
  nombre: string;
  activo: boolean;
  es_titular: boolean;
}

/** Todo lo que necesita la pantalla de roles. */
export interface DatosRoles {
  permisos: Permiso[];
  roles: Rol[];
  asignaciones: Asignacion[];
  miembros: Miembro[];
  sedes: Sede[];
}

/** Nombre para mostrar a partir de nombre y apellido. */
export const nombreCompleto = (m: { nombre: string | null; apellido: string | null }) =>
  [m.nombre, m.apellido].filter(Boolean).join(' ') || 'Sin nombre';

/** Miembros de la organización (activos y suspendidos), por nombre. */
export async function miembros(organizacionId: string): Promise<Miembro[]> {
  const filas = exigir(
    await cliente()
      .from('miembros')
      .select('cuenta_id,nombre,apellido,estado,es_titular')
      .eq('organizacion_id', organizacionId),
  );
  return filas
    .map((m) => ({
      cuenta_id: m.cuenta_id as string,
      nombre: nombreCompleto(m),
      activo: m.estado === 'ACTIVA',
      es_titular: !!m.es_titular,
    }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre));
}

/** Catálogo de permisos, roles activos, asignaciones, miembros y sedes de la organización. */
export async function datosRoles(organizacionId: string): Promise<DatosRoles> {
  const c = cliente();
  const [permisos, roles, vinculos, asignaciones, equipo, listaSedes] = await Promise.all([
    c.from('permisos').select('codigo,modulo,descripcion').order('codigo'),
    c.from('roles').select('id,nombre,nivel_aprobacion,es_sistema')
      .eq('organizacion_id', organizacionId).eq('activo', true).order('nombre'),
    c.from('rol_permisos').select('rol_id,permiso_codigo').eq('organizacion_id', organizacionId),
    c.from('membresia_roles').select('id,cuenta_id,rol_id,sede_id').eq('organizacion_id', organizacionId),
    miembros(organizacionId),
    sedes(organizacionId),
  ]);
  const permisosPorRol = exigir(vinculos);
  return {
    permisos: exigir(permisos) as Permiso[],
    roles: exigir(roles).map((r) => ({
      id: r.id as string,
      nombre: r.nombre as string,
      nivel_aprobacion: r.nivel_aprobacion ?? 0,
      es_sistema: !!r.es_sistema,
      permisos: permisosPorRol.filter((v) => v.rol_id === r.id).map((v) => v.permiso_codigo as string),
    })),
    asignaciones: exigir(asignaciones) as Asignacion[],
    miembros: equipo,
    sedes: listaSedes,
  };
}

/** Crea un rol. PRECONDICION si el nombre ya existe en la organización. */
export async function crearRol(organizacionId: string, nombre: string, nivelAprobacion: number): Promise<string> {
  return exigir(
    await cliente().rpc('crear_rol', {
      p_organizacion_id: organizacionId,
      p_nombre: nombre,
      p_nivel_aprobacion: nivelAprobacion,
    }),
  );
}

/** Activa o desactiva un permiso de un rol. Idempotente. */
export async function fijarPermisoRol(rolId: string, permiso: string, activo: boolean): Promise<void> {
  sinError(await cliente().rpc('fijar_permiso_rol', { p_rol_id: rolId, p_permiso: permiso, p_activo: activo }));
}

/** Asigna un rol a una cuenta, en una sede o en todas (sede nula). Idempotente. */
export async function asignarRol(cuentaId: string, rolId: string, sedeId: string | null): Promise<string> {
  // sede nula = todas las sedes.
  return exigir(
    await rpcLibre('asignar_rol', { p_cuenta_id: cuentaId, p_rol_id: rolId, p_sede_id: sedeId, p_sector_id: null }),
  ) as string;
}

/** Quita una asignación. PRECONDICION si deja a la organización sin administración. */
export async function quitarRol(asignacionId: string): Promise<void> {
  sinError(await cliente().rpc('quitar_rol', { p_membresia_rol_id: asignacionId }));
}
