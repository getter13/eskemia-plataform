#!/bin/sh
#
# Eskemia · Datos demo para el entorno LOCAL.
#
# Qué hace: crea (si no existe) la cuenta demo@eskemia.test con email confirmado, la
# organización "Demo" con esa cuenta como titular, y un catálogo mínimo (rubro, categoría,
# dos productos, un proveedor con precios) para probar Compras y Recepción en la app.
# Todo por las RPC del esquema api, actuando como la cuenta demo.
# Dónde encaja: después de db/scripts/reset.sh o aplicar.sh. NUNCA en producción: se niega
# si ESKEMIA_ENTORNO=produccion. La contraseña es solo de desarrollo y vive acá a la vista.
#
# Uso: sh db/scripts/demo.sh
# Ingreso en la app: demo@eskemia.test / eskemia-demo-local

set -e
. "$(dirname "$0")/comun.sh"

if [ "${ESKEMIA_ENTORNO:-}" = "produccion" ]; then
    echo "Error: demo.sh no corre en producción." >&2
    exit 1
fi

psql_admin <<'SQL'
-- Cuenta demo con email confirmado (el trigger de nucleo crea su fila en cuentas).
do $$
declare
  v_id constant uuid := 'd0000000-0000-4000-8000-000000000001';
begin
  if not exists (select 1 from auth.users where id = v_id) then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change, email_change_token_new)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
            'demo@eskemia.test', extensions.crypt('eskemia-demo-local', extensions.gen_salt('bf')), now(),
            '{"provider": "email", "providers": ["email"]}', '{"nombre": "Demo", "apellido": "Eskemia"}',
            now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at, last_sign_in_at)
    values (gen_random_uuid(), v_id, v_id::text, 'email',
            jsonb_build_object('sub', v_id::text, 'email', 'demo@eskemia.test', 'email_verified', true),
            now(), now(), now());
  end if;
end;
$$;
SQL

psql_db <<'SQL'
-- Organización y catálogo, por RPC y con el JWT de la cuenta demo.
select set_config('request.jwt.claims', '{"sub": "d0000000-0000-4000-8000-000000000001", "role": "authenticated"}', false);
do $$
declare
  v_org uuid := (select m.organizacion_id from nucleo.membresias m
                 where m.cuenta_id = 'd0000000-0000-4000-8000-000000000001' limit 1);
  v_rubro uuid;
  v_cat uuid;
  v_leche uuid;
  v_yerba uuid;
  v_prov uuid;
begin
  if v_org is not null then
    raise notice 'La organización Demo ya existe: no se toca.';
    return;
  end if;
  v_org := (api.crear_organizacion('Demo', 'Organización de prueba local') ->> 'id')::uuid;
  update nucleo.sedes set codigo = 'DEM' where organizacion_id = v_org;
  v_rubro := api.guardar_rubro(v_org, gen_random_uuid(), 'Almacén');
  v_cat := api.guardar_categoria(v_org, gen_random_uuid(), v_rubro, 'Secos');
  v_leche := api.guardar_producto(v_org, gen_random_uuid(), v_cat, 'Leche entera', 'UN');
  v_yerba := api.guardar_producto(v_org, gen_random_uuid(), v_cat, 'Yerba mate', 'UN');
  v_prov := api.guardar_proveedor(v_org, gen_random_uuid(), 'Distribuidora Demo', '30999999991');
  perform api.guardar_codigo(v_org, gen_random_uuid(), v_leche,
    (select p.id from api.presentaciones p where p.producto_id = v_leche), '7790000000010', 'EAN13');
  perform api.guardar_producto_proveedor(v_org, gen_random_uuid(), v_leche, v_prov,
    (select p.id from api.presentaciones p where p.producto_id = v_leche), 1240.50, null, true);
  perform api.guardar_producto_proveedor(v_org, gen_random_uuid(), v_yerba, v_prov,
    (select p.id from api.presentaciones p where p.producto_id = v_yerba), 3890, null, true);
  raise notice 'Organización Demo creada.';
end;
$$;
SQL

echo "Listo. Ingresá en la app con demo@eskemia.test / eskemia-demo-local"
