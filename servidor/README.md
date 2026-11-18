# On Budget · servidor de sincronización

Servidor autoalojado para sincronizar On Budget entre varios dispositivos, al estilo de Vaultwarden. Lo montas tú, en tu máquina, y la app solo se conecta a él si eliges «Conectar a mi servidor» al empezar.

- **No ve tus datos.** La app cifra todo en el móvil antes de enviarlo (Argon2id + XChaCha20-Poly1305). El servidor guarda bloques cifrados, números de orden y fechas de recepción.
- **No recibe tu contraseña.** La app manda una huella derivada de ella, y el servidor solo guarda un hash de esa huella.
- **Sin registro abierto.** Para crear una bóveda hace falta un código de invitación que generas tú por comandos.
- **Un único archivo de datos**: `datos/onbudget.sqlite3`.

> Nota: cuando llegue la fase de tiquets con OCR, las fotos de los tiquets serán la única excepción. El servidor tendrá que verlas para transcribirlas, y la app lo avisará.

## Requisitos

- Docker con Docker Compose, en una máquina **amd64** (PC, NAS Intel/AMD o VPS). La imagen arm64 (Raspberry Pi) llegará más adelante.
- Una forma de servir **HTTPS**: un dominio propio con Nginx, o Tailscale. La app no se conecta por HTTP sin cifrar.

## 1. Arrancar el servidor

Solo necesitas el archivo `docker-compose.yml` de esta carpeta. Usa la imagen ya compilada que publica GitHub (`ghcr.io/angelfuefer/onbudget-servidor`), así que no hace falta compilar nada.

```bash
mkdir -p ~/onbudget && cd ~/onbudget
# copia aquí docker-compose.yml
mkdir -p datos && sudo chown 1000:1000 datos   # el servidor corre como usuario 1000
docker compose up -d
docker compose logs -f          # debe decir "escuchando en http://0.0.0.0:8080"
```

> Mientras el repositorio sea privado, la imagen también lo es. Antes del primer `docker compose up`, entra con `docker login ghcr.io -u <tu-usuario-de-github>` usando como contraseña un token de GitHub con el permiso `read:packages`. Si prefieres compilarla tú, en `docker-compose.yml` comenta `image:` y descomenta `build: .` (entonces necesitas la carpeta `servidor/` entera).

El servidor queda en `http://127.0.0.1:8080`, solo accesible desde la propia máquina. El paso 2 lo publica con HTTPS.

## 2. Ponerle HTTPS (elige una opción)

Igual que Vaultwarden, el servidor habla HTTP y delante se pone algo que gestione el certificado.

### Opción A · Dominio propio con Nginx

Necesitas un dominio (o subdominio) que apunte a la IP de tu casa o de tu VPS, y los puertos 80 y 443 abiertos.

1. Pide el certificado con Let's Encrypt:

   ```bash
   sudo apt install nginx certbot python3-certbot-nginx
   sudo certbot certonly --nginx -d presupuesto.midominio.com
   ```

2. Crea `/etc/nginx/sites-available/onbudget`:

   ```nginx
   server {
       listen 80;
       server_name presupuesto.midominio.com;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       server_name presupuesto.midominio.com;

       ssl_certificate     /etc/letsencrypt/live/presupuesto.midominio.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/presupuesto.midominio.com/privkey.pem;

       # Tamaño máximo de una subida (debe cuadrar con MAX_MB_CUERPO)
       client_max_body_size 25m;

       location / {
           proxy_pass http://127.0.0.1:8080;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

3. Actívalo y prueba:

   ```bash
   sudo ln -s /etc/nginx/sites-available/onbudget /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   curl https://presupuesto.midominio.com/salud
   ```

   Certbot renueva el certificado él solo.

En la app, la URL del servidor es `https://presupuesto.midominio.com`.

### Opción B · Tailscale (sin dominio ni puertos abiertos)

El servidor solo es accesible desde tus dispositivos de Tailscale y no se abre nada a internet. Tailscale da un certificado HTTPS válido para el nombre `*.ts.net` de la máquina.

1. Instala Tailscale en el servidor y en los móviles, con la misma cuenta.
2. En la [consola de Tailscale](https://login.tailscale.com/admin/dns), activa **MagicDNS** y **HTTPS Certificates**.
3. En el servidor, publica el puerto 8080 con HTTPS:

   ```bash
   sudo tailscale serve --bg --https=443 http://127.0.0.1:8080
   tailscale serve status          # muestra la URL, p. ej. https://mi-servidor.mi-red.ts.net
   ```

En la app, la URL del servidor es la que muestra `tailscale serve status`. El tráfico de Tailscale ya va cifrado de extremo a extremo y, además, el certificado es válido.

### Opción C · HTTPS en el propio servidor (sin proxy)

Si ya tienes un certificado (por ejemplo de `tailscale cert` o de certbot), el servidor puede servir HTTPS directamente. Descomenta en `docker-compose.yml`:

```yaml
    environment:
      TLS_CERTIFICADO: /certificados/fullchain.pem
      TLS_CLAVE: /certificados/privkey.pem
    volumes:
      - ./certificados:/certificados:ro
```

Con esta opción, el servidor no renueva el certificado: cuando lo renueves, reinicia el contenedor.

## 3. Crear usuarios

Cada persona tiene su propio usuario, con su nombre y su contraseña maestra. Para dar de alta a alguien, crea un código de invitación de un solo uso:

```bash
docker compose exec onbudget onbudget-servidor invitacion crear
# Código de invitación (un solo uso): ABCD-EFGH-JKLM-NPQR
```

En la app elige **Conectar a mi servidor → Crear cuenta en mi servidor** y escribe la URL, el código, un nombre de usuario (de 3 a 32 letras minúsculas, números, `.`, `_` o `-`) y una contraseña maestra. Para entrar desde otro dispositivo basta con el nombre y la contraseña, sin invitación.

> La pantalla de la app para conectarse al servidor llegará en una próxima versión; de momento el servidor ya está listo para recibirla.

> La contraseña maestra no se puede recuperar. Ni el servidor ni quien lo administra la conocen, y sin ella los datos no se pueden descifrar.

### Presupuestos compartidos y permisos

Cada presupuesto vive en una **bóveda**. Quien la crea es su propietario y puede compartirla con otros usuarios del servidor, eligiendo el permiso de cada uno:

| Permiso | Puede |
| --- | --- |
| Solo consulta | Ver el presupuesto |
| Consulta y escritura | Ver y apuntar gastos, ingresos, ahorros… |
| Propietario | Todo lo anterior, compartir, cambiar permisos y borrar la bóveda |

El servidor hace cumplir estos permisos y una bóveda nunca se queda sin propietario. Al compartir, la app cifra la clave de la bóveda con la clave pública del otro usuario, así que el servidor sigue sin poder leer nada. Si quitas a alguien de una bóveda deja de recibir datos nuevos, pero conserva lo que ya había descargado.

Quien administra el servidor (el panel y los comandos) gestiona usuarios, dispositivos y bóvedas, pero no puede ver importes ni conceptos ni entrar en los presupuestos.

## Panel de administración web (`/admin`)

Igual que en Vaultwarden, hay un panel web en `https://tu-servidor/admin` para ver el estado, crear y anular invitaciones, ver los usuarios y sus dispositivos, cerrar la sesión de un móvil perdido, desactivar o borrar un usuario, y ver quién comparte cada bóveda o borrarla. Está en español, inglés, francés y alemán, con tema claro y oscuro.

Viene **desactivado**. Para activarlo:

1. Genera el hash de la contraseña del panel (mínimo 12 caracteres):

   ```bash
   docker compose run --rm onbudget admin hash
   # $pbkdf2-sha256$600000$...
   ```

2. Ponlo en `docker-compose.yml`, en `ADMIN_TOKEN`, escribiendo **cada `$` como `$$`** (Docker Compose interpreta `$`):

   ```yaml
       environment:
         ADMIN_TOKEN: $$pbkdf2-sha256$$600000$$...
   ```

3. `docker compose up -d` y entra en `/admin` con la contraseña.

También se acepta la contraseña en texto plano, pero el panel avisará para que la cambies por el hash. La sesión del panel caduca tras 20 minutos sin uso, y los intentos fallidos se bloquean igual que en la app. Desde el panel no se ven importes ni conceptos: el servidor solo guarda datos cifrados.

## Comandos de administración

Todos se lanzan con `docker compose exec onbudget onbudget-servidor <comando>`:

| Comando | Para qué |
| --- | --- |
| `invitacion crear` | Código de un solo uso para dar de alta un usuario |
| `invitacion anular` | Anula los códigos que no se han usado |
| `usuarios listar` | Usuarios, su estado, sus bóvedas y sus dispositivos |
| `usuarios desactivar <nombre>` | Le impide entrar y cierra sus sesiones (no borra nada) |
| `usuarios activar <nombre>` | Vuelve a permitirle entrar |
| `usuarios borrar <nombre>` | Borra el usuario y las bóvedas de las que es el único propietario |
| `bovedas listar` | Bóvedas, miembros y número de cambios |
| `bovedas borrar <id>` | Borra una bóveda y todos sus datos (no se puede deshacer) |
| `dispositivos listar <usuario>` | Dispositivos de un usuario y su último acceso |
| `dispositivos revocar <usuario> <id>` | Cierra la sesión de un móvil perdido |
| `admin hash [contraseña]` | Genera el hash para `ADMIN_TOKEN` |
| `ayuda` | Muestra la ayuda |

## Variables de entorno

| Variable | Por defecto | Qué hace |
| --- | --- | --- |
| `PUERTO` | `8080` | Puerto en el que escucha |
| `DIRECCION` | `0.0.0.0` | Interfaz en la que escucha dentro del contenedor |
| `CARPETA_DATOS` | `/datos` | Dónde se guarda `onbudget.sqlite3` |
| `TLS_CERTIFICADO`, `TLS_CLAVE` | — | HTTPS propio (opción C); hacen falta las dos |
| `MAX_MB_CUERPO` | `25` | Tamaño máximo de una petición |
| `CABECERA_IP` | `X-Real-IP` | Cabecera con la IP real del cliente, para frenar intentos de adivinar la contraseña |
| `ADMIN_TOKEN` | — | Activa el panel `/admin` (mejor el hash de `admin hash`) |

## Copias de seguridad y actualizaciones

- **Copia**: con el servidor parado, copia la carpeta `datos/`. En marcha, usa `sqlite3 datos/onbudget.sqlite3 ".backup copia.sqlite3"`. Los datos ya van cifrados, pero guarda la copia en un sitio seguro igualmente.
- **Actualizar**: `docker compose pull && docker compose up -d` (o `git pull && docker compose up -d --build` si la compilas tú). El esquema de la base de datos se actualiza solo al arrancar.

## API (para la app)

Todas las respuestas son JSON. Los errores tienen la forma `{"error": "<código>"}` y las rutas con sesión piden `Authorization: Bearer <token>`.

| Método y ruta | Sesión | Qué hace |
| --- | --- | --- |
| `GET /salud` | No | Estado, versión del servidor y versión de la API |
| `POST /v2/usuarios` | No | Da de alta un usuario con un código de invitación y devuelve el token |
| `GET /v2/usuarios/{nombre}/kdf` | No | Parámetros de Argon2id para derivar la clave (no revela si el usuario existe) |
| `POST /v2/sesion` | No | Inicia sesión con la huella de acceso y devuelve el token y las claves cifradas |
| `DELETE /v2/sesion` | Sí | Cierra la sesión de este dispositivo |
| `GET /v2/yo` | Sí | Datos del usuario y sus bóvedas con su permiso |
| `DELETE /v2/yo` | Sí | Borra la cuenta (pide de nuevo la huella de acceso) |
| `GET /v2/usuarios/{nombre}/clave-publica` | Sí | Clave pública de otro usuario, para compartir con él |
| `GET /v2/dispositivos` | Sí | Dispositivos del usuario |
| `DELETE /v2/dispositivos/{id}` | Sí | Revoca un dispositivo |
| `GET`/`POST /v2/bovedas` | Sí | Lista las bóvedas del usuario o crea una |
| `DELETE /v2/bovedas/{id}` | Propietario | Borra la bóveda (pide de nuevo la huella de acceso) |
| `GET /v2/bovedas/{id}/miembros` | Miembro | Miembros y permisos |
| `PUT /v2/bovedas/{id}/miembros/{nombre}` | Propietario | Añade un miembro o cambia su permiso (`lectura`, `escritura`, `propietario`) |
| `DELETE /v2/bovedas/{id}/miembros/{nombre}` | Propietario o uno mismo | Quita a un miembro o se sale de la bóveda |
| `POST /v2/bovedas/{id}/cambios` | Escritura | Sube hasta 500 paquetes cifrados de 1 MB como máximo cada uno |
| `GET /v2/bovedas/{id}/cambios?desde=N&limite=M` | Miembro | Descarga los cambios posteriores a N, por páginas |
| `GET /v2/bovedas/{id}/instantanea` | Miembro | Copia completa cifrada |
| `PUT /v2/bovedas/{id}/instantanea` | Escritura | Sube la copia completa; se descarta el historial anterior |

Quien no es miembro de una bóveda recibe `404`, igual que si no existiera.

## Desarrollo

```bash
cd servidor
dart pub get
dart test
dart run bin/onbudget_servidor.dart ayuda
CARPETA_DATOS=./datos dart run bin/onbudget_servidor.dart servir
```
