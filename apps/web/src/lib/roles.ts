import { supabase } from './supabase';

export interface Permiso {
  codigo: string;
  modulo: string;
  descripcion: string;
}
export interface Rol {
  id: string;
  nombre: string;
  nivel_aprobacion: number;
  permisos: string[];
}
export interface Asignacion {
  id: string;
  user_id: string;
  rol_id: string;
  sede_id: string | null;
}
export interface Usuario {
  user_id: string;
  nombre: string;
  activo: boolean;
}
export interface Sede {
  id: string;
  nombre: string;
}
export interface DatosRoles {
  permisos: Permiso[];
  roles: Rol[];
  asignaciones: Asignacion[];
  usuarios: Usuario[];
  sedes: Sede[];
}

function exigir<T>(r: { data: T | null; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message);
  return r.data as T;
}

export async function traerDatosRoles(): Promise<DatosRoles> {
  const [permisos, roles, rolPermisos, asignaciones, usuarios, sedes] = await Promise.all([
    supabase.from('permisos').select('codigo,modulo,descripcion').order('codigo'),
    supabase.from('roles').select('id,nombre,nivel_aprobacion').eq('activo', true).order('nombre'),
    supabase.from('rol_permisos').select('rol_id,permiso_codigo'),
    supabase.from('usuario_roles').select('id,user_id,rol_id,sede_id'),
    supabase.from('perfiles').select('user_id,nombre,activo').order('nombre'),
    supabase.from('sedes').select('id,nombre').order('nombre'),
  ]);
  const vinculos = exigir(rolPermisos) as Array<{ rol_id: string; permiso_codigo: string }>;
  return {
    permisos: exigir(permisos) as Permiso[],
    roles: (exigir(roles) as Array<Omit<Rol, 'permisos'>>).map((r) => ({
      ...r,
      permisos: vinculos.filter((v) => v.rol_id === r.id).map((v) => v.permiso_codigo),
    })),
    asignaciones: exigir(asignaciones) as Asignacion[],
    usuarios: exigir(usuarios) as Usuario[],
    sedes: exigir(sedes) as Sede[],
  };
}

async function llamar(nombre: string, args: Record<string, unknown>) {
  const { error } = await supabase.rpc(nombre, args);
  if (error) throw new Error(error.message.replace(/^[A-Z_]+:\s*/, ''));
}

export const crearRol = (nombre: string, nivel: number) =>
  llamar('crear_rol', { p_nombre: nombre, p_nivel_aprobacion: nivel });

export const fijarPermisoRol = (rolId: string, permiso: string, activo: boolean) =>
  llamar('fijar_permiso_rol', { p_rol_id: rolId, p_permiso: permiso, p_activo: activo });

export const asignarRol = (userId: string, rolId: string, sedeId: string | null) =>
  llamar('asignar_rol', { p_user_id: userId, p_rol_id: rolId, p_sede_id: sedeId });

export const quitarRol = (id: string) => llamar('quitar_rol', { p_usuario_rol_id: id });
