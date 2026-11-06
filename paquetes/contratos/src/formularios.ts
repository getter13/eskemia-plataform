// Eskemia · Esquemas Zod de formularios.
//
// Qué hace: valida en el front lo mismo que la base exige como precondición, para avisar
// al salir del campo en lugar de esperar el error del servidor. La base sigue siendo la
// que decide: estos esquemas solo mejoran la respuesta.
// Dónde encaja: formularios de apps/web (ingreso y registro en la Etapa 4, organización
// en la 5, invitaciones en la 9) y motivos de anulación o rechazo en Compras y Recepción.
// Mensajes en español rioplatense, sin culpar a la persona.

import { z } from 'zod';

/** Email normalizado (minúsculas, sin espacios), como lo guarda la base. */
export const email = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, 'Escribí tu email')
  .email('Revisá el email: le falta algo');

/** Contraseña con el mínimo que exige Auth (12 caracteres, ver infra/compose). */
export const contrasena = z.string().min(12, 'La contraseña necesita al menos 12 caracteres');

export const esquemaIngreso = z.object({
  email,
  contrasena: z.string().min(1, 'Escribí tu contraseña'),
});
export type DatosIngreso = z.infer<typeof esquemaIngreso>;

export const esquemaRegistro = z.object({
  nombre: z.string().trim().min(1, 'Escribí tu nombre'),
  apellido: z.string().trim().min(1, 'Escribí tu apellido'),
  email,
  contrasena,
  aceptaTerminos: z.literal(true, { message: 'Para seguir, aceptá los términos' }),
});
export type DatosRegistro = z.infer<typeof esquemaRegistro>;

/** api.crear_organizacion: el nombre no puede quedar vacío. */
export const esquemaOrganizacion = z.object({
  nombre: z.string().trim().min(1, 'Escribí el nombre de la empresa').max(120, 'Usá un nombre más corto'),
  descripcion: z.string().trim().max(500, 'Usá una descripción más corta').optional(),
  puestoId: z.uuid('Elegí tu puesto').optional(),
});
export type DatosOrganizacion = z.infer<typeof esquemaOrganizacion>;

/** api.invitar: email válido y un rol. */
export const esquemaInvitacion = z.object({
  email,
  rolId: z.uuid('Elegí un rol'),
  sedeId: z.uuid().nullable(),
});
export type DatosInvitacion = z.infer<typeof esquemaInvitacion>;

/** Anular una OC, cerrar saldo, rechazar una OC o una recepción: el motivo es obligatorio. */
export const motivo = z.string().trim().min(1, 'Contá brevemente el motivo').max(500, 'Usá un motivo más corto');
