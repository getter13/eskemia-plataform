// Crea los usuarios de prueba en el proyecto vinculado. Requiere `npx supabase link`.
// Uso, desde la raíz del repo: node supabase/scripts/crear-usuarios-prueba.mjs
//
// Las contraseñas se generan acá y se guardan solo en .env.local (ignorado por Git).
// Reejecutarlo reutiliza las contraseñas y no duplica usuarios.
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const TENANT = '00000000-0000-4000-8000-000000000001';
const SEDE = '00000000-0000-4000-8000-000000000002';

const USUARIOS = [
  {
    id: '00000000-0000-4000-c000-000000000001',
    email: 'operario@eskemia.test',
    rol: 'operario',
    nombreRol: 'Operario de recepción',
    nombre: 'Operario de prueba',
    sede: SEDE,
    variable: 'SEED_OPERARIO_PASSWORD',
  },
  {
    id: '00000000-0000-4000-c000-000000000002',
    email: 'admin@eskemia.test',
    rol: 'admin',
    nombreRol: 'Admin',
    nombre: 'Admin de prueba',
    sede: null,
    variable: 'SEED_ADMIN_PASSWORD',
  },
  {
    id: '00000000-0000-4000-c000-000000000003',
    email: 'comprador@eskemia.test',
    rol: 'operario',
    nombreRol: 'Comprador',
    nombre: 'Comprador de prueba',
    sede: SEDE,
    variable: 'SEED_COMPRADOR_PASSWORD',
  },
  {
    id: '00000000-0000-4000-c000-000000000004',
    email: 'encargado@eskemia.test',
    rol: 'supervisor',
    nombreRol: 'Encargado de compras',
    nombre: 'Encargado de prueba',
    sede: SEDE,
    variable: 'SEED_ENCARGADO_PASSWORD',
  },
];

const envPath = '.env.local';
const envActual = existsSync(envPath) ? readFileSync(envPath, 'utf8') : '';

function contrasena(variable) {
  const previa = envActual.match(new RegExp(`^${variable}=(.+)$`, 'm'));
  if (previa) return previa[1].trim();
  const nueva = randomBytes(18).toString('base64url');
  appendFileSync(envPath, `${variable}=${nueva}\n`);
  return nueva;
}

const claves = [];
const sql = USUARIOS.map((u) => {
  const clave = contrasena(u.variable);
  claves.push(clave);
  const metaIdentidad = JSON.stringify({ sub: u.id, email: u.email, email_verified: true });
  return `
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new
) values (
  '00000000-0000-0000-0000-000000000000', '${u.id}', 'authenticated', 'authenticated',
  '${u.email}', extensions.crypt('${clave}', extensions.gen_salt('bf', 10)), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
) on conflict (id) do update set encrypted_password = excluded.encrypted_password;

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values ('${u.id}', '${u.id}', '${metaIdentidad}', 'email', now(), now(), now())
on conflict (provider_id, provider) do nothing;

insert into public.perfiles (user_id, tenant_id, sede_id, rol, nombre)
values ('${u.id}', '${TENANT}', ${u.sede ? `'${u.sede}'` : 'null'}, '${u.rol}', '${u.nombre}')
on conflict (user_id) do nothing;

insert into public.usuario_roles (tenant_id, user_id, rol_id, sede_id)
select '${TENANT}', '${u.id}', r.id, ${u.sede ? `'${u.sede}'` : 'null'}
from public.roles r
where r.tenant_id = '${TENANT}' and r.nombre = '${u.nombreRol}'
on conflict do nothing;
`;
}).join('\n');

const dir = mkdtempSync(join(tmpdir(), 'eskemia-seed-'));
const archivo = join(dir, 'usuarios.sql');
try {
  writeFileSync(archivo, sql, 'utf8');
  const r = spawnSync(`npx supabase db query --remote --yes -f "${archivo}"`, {
    shell: true,
    encoding: 'utf8',
  });
  if (r.status !== 0) {
    let salida = `${r.stdout ?? ''}\n${r.stderr ?? ''}`;
    for (const clave of claves) salida = salida.replaceAll(clave, '***');
    console.error(`Falló la creación de usuarios:\n${salida}`);
    process.exit(1);
  }
  console.log('Usuarios listos:', USUARIOS.map((u) => `${u.email} (${u.rol})`).join(', '));
  console.log('Contraseñas en .env.local:', USUARIOS.map((u) => u.variable).join(', '));
} finally {
  rmSync(dir, { recursive: true, force: true });
}
