# Imagen del servidor de sincronización de On Budget.
# Fase actual: linux/amd64. arm64 (Raspberry Pi, NAS ARM) llegará después.

FROM dart:stable AS compilacion
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY . .
RUN dart pub get --offline && dart compile exe bin/onbudget_servidor.dart -o /app/onbudget-servidor

FROM debian:bookworm-slim
# libsqlite3: base de datos (con enlace libsqlite3.so, que es el nombre que abre el paquete sqlite3 de Dart); ca-certificates: por si en el futuro hay llamadas salientes; tini: señales y procesos
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates tini curl \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s "$(find /usr/lib -name 'libsqlite3.so.0' | head -n 1)" /usr/lib/libsqlite3.so \
    && useradd --system --uid 1000 --home /datos onbudget \
    && mkdir -p /datos && chown onbudget /datos

COPY --from=compilacion /app/onbudget-servidor /usr/local/bin/onbudget-servidor

ENV CARPETA_DATOS=/datos \
    PUERTO=8080 \
    DIRECCION=0.0.0.0
VOLUME /datos
EXPOSE 8080
USER onbudget

HEALTHCHECK --interval=60s --timeout=5s \
  CMD curl -fsk "$( [ -n "$TLS_CERTIFICADO" ] && echo https || echo http )://127.0.0.1:${PUERTO}/salud" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "onbudget-servidor"]
CMD ["servir"]
