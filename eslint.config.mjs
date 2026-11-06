// Eskemia · ESLint del monorepo.
//
// Qué hace: hace cumplir dos reglas del CLAUDE.md: ningún archivo fuera de
// paquetes/cliente-api importa @supabase/supabase-js (todo acceso a la base pasa por
// @eskemia/cliente-api), y los íconos son de Phosphor (Lucide solo en pantallas heredadas
// hasta la Etapa 11). Suma las reglas de hooks de React (orden de los hooks como error;
// dependencias de efectos como aviso).
// Dónde encaja: `pnpm lint` en la raíz y el job "web" del CI. Las reglas de tokens de la
// estética v2 (sin hex ni px sueltos) se suman en la etapa de tokens.
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';

const SUPABASE = {
  group: ['@supabase/*'],
  message: 'Solo paquetes/cliente-api habla con Supabase: importá la función de @eskemia/cliente-api.',
};
const LUCIDE = {
  group: ['lucide-react'],
  message: 'Los íconos son de Phosphor (@phosphor-icons/react, peso fill). Lucide queda solo en pantallas heredadas hasta la Etapa 11.',
};

const prohibirSupabase = { 'no-restricted-imports': ['error', { patterns: [SUPABASE, LUCIDE] }] };

/** Pantallas heredadas del MVP: pueden seguir con Lucide hasta que la Etapa 11 las rehaga. */
const HEREDADAS = ['apps/web/src/paginas/**', 'apps/web/src/componentes/**', 'apps/web/src/App.tsx'];

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
    files: HEREDADAS,
    rules: { 'no-restricted-imports': ['error', { patterns: [SUPABASE] }] },
  },
  {
    // La única excepción a Supabase: el paquete que es la puerta a Supabase.
    files: ['paquetes/cliente-api/**'],
    rules: { 'no-restricted-imports': ['error', { patterns: [LUCIDE] }] },
  },
);
