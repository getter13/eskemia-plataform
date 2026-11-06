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

-- Completa el catálogo gastronómico: rubro nuevo, categorías y 20 productos más, hasta 40.
insert into public.rubros (id, tenant_id, nombre, orden) values
  ('00000000-0000-4000-f000-000000000004', '00000000-0000-4000-8000-000000000001', 'Descartables (demo)', 4)
on conflict (id) do nothing;

insert into public.categorias (id, tenant_id, rubro_id, nombre, orden) values
  ('00000000-0000-4000-f100-000000000005', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000001', 'Proteínas', 5),
  ('00000000-0000-4000-f100-000000000006', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000001', 'Verdulería', 6),
  ('00000000-0000-4000-f100-000000000007', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000002', 'Con alcohol', 7),
  ('00000000-0000-4000-f100-000000000008', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-f000-000000000004', 'Salón', 8)
on conflict (id) do nothing;

-- Dígito verificador de un GTIN: el código tiene que ser válido para poder escanearlo.
create function pg_temp.con_digito(p_base text)
returns text
language sql
immutable
as $$
  select p_base || ((10 - sum(
    substr(reverse(p_base), n, 1)::int * case when n % 2 = 1 then 3 else 1 end
  )::int % 10) % 10)::text
  from generate_series(1, length(p_base)) as n
$$;

insert into public.productos (id, tenant_id, categoria_id, gtin, nombre, tipo_medida)
select
  ('00000000-0000-4000-b000-0000000000' || lpad(d.n::text, 2, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001',
  ('00000000-0000-4000-f100-00000000000' || d.categoria)::uuid,
  pg_temp.con_digito('7799000' || lpad((d.n * 10)::text, 5, '0')),
  d.nombre,
  d.medida::public.tipo_medida
from (values
  (21, 5, 'Carne picada', 'PESO'), (22, 5, 'Pollo entero', 'PESO'),
  (23, 5, 'Milanesa de nalga', 'PESO'), (24, 5, 'Filet de merluza', 'PESO'),
  (25, 6, 'Papa', 'PESO'), (26, 6, 'Cebolla', 'PESO'),
  (27, 6, 'Tomate perita', 'PESO'), (28, 6, 'Lechuga', 'PESO'),
  (29, 1, 'Polenta', 'UNIDAD'), (30, 1, 'Lentejas', 'UNIDAD'),
  (31, 1, 'Mayonesa', 'UNIDAD'), (32, 1, 'Vinagre', 'UNIDAD'),
  (33, 3, 'Jugo de naranja', 'UNIDAD'), (34, 3, 'Soda', 'UNIDAD'),
  (35, 7, 'Cerveza', 'UNIDAD'), (36, 7, 'Vino tinto', 'UNIDAD'),
  (37, 4, 'Esponja', 'UNIDAD'), (38, 4, 'Bolsa de residuos', 'UNIDAD'),
  (39, 8, 'Servilletas', 'UNIDAD'), (40, 8, 'Vasos descartables', 'UNIDAD')
) as d (n, categoria, nombre, medida)
on conflict (id) do nothing;

-- Reglas: Proteínas siempre, Con alcohol por monto, Limpieza nunca.
insert into public.reglas_aprobacion (tenant_id, alcance, alcance_id, modo, monto_umbral, nivel_requerido) values
  ('00000000-0000-4000-8000-000000000001', 'CATEGORIA', '00000000-0000-4000-f100-000000000005', 'SIEMPRE', null, 1),
  ('00000000-0000-4000-8000-000000000001', 'CATEGORIA', '00000000-0000-4000-f100-000000000007', 'POR_MONTO', 50000, 2),
  ('00000000-0000-4000-8000-000000000001', 'RUBRO', '00000000-0000-4000-f000-000000000003', 'NUNCA', null, 0)
on conflict (tenant_id, alcance, alcance_id) do nothing;

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

-- El código de la caja: escanearla suma 12 unidades contra la orden.
insert into public.producto_codigos (tenant_id, producto_id, presentacion_id, codigo, tipo)
select p.tenant_id, p.id, pre.id, pg_temp.con_digito('1' || left(p.gtin, 12)), 'DUN14'
from public.productos p
join public.presentaciones pre on pre.producto_id = p.id and pre.nombre = 'Caja x 12'
where p.id::text like '00000000-0000-4000-b000-%' and p.gtin is not null
on conflict (tenant_id, codigo_busqueda) do nothing;

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
