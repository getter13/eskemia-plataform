-- Eskemia · Pedido demo para ver órdenes pendientes en el kiosco. Requiere seed-compras-demo.sql.
-- Lo confirma el admin de prueba por la misma RPC que usa la app. Reejecutarlo no duplica nada:
-- confirmar_pedido es idempotente por request_uuid.
-- Uso: npx supabase db query --remote --yes -f supabase/seed-ordenes-demo.sql

begin;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-c000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select public.confirmar_pedido(
  '00000000-0000-4000-f200-000000000001',
  '00000000-0000-4000-8000-000000000002',
  (
    -- Una oferta preferida de cada uno de los primeros productos demo: reparte entre proveedores.
    select jsonb_agg(jsonb_build_object('oferta_id', c.oferta, 'cantidad', c.cantidad))
    from (
      select o.value ->> 'id' as oferta, (row_number() over (order by p.sku) % 3) + 2 as cantidad
      from public.catalogo_compras('00000000-0000-4000-8000-000000000002') p
      cross join lateral jsonb_array_elements(p.ofertas) with ordinality as o (value, n)
      where o.n = 1 and p.sku in ('DEMO-0001', 'DEMO-0002', 'DEMO-0003', 'DEMO-0004', 'DEMO-0009', 'DEMO-0016')
    ) c
  )
) as resultado;

commit;
