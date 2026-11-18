class DBKeys {
  // SharedPreferences keys
  static const String modoOscuro = 'modoOscuro';
  static const String esPrimeraVez = 'esPrimeraVez';
  static const String gastoMensual = 'gastoMensual';
  static const String nominaMensual = 'nominaMensual';
  static const String diaCobro = 'diaCobro';
  static const String ultimoMesNomina = 'ultimoMesNomina';
  static const String gastosFijos = 'gastosFijos';
  static const String categoriasJson = 'categorias_json';
  static const String idioma = 'idioma';
  static const String permisoNotificaciones = 'permisoNotificaciones';
  static const String tasaAhorro = 'tasaAhorro'; // Interés anual (TAE %) del ahorro
  static const String moneda = 'moneda'; // Código ISO: EUR, USD, GBP, CNY, JPY
  static const String tarjetas = 'tarjetas'; // Lista JSON con los nombres de las tarjetas
  static const String tarjetasDetectadas = 'tarjetasDetectadas'; // Propuestas por la lectura de notificaciones
  static const String tarjetasDescartadas = 'tarjetasDescartadas'; // Propuestas que el usuario rechazó
  static const String ultimoMetodoPago = 'ultimoMetodoPago';
  static const String ultimaTarjeta = 'ultimaTarjeta';
  static const String conexionMercados = 'conexionMercados'; // Conexión con los servidores de bolsa activada
  static const String claveApiMercados = 'claveApiMercados'; // Clave de EODHD del usuario (obligatoria para conectar)
  static const String cuentasAhorro = 'cuentasAhorro'; // Lista JSON de cuentas bancarias (corrientes y de ahorro)
  static const String historialSaldos = 'historialSaldos'; // JSON {idCuenta: [{fecha, saldo}]}
  static const String pagosDetectados = 'pagosDetectados'; // Pagos leídos de notificaciones bancarias, pendientes de confirmar
  static const String pagosGestionados = 'pagosGestionados'; // Pagos ya confirmados o descartados (para no volver a proponerlos)
  static const String limitesEfectivo = 'limitesEfectivo'; // JSON {"AAAA-MM": importe} por periodo
  static const String limiteEfectivoPreguntado = 'limiteEfectivoPreguntado'; // Último periodo en que se pidió
  static const String idDispositivo = 'idDispositivo'; // uuid de este dispositivo (sincronización), nunca se comparte entre móviles
  static const String colorAcento = 'colorAcento'; // Clave de AppStrings.acento* elegida en Temas
  static const String modoAlmacenamiento = 'modoAlmacenamiento'; // AppStrings.almacenamientoLocal / almacenamientoServidor
  static const String urlServidor = 'urlServidor'; // URL del servidor propio (sincronización en desarrollo)
  // Conexión con los bancos (Open Banking)
  static const String proveedorBancario = 'proveedorBancario'; // TipoProveedor.name
  static const String idAplicacionBancaria = 'idAplicacionBancaria'; // Application ID del agregador
  static const String clavePrivadaBancaria = 'clavePrivadaBancaria'; // PEM de la clave privada de la aplicación
  static const String urlVueltaBancaria = 'urlVueltaBancaria'; // URL a la que vuelve el banco tras autorizar
  static const String paisBancario = 'paisBancario'; // País de los bancos que se listan (ES)

  // Database
  static const String nombreBaseDatos = 'presupuesto.db';

  // Database table names
  static const String tableTransacciones = 'transacciones';
  static const String tableActivos = 'activos_financieros';
  static const String tableCambiosPendientes = 'cambios_pendientes'; // Cola de cambios locales aún no enviados al servidor

  // Database column names
  static const String columnId = 'id';
  static const String columnMonto = 'montoEnCentimos';
  static const String columnConcepto = 'concepto';
  static const String columnFecha = 'fecha';
  static const String columnCategoria = 'categoria';
  static const String columnEsIngreso = 'esIngreso';
  static const String columnTarro = 'tarroDestino';
  static const String columnMetodoPago = 'metodoPago';
  static const String columnTarjeta = 'tarjeta';
  static const String columnCuentaAhorro = 'cuentaAhorro'; // id de la cuenta de ahorro (solo movimientos de Ahorro)
  static const String columnTiquet = 'tiquet'; // Nombre del archivo con la foto del tiquet (carpeta de la app)
  static const String columnTicker = 'ticker';
  static const String columnCantidad = 'cantidad';
  static const String columnPrecioCompra = 'precioCompra';
  static const String columnTipo = 'tipo'; // Tipo de inversión (AppStrings.tiposInversion)
  static const String columnNombre = 'nombre'; // Nombre que el usuario le da al activo
  static const String columnIsin = 'isin';
  static const String columnUltimoValor = 'ultimoValor';

  // Columnas de sincronización (v6), comunes a las tablas sincronizables
  static const String columnUuid = 'uuid'; // Identificador global de la fila (igual en todos los dispositivos)
  static const String columnRelojes = 'relojes'; // JSON {campo: reloj híbrido} de la última escritura de cada campo
  static const String columnModificado = 'modificado'; // Reloj más reciente de la fila (para consultas y orden)
  static const String columnBorrado = 'borrado'; // 1 = borrada; se conserva para que el borrado llegue al resto de móviles
  static const String columnDispositivo = 'dispositivo'; // Último dispositivo que la modificó (base para roles)
  static const String columnEntidad = 'entidad'; // Tabla a la que pertenece un cambio pendiente
  static const String columnReloj = 'reloj';
}
