-- Eskemia · Tipos de diferencia contra la orden de compra (plan de Compras, etapa 8).
-- Va en su propia migración: un valor nuevo de enum no se puede usar en la transacción que lo crea.
alter type public.tipo_diferencia add value if not exists 'NO_PEDIDO';
alter type public.tipo_diferencia add value if not exists 'SUSTITUCION';
