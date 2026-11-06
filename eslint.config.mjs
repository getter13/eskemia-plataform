// Eskemia · ESLint del monorepo.
//
// Qué hace: hace cumplir una regla no negociable del CLAUDE.md: ningún archivo fuera de
// paquetes/cliente-api importa @supabase/supabase-js (ni sus subpaquetes). Todo acceso a
// la base pasa por @eskemia/cliente-api. Suma las reglas de hooks de React (orden de los
// hooks como error; dependencias de efectos como aviso).
// Dónde encaja: `pnpm lint` en la raíz y el job "web" del CI. Las reglas de tokens de la
// estética v2 (sin hex ni px sueltos) se suman en la etapa de tokens.
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';

const prohibirSupabase = {
  'no-restricted-imports': [
    'error',
    {
      patterns: [
        {
          group: ['@supabase/*'],
          message: 'Solo paquetes/cliente-api habla con Supabase: importá la función de @eskemia/cliente-api.',
        },
      ],
    },
  ],
};

export default tseslint.config(
  { ignores: ['**/node_modules/**', '**/dist/**', 'db/**', 'infra/**', 'docs/**', 'supabase/**'] },
  {
    files: ['**/*.{ts,tsx,js,mjs}'],
    languageOptions: { parser: tseslint.parser },
    rules: prohibirSupabase,
  },
  {
    files: ['apps/web/**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
    },
  },
  {
    // La única excepción: el paquete que es la puerta a Supabase.
    files: ['paquetes/cliente-api/**'],
    rules: { 'no-restricted-imports': 'off' },
  },
);
