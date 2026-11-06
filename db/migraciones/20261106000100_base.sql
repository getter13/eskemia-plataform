-- Eskemia · Línea base v1 · 01: extensiones y esquemas.
--
-- Qué hace: crea los esquemas privados (nucleo, compras, recepcion, colab) y el único
-- esquema expuesto a PostgREST (api). Instala pgmq para la cola de emails.
-- Dónde encaja: primera migración de la línea base (Etapa 2 del plan). Las migraciones
-- anteriores quedan en db/legado/ como referencia de solo lectura.
-- Se aplica como el rol postgres (BYPASSRLS): sus funciones SECURITY DEFINER operan
-- aun con RLS forzado; el resto de los roles queda sujeto a las políticas.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pgmq;

create schema nucleo;
create schema compras;
create schema recepcion;
create schema colab;
create schema api;

comment on schema nucleo is 'Núcleo multi-organización: cuentas, organizaciones, membresías, roles, módulos y eventos. Privado.';
comment on schema compras is 'Módulo Compras: catálogo, pedidos y órdenes de compra. Privado.';
comment on schema recepcion is 'Módulo Recepción de mercadería. Privado.';
comment on schema colab is 'Módulo Salas de reuniones (chat de texto). Privado.';
comment on schema api is 'Único esquema expuesto a PostgREST: vistas security_invoker y RPC.';

-- Nadie usa los esquemas por defecto. authenticated necesita USAGE en los privados
-- porque las vistas de api son security_invoker y leen las tablas con sus permisos;
-- RLS forzado decide qué filas ve. PostgREST no los expone (PGRST_DB_SCHEMAS=api).
revoke all on schema nucleo, compras, recepcion, colab, api from public;
grant usage on schema nucleo, compras, recepcion, colab to authenticated, service_role;
grant usage on schema api to anon, authenticated, service_role;

-- Ninguna función nueva es ejecutable por defecto: cada RPC se habilita explícitamente.
alter default privileges in schema nucleo, compras, recepcion, colab, api
  revoke execute on functions from public;
