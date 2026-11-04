-- Eskemia · Datos demo del marketplace, marcados como demo. Solo para pruebas: requiere seed.sql.
-- Reejecutarlo no duplica nada. Uso: npx supabase db query --remote --yes -f supabase/seed-compras-demo.sql

insert into public.rubros (id, tenant_id, nombre, orden) values
  ('00000000-0000-4000-f000-000000000001', '00000000-0000-4000-8000-000000000001', 'Comida (demo)', 1),
  ('00000000-0000-4000-f000-000000000002', '00000000-0000-4000-8000-000000000001', 'Bebidas (demo)', 2),
  ('00000000-0000-4000-f000-000000000003', '00000000-0000-4000-8000-000000000001', 'Limpieza (demo)', 3)
on conflict (id) do nothing;

-- La categoría de prueba sigue usándose en la guía del kiosco: solo se le asigna rubro.
update public.categorias set rubro_id = '00000000-0000-4000-f000-000000000001'
where id = '00000000-0000-4000-d000-000000000001' and rubro_id is null;

insert into public.categorias (id, tenant_id, rubro_id, nombre, orden) values
  ('00000000-0000-4000-f100-000000000001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000001', 'Almacén', 1),
  ('00000000-0000-4000-f100-000000000002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000001', 'Lácteos y fiambres', 2),
  ('00000000-0000-4000-f100-000000000003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000002', 'Sin alcohol', 3),
  ('00000000-0000-4000-f100-000000000004', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000003', 'Hogar', 4)
on conflict (id) do nothing;

update public.productos p
set categoria_id = c.categoria::uuid
from (values
  ('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000005', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000007', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000008', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000019', '00000000-0000-4000-f100-000000000001'),
  ('00000000-0000-4000-b000-000000000010', '00000000-0000-4000-f100-000000000002'),
  ('00000000-0000-4000-b000-000000000012', '00000000-0000-4000-f100-000000000002'),
  ('00000000-0000-4000-b000-000000000013', '00000000-0000-4000-f100-000000000003'),
  ('00000000-0000-4000-b000-000000000014', '00000000-0000-4000-f100-000000000003'),
  ('00000000-0000-4000-b000-000000000015', '00000000-0000-4000-f100-000000000004'),
  ('00000000-0000-4000-b000-000000000016', '00000000-0000-4000-f100-000000000004'),
  ('00000000-0000-4000-b000-000000000017', '00000000-0000-4000-f100-000000000004'),
  ('00000000-0000-4000-b000-000000000018', '00000000-0000-4000-f100-000000000004')
) as c (producto, categoria)
where p.id = c.producto::uuid and p.categoria_id is null;

update public.productos set sku = 'DEMO-' || right(id::text, 4)
where id::text like '00000000-0000-4000-b000-%' and sku is null;

update public.proveedores p
set codigo = d.codigo, monto_minimo = d.minimo, plazo_entrega_dias = d.plazo
from (values
  ('00000000-0000-4000-a000-000000000001', 'DEMO-P1', 50000, 2),
  ('00000000-0000-4000-a000-000000000002', 'DEMO-P2', 30000, 1),
  ('00000000-0000-4000-a000-000000000003', 'DEMO-P3', null, 3)
) as d (id, codigo, minimo, plazo)
where p.id = d.id::uuid and p.codigo is null;

-- Una presentación mayorista para algunos productos.
insert into public.presentaciones (tenant_id, producto_id, nombre, factor)
select p.tenant_id, p.id, 'Caja x 12', 12
from public.productos p
where p.id in (
  '00000000-0000-4000-b000-000000000001',
  '00000000-0000-4000-b000-000000000006',
  '00000000-0000-4000-b000-000000000009',
  '00000000-0000-4000-b000-000000000014'
)
on conflict (producto_id, nombre) do nothing;

-- Todos tienen un proveedor; cada tercero tiene un segundo, para probar la elección en el pedido.
with productos_demo as (
  select p.id, p.tenant_id, right(p.id::text, 2)::int as n, pre.id as presentacion, pre.factor
  from public.productos p
  join public.presentaciones pre on pre.producto_id = p.id
  where p.id::text like '00000000-0000-4000-b000-%'
    and pre.id = (
      select x.id from public.presentaciones x where x.producto_id = p.id order by x.factor desc limit 1
    )
),
ofertas as (
  select tenant_id, id as producto, presentacion, factor, n,
    ('00000000-0000-4000-a000-00000000000' || (n % 3 + 1))::uuid as proveedor, 1.00 as recargo, true as preferido
  from productos_demo
  union all
  select tenant_id, id, presentacion, factor, n,
    ('00000000-0000-4000-a000-00000000000' || ((n + 1) % 3 + 1))::uuid, 0.92, false
  from productos_demo where n % 3 = 0
)
insert into public.producto_proveedor (tenant_id, producto_id, proveedor_id, presentacion_id, precio_actual, preferido)
select tenant_id, producto, proveedor, presentacion, round((800 + n * 137) * factor * recargo, 2), preferido
from ofertas
on conflict (producto_id, proveedor_id, presentacion_id) do nothing;

select
  (select count(*) from public.rubros where nombre like '%(demo)') as rubros_demo,
  (select count(*) from public.producto_proveedor) as ofertas,
  (select count(*) from public.productos where sku like 'DEMO-%') as con_sku;
