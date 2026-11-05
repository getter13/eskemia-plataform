# Eskemia · Infraestructura: requisitos, entornos y resguardo

> Fecha: 04/11/2026. Decisiones de stack en `docs/adr/0002-supabase-self-hosted.md` y
> `docs/adr/0003-stack-y-lenguajes.md`.
>
> **Las versiones del compose de Supabase y sus requisitos cambian seguido. Reverificar
> contra la documentación oficial al momento de ejecutar el paso 1 de cada plan.**

---

## 1. Requisitos mínimos

### 1.1 Servidor de producción

Supabase lista como mínimo 4 GB de RAM, 2 núcleos y 40 GB de SSD, y como recomendado 8 GB,
4 núcleos y 80 GB. El stack arranca cerca de 2,5–3 GB antes de nuestros datos.

| Recurso | Mínimo | **Recomendado (lo que pido)** | Por qué |
|---|---|---|---|
| RAM | 4 GB | **8 GB** | Postgres necesita caché para el conjunto de trabajo. Con 4 GB el kernel empieza a matar contenedores (código de salida 137) |
| CPU | 2 núcleos | **4 vCPU** | Postgres, Realtime y el gateway compiten |
| Disco | 40 GB | **160 GB NVMe** | Base + archivo WAL + volumen de Storage + repositorio local de backup + imágenes |
| Red | — | IPv4 fija, 1 Gbps | La IP fija es necesaria para el DNS |

**Sobre el disco:** las fotos de remitos son el rubro que crece. Con 50 recepciones por día
y dos fotos cada una, se van cerca de 100 MB por día, unos 36 GB por año y por sede. Hay que
elegir un proveedor que permita **agregar un volumen** después, sin recrear el servidor.

**Sistema operativo: Ubuntu Server 24.04 LTS.** Soporte hasta 2029, es la plataforma con
mejor soporte oficial de Docker Engine y la más documentada para este stack. Debian 12 es
una alternativa válida y algo más liviana; cualquier otra agrega fricción sin beneficio.

**Región: la más cercana a Argentina** (São Paulo o Santiago antes que Estados Unidos, y
Estados Unidos antes que Europa). La PWA es offline-first, así que la latencia no bloquea la
operación, pero de 30 ms a 220 ms hay diferencia en cada escaneo que sí va al servidor.
Verificar además si algún cliente futuro tiene requisito legal de residencia de datos.

### 1.2 Entorno de desarrollo (máquina de Nico, Windows)

| Recurso | Requisito |
|---|---|
| RAM de la máquina | **16 GB** (el stack recortado pide 4–6 GB libres para Docker) |
| Disco libre | 40 GB |
| Software | WSL2 con Ubuntu 24.04, Docker Desktop con backend WSL2, Git, Node LTS |

**Dato crítico de rendimiento y permisos:** el proyecto y sobre todo el directorio
`volumes/` tienen que vivir **dentro del sistema de archivos de WSL2** (por ejemplo
`~/eskemia`), **no** en `/mnt/c/...`. Postgres sobre un bind mount de Windows da problemas
de permisos y de `fsync`, y el rendimiento cae. Desde Windows se accede por `\\wsl$`.

Hoy el repo está en `C:\Users\CHUWAKA\Eskemia plataform`. **Esto implica moverlo**, y es una
decisión tuya porque cambia tu forma de trabajar. Lo veo en el paso 1 del Plan B.

### 1.3 Dominio y red

| Elemento | Definición |
|---|---|
| Dominio | Propio, a definir (ejemplo: `eskemia.com.ar`) |
| Registro DNS | Un `A` al IPv4 del servidor |
| **Un solo origen** | `app.<dominio>` sirve la PWA **y** la API por prefijos de ruta |
| Studio | **Nunca público.** Solo `localhost`, por túnel SSH |
| Postgres | **Nunca público.** Sin puerto publicado, acceso por túnel SSH |
| TLS | Let's Encrypt automático vía el overlay oficial de Caddy |

**Por qué un solo origen y no `app.` + `api.`:** el cliente `supabase-js` agrega los
prefijos `/rest/v1`, `/auth/v1`, `/storage/v1` y `/realtime/v1` a la URL base. Si Caddy
rutea esos prefijos al gateway y todo lo demás a los archivos estáticos, queda **sin CORS,
con un solo certificado y una CSP mucho más estricta**. Verificar la lista completa de
prefijos al configurar.

### 1.4 Autenticación segura

Estado actual en `config.toml`: contraseña mínima de 6, sin requisitos, registro abierto,
sin confirmación. Eso no va a producción. Configuración objetivo:

| Parámetro | Valor | Motivo |
|---|---|---|
| Registro público | **Desactivado** | Es un ERP interno: los usuarios los crea un administrador |
| Largo mínimo de contraseña | **12** | 6 es indefendible en un sistema con datos de compras |
| Requisitos de contraseña | Activados | — |
| MFA (TOTP) | **Obligatorio** para administración y supervisión | Son los perfiles que validan recepciones y aprueban OC |
| Expiración de JWT | 3600 s o menos | Ya configurado |
| Rotación de refresh token | Activada | Ya configurada |
| Rate limits | Revisados para inicio de sesión y refresco | Freno a fuerza bruta |
| `service_role` | **Solo en el servidor**, nunca en el front | Ya se cumple |

**SMTP: lo evitamos.** Supabase lo marca como opcional, necesario para flujos reales de
registro. Con el registro cerrado y el reseteo de contraseña hecho por un administrador, no
hace falta, y nos saca un proveedor externo de encima. Si más adelante un cliente pide
autogestión de contraseña, se agrega.

**A leer antes de configurar:** el self-hosting actual usa claves de API nuevas y firma de
JWT asimétrica, con guía propia. Hay que leerla antes de generar secretos, porque esto
define cómo se emiten las claves.

---

## 2. Plan A · Servidor privado de producción

> No entra ningún dato real de cliente antes de completar la Fase 5 **con un restore
> probado**. Esa es la única condición no negociable de todo el plan.

### Fase 1 · Provisión y endurecimiento del sistema operativo

1. Contratar el VPS: Ubuntu Server 24.04 LTS, 8 GB, 4 vCPU, 160 GB NVMe, IPv4 fija, en la
   región más cercana a Argentina.
2. Crear un usuario no-root con `sudo`. Subir la clave pública SSH.
3. Endurecer SSH en `/etc/ssh/sshd_config`: `PermitRootLogin no`,
   `PasswordAuthentication no`, `KbdInteractiveAuthentication no`. Recargar el servicio.
   **Verificar que la sesión nueva entra antes de cerrar la actual.**
4. Firewall: `ufw default deny incoming`, `ufw allow 22,80,443`, `ufw enable`. Nada más.
   En particular, **nunca** 5432, 8000 ni 6543 abiertos a internet.
5. `fail2ban` para SSH.
6. Parches automáticos de seguridad: `unattended-upgrades`.
7. Zona horaria `America/Argentina/Buenos_Aires`, NTP activo, `swap` de 2 GB como red de
   contención del OOM killer.

### Fase 2 · Docker y el stack recortado

8. Instalar Docker Engine y el plugin Compose v2. Verificar `docker compose version`.
9. Clonar una release **fijada**, nunca `master`:
   ```bash
   git clone --depth 1 --branch self-hosted/vX.Y.Z https://github.com/supabase/supabase
   mkdir ~/eskemia-stack && cp -rf supabase/docker/. ~/eskemia-stack
   cd ~/eskemia-stack && cp .env.example .env
   printf 'ref=self-hosted/vX.Y.Z\n' > .supabase-version
   ```
   (Reverificar cuál es la última release `self-hosted/v*` al ejecutar.)
10. **Generar todos los secretos propios** con `openssl rand`: contraseña de Postgres,
    secreto JWT, claves de API, credenciales de Studio, `POOLER_TENANT_ID`. Guardarlos en
    un gestor de contraseñas. Permisos `chmod 600 .env`.
    > **Trampa crítica:** `POSTGRES_PASSWORD` se escribe en el volumen en el **primer**
    > arranque y no se vuelve a leer del `.env`. Si se cambia después, rompe todos los
    > servicios que conectan. **Hay que acertarlo la primera vez.**
11. Recortar el compose según el ADR 0003: quitar Edge Runtime, no habilitar el overlay de
    logs, y evaluar imgproxy. Dejar Postgres, Auth, PostgREST, Storage, Realtime,
    Supavisor, el gateway y Studio.
12. Fijar las versiones de imagen por tag exacto, no `latest`. Commitear
    `docker-compose.yml`, los overrides y `.env.example` documentado (el compose referencia
    del orden de 90 variables). **Nunca el `.env`.**
13. `docker compose up -d`, `docker compose ps`, revisar logs de cada servicio.

### Fase 3 · Dominio, TLS y proxy

14. Apuntar el registro `A` del dominio al IP del servidor.
15. Habilitar el overlay oficial de Caddy (`sh run.sh config add caddy` o equivalente en la
    release fijada). Verificar que emite el certificado.
16. Configurar el Caddyfile:
    - `/rest/*`, `/auth/*`, `/storage/*`, `/realtime/*` → gateway interno.
    - Todo lo demás → archivos estáticos de la PWA, con fallback a `index.html`.
    - Cabeceras de seguridad, que reemplazan a las de `vercel.json`: HSTS,
      `X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`, y una CSP
      con `frame-ancestors 'none'` y `default-src 'self'` (posible justamente porque es un
      solo origen).
    - `Cache-Control: no-cache` para `sw.js`.
17. Verificar que Studio y Postgres **no** responden desde afuera. Acceso por túnel:
    `ssh -L 8000:localhost:8000 usuario@servidor`.

### Fase 4 · Esquema y aplicación

18. Aplicar las 19 migraciones en orden. Cargar la semilla de permisos y roles.
    **No** cargar los seeds demo en producción.
19. Después de cada migración aplicada por fuera de PostgREST, **recargar la caché de
    esquema**: PostgREST no detecta DDL externo. `NOTIFY pgrst, 'reload schema';`
    Esto va en el procedimiento de despliegue, no es opcional.
20. Aplicar la configuración de autenticación de §1.4 por `.env` y reiniciar los
    contenedores afectados. Crear el primer usuario administrador y activarle MFA.
21. Compilar el front con `VITE_SUPABASE_URL=https://app.<dominio>` y la clave pública.
    Copiar `dist/` al directorio que sirve Caddy.
22. Correr el guion de prueba de punta a punta (`docs/guion-prueba-compras.md`) contra
    producción, **antes** de que haya datos reales.

### Fase 5 · Resguardo (bloqueante)

23. **Nivel 1, inmediato:** script nocturno con `pg_dump` por `docker exec`, `tar` del
    volumen de Storage, y copia de `.env` y del compose. Todo cifrado y subido fuera del
    servidor. RPO de 24 horas. Simple, robusto y verificable: esto se hace primero y
    funciona desde el día uno.
24. **Nivel 2, antes de datos reales de un cliente:** PITR con `pgBackRest`, dos
    repositorios en simultáneo (uno local para restaurar rápido, uno remoto cifrado), con
    archivado continuo de WAL. Detalle en §4.
25. **Probar un restore completo en un servidor descartable y documentar los tiempos
    reales.** Un backup que nunca se restauró no es un backup.
26. Monitoreo de los backups: última corrida exitosa, antigüedad del punto de recuperación
    más nuevo, tamaño y desvíos, espacio libre, fallas de subida.

### Fase 6 · Monitoreo y cierre

27. Prometheus y Grafana con alertas: contenedor caído, disco por encima del 80 %, backup
    con más de 26 horas, certificado por vencer, picos de error de autenticación.
28. Escribir `docs/runbook-operacion.md`: arranque y parada, actualización con versiones
    fijadas, aplicación de migraciones, restore, rotación de secretos, qué hacer ante
    caída.

### Checklist de salida de producción

- [ ] SSH solo por clave, sin root, firewall en tres puertos
- [ ] Postgres y Studio inaccesibles desde internet
- [ ] TLS con renovación automática, cabeceras de seguridad y CSP activas
- [ ] Registro cerrado, contraseña mínima 12, MFA en administración
- [ ] Secretos propios, `.env` fuera de git, versiones de imagen fijadas
- [ ] **Backup corriendo, copia fuera del servidor y restore probado y documentado**
- [ ] Alertas llegando a algún lado que mires
- [ ] Guion de prueba de punta a punta en verde

---

## 3. Plan B · Entorno de desarrollo local

El mismo compose que producción. Eso es lo que da la paridad.

1. **Decisión previa tuya:** mover el proyecto al sistema de archivos de WSL2
   (`~/eskemia`) por lo explicado en §1.2. Si preferís dejarlo en `C:\`, hay que usar
   volúmenes nombrados de Docker para los datos de Postgres en lugar del bind mount, con la
   contrapartida de que ahí sí `docker compose down -v` borra los datos.
2. Instalar WSL2 con Ubuntu 24.04 y Docker Desktop con backend WSL2. Asignarle a WSL2 un
   límite de memoria razonable en `.wslconfig` (6 GB).
3. Clonar el repo de Eskemia dentro de WSL2 y `npm install` en `app/`.
4. Copiar el mismo `docker-compose.yml` recortado y la misma release fijada que producción.
   Partir de `.env.example` con **secretos distintos** a los de producción.
5. `docker compose up -d`. Aplicar las 19 migraciones **y** los seeds demo
   (`seed-compras-demo.sql`, `seed-ordenes-demo.sql`).
6. `app/.env.local` apuntando a `http://localhost:8000` con la clave pública local.
   `npm run dev`.
7. Crear usuarios de prueba con distintos roles y verificar login, foto a Storage, lectura
   por escáner y una OC que aparezca en tiempo real en Pendientes.
8. Correr el guion de prueba completo.
9. **Dar de baja el proyecto de Supabase cloud.** No hay datos que migrar.

### Reglas del entorno local

- Los datos locales son **descartables**. Si se corrompen, se borra `volumes/` y se
  reconstruye desde migraciones y seeds. Eso tiene que doler cero, y es la prueba de que
  las migraciones son completas y portables.
- **Nunca** credenciales de producción en la máquina de desarrollo.
- **Nunca** `--remote` en los tests SQL. Corren contra el stack local y en CI contra un
  Postgres efímero.
- Toda migración se aplica primero local, después en producción.

> **Nota sobre staging:** con dos entornos no hay staging. Es aceptable mientras no haya
> clientes, sostenido por que las migraciones se prueban local y en CI. **Antes del primer
> cliente externo hay que agregar un tercer entorno**, que puede ser un VPS chico con el
> mismo compose.

---

## 4. Backups: ¿local o remoto?

**Los dos. No es una elección.** La regla de la industria son tres copias de los datos, en
al menos dos medios distintos, con al menos una fuera del entorno primario.

El razonamiento es corto: una copia **local** da restauración rápida, que es lo que importa
cuando alguien borra algo por error (el caso más frecuente). Una copia **remota** es la que
te salva cuando el problema es el servidor mismo: se muere el disco, el proveedor te
suspende la cuenta, o alguien entra y cifra todo. Si el único backup vive en la máquina que
falló, no tenés backup. `pgBackRest` soporta dos repositorios en simultáneo, así que se
cumple la regla desde un solo servidor.

### Qué se respalda (y lo que casi todos olvidan)

| Qué | Cómo | Frecuencia |
|---|---|---|
| Base de datos | `pgBackRest`: backup completo + WAL continuo | Completo semanal, incremental diario, WAL continuo |
| **Volumen de Storage** | `tar` cifrado del directorio de Storage | Diario |
| **Secretos y configuración** | `.env`, compose y Caddyfile, cifrados y guardados **aparte** | En cada cambio |
| Código fuente | Git, con un segundo remoto en nuestro propio servidor | En cada commit |

**Los dos del medio son los que se olvidan y los que duelen.** Un dump de base **no
incluye** los archivos de Storage: si se pierde ese volumen, quedan las recepciones sin las
fotos de los remitos ni las firmas, que es justamente la prueba documental del control. Y
sin el `.env`, un backup de base restaurado es inútil, porque ningún servicio puede
conectarse: esa copia va cifrada y separada del resto, porque es la llave de todo.

### Objetivos, que hay que fijar y no adivinar

| Objetivo | Nivel 1 (inmediato) | Nivel 2 (antes de datos reales) |
|---|---|---|
| RPO (datos que acepto perder) | 24 h | **5 minutos** |
| RTO (tiempo hasta volver) | A medir en el ensayo | **< 1 h** |

Los dos objetivos aplican a la **aplicación**, no a Postgres solo: si la base vuelve en 20
minutos pero las fotos tardan seis horas, no cumplimos.

### Cifrado y retención

- Repositorio cifrado con clave propia, generada con `openssl rand -base64 48` y guardada
  en el gestor de contraseñas, **nunca en el servidor junto al backup**.
- Retención: 7 diarios, 4 semanales, 12 mensuales. Se ajusta cuando sepamos el crecimiento
  real.
- La copia remota va a almacenamiento de objetos compatible con S3, o a un equipo tuyo. No
  importa el proveedor mientras esté cifrada antes de salir del servidor.

### Una aclaración necesaria

Replicar la base no es respaldarla. Una réplica copia al instante el borrado accidental,
el `update` mal hecho o los datos ya comprometidos. Los backups existen porque guardan
**puntos en el tiempo anteriores al error**.

### El ensayo de restore

**Mensual, agendado, sin excepciones.** Levantar un servidor descartable, restaurar base +
Storage + configuración, verificar que una recepción vieja abre con sus fotos y firmas, y
anotar cuánto tardó. Si el ensayo no se hace, el backup pasa a ser una suposición.

Me hago cargo del régimen: lo dejo escrito, armo los scripts y el monitoreo, y en cada
sesión en que toquemos infraestructura o esquema reviso que siga en pie. Lo que no puedo
hacer desde acá es ejecutarlo en tu servidor ni ver sus alertas, así que el ensayo mensual
y la atención a las alertas quedan de tu lado.

---

## 5. Lo que necesito de vos para arrancar

| # | Dato | Para qué |
|---|---|---|
| 1 | **RAM de tu máquina** | Si no llega a 16 GB, el Plan B cambia de forma |
| 2 | **¿Movemos el proyecto a WSL2?** | Paso 1 del Plan B, afecta tu forma de trabajar |
| 3 | **Dominio**: ¿ya lo tenés o hay que registrarlo? | Fases 3 y 4 del Plan A |
| 4 | **Proveedor de VPS**: ¿tenés preferencia, o lo evalúo yo con los criterios de §1.1? | Fase 1 |
| 5 | **Gestor de contraseñas** que uses | Los secretos se generan una sola vez y bien |

Con el punto 1 y el 2 arranco el Plan B solo, que es el que desbloquea todo el desarrollo.
El Plan A necesita los puntos 3, 4 y 5.
