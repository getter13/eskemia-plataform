// Eskemia · Caché de datos del front (TanStack Query).
//
// Qué hace: crea el QueryClient único y define las claves de consulta por dominio, para
// que invalidar después de una acción sea explícito (invalidar claves.compras.ordenes).
// Dónde encaja: main.tsx lo provee a toda la app. Las pantallas nuevas leen con useQuery
// sobre funciones de @eskemia/cliente-api; las existentes de Compras y Recepción migran
// cuando se rehacen como herramientas (Etapa 11), porque hoy cachean en Dexie para
// trabajar sin señal.
import { QueryClient } from '@tanstack/react-query';
import { ErrorApi } from '@eskemia/cliente-api';

export const consultas = new QueryClient({
  defaultOptions: {
    queries: {
      // Los datos de operación cambian seguido, pero no hace falta pedirlos en cada foco.
      staleTime: 30_000,
      // Reintentar solo lo que puede andar al reintentar (red, servidor, sesión vencida).
      retry: (intentos, error) => intentos < 3 && (!(error instanceof ErrorApi) || error.transitorio),
    },
  },
});

/** Claves de consulta, por dominio y organización. */
export const claves = {
  organizaciones: ['organizaciones'] as const,
  permisos: (organizacionId: string) => ['permisos', organizacionId] as const,
  compras: {
    ordenes: (organizacionId: string) => ['compras', 'ordenes', organizacionId] as const,
    bandeja: (organizacionId: string) => ['compras', 'bandeja', organizacionId] as const,
  },
  recepcion: {
    bandeja: (organizacionId: string, fecha: string) => ['recepcion', 'bandeja', organizacionId, fecha] as const,
  },
};
