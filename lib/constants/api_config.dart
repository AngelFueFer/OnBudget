class ApiConfig {
  // EODHD API Configuration
  static const String baseUrl = 'https://eodhd.com/api/real-time';
  static const String urlBusqueda = 'https://eodhd.com/api/search'; // Busca por nombre, ticker o ISIN

  // API timeout (seconds)
  static const int timeoutSegundos = 8;

  // Retry configuration
  static const int maxReintentos = 3;
  static const int delayReintentoMs = 2000; // 2 segundos
}

// Códigos de error personalizados
class ApiErrorCode {
  static const String timeout = 'TIMEOUT';
  static const String noConexion = 'NO_CONEXION';
  static const String statusCode = 'STATUS_CODE_ERROR';
  static const String parseo = 'PARSEO_ERROR';
  static const String datosFaltantes = 'DATOS_FALTANTES';
  static const String mercadoCerrado = 'MERCADO_CERRADO';
  static const String desconocido = 'ERROR_DESCONOCIDO';
}
