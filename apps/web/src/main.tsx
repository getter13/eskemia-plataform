// Eskemia · Punto de entrada de la app web.
//
// Qué hace: carga la tipografía y los tokens de la estética v2, inicia el cliente único
// de la API (con la clave pública del .env.local), crea la caché de TanStack Query y monta
// la app con el router.
// Dónde encaja: Vite lo carga desde index.html. Manrope viene de @fontsource/manrope y Vite
// la empaqueta como woff2 propio (autoalojada, sin CDN). Solo el subconjunto latino: es lo que
// usa el español y evita que la PWA precargue cirílico, griego y vietnamita. Las variables
// VITE_SUPABASE_* apuntan al gateway del stack local (infra/compose) o al del entorno donde se
// despliegue.
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClientProvider } from '@tanstack/react-query';
import { iniciarCliente } from '@eskemia/cliente-api';
import '@fontsource/manrope/latin-400.css';
import '@fontsource/manrope/latin-500.css';
import '@fontsource/manrope/latin-700.css';
import '@fontsource/manrope/latin-800.css';
import '@eskemia/tokens/tokens.css';
import './styles/app.css';
import { consultas } from './lib/consultas';
import { App } from './App';

iniciarCliente({
  url: import.meta.env.VITE_SUPABASE_URL as string,
  clave: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string,
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={consultas}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
);
