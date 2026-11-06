// Eskemia · Roles y permisos de la organización actual.
//
// Qué hace: adapta lo que devuelve @eskemia/cliente-api a la forma que usa la pantalla de
// roles (usuarios con user_id, asignaciones por usuario) y expone las acciones.
// Dónde encaja: pantalla Admin > Usuarios y roles. Exige nucleo.usuarios.gestionar. La
// administración completa de usuarios e invitaciones llega en la Etapa 9.
import {
  asignarRol as asignar,
  crearRol as crear,
  datosRoles,
  fijarPermisoRol as fijarPermiso,
  quitarRol as quitar,
  type Permiso,
  type Rol,
  type Sede,
} from '@eskemia/cliente-api';
import { organizacionActual } from './db';

export type { Permiso, Rol, Sede };

/** Rol asignado a una persona, en una sede o en todas (sede nula). */
export interface Asignacion {
  id: string;
  user_id: string;
  rol_id: string;
  sede_id: string | null;
}

/** Persona del equipo. */
export interface Usuario {
  user_id: string;
  nombre: string;
  activo: boolean;
}

/** Todo lo que necesita la pantalla de roles. */
export interface DatosRoles {
  permisos: Permiso[];
  roles: Rol[];
  asignaciones: Asignacion[];
  usuarios: Usuario[];
  sedes: Sede[];
}

/** Permisos, roles, asignaciones, equipo y sedes de la organización actual. */
export async function traerDatosRoles(): Promise<DatosRoles> {
  const datos = await datosRoles(await organizacionActual());
  return {
    permisos: datos.permisos,
    roles: datos.roles,
    asignaciones: datos.asignaciones.map((a) => ({ id: a.id, user_id: a.cuenta_id, rol_id: a.rol_id, sede_id: a.sede_id })),
    usuarios: datos.miembros.map((m) => ({ user_id: m.cuenta_id, nombre: m.nombre, activo: m.activo })),
    sedes: datos.sedes,
  };
}

/** Crea un rol con su nivel de aprobación. */
export async function crearRol(nombre: string, nivel: number) {
  await crear(await organizacionActual(), nombre, nivel);
}

/** Activa o desactiva un permiso de un rol. */
export const fijarPermisoRol = (rolId: string, permiso: string, activo: boolean) => fijarPermiso(rolId, permiso, activo);

/** Asigna un rol a una persona, en una sede o en todas. */
export async function asignarRol(userId: string, rolId: string, sedeId: string | null) {
  await asignar(userId, rolId, sedeId);
}

/** Quita una asignación de rol. */
export const quitarRol = (id: string) => quitar(id);
