class AppNumbers {
  // Timeouts (en segundos)
  static const int timeoutAPI = 8;
  static const int timeoutLargo = 15;
  static const int reintentos = 3;
  static const int delayReintento = 2; // segundos

  // Tamaños de UI
  static const double anchoBotonCategoria = 72;
  static const double altoBotonCategoria = 85;
  static const double radiusIconoCategoria = 26;
  static const double tamanoIconoCategoria = 24;
  static const double paddingStandard = 16;
  static const double paddingLargo = 24;
  static const double paddingCorto = 8;
  static const double paddingMedio = 12;

  // Barra superior: altura y tamaño común de los selectores centrados (Inversión, Presupuesto y Ahorro)
  static const double alturaBarraSuperior = 62;
  static const double altoSelectorBarra = 36;
  static const double anchoSelectorBarra = 240;

  // Velocidad (px/s) a partir de la cual un deslizamiento en la franja de botones cambia de pestaña
  static const double velocidadCambioPestana = 300;
  static const double tamanoBotonFlotante = 78.75; // Botones + / −: 87.5 reducido un 10%
  static const double tamanoIconoBotonFlotante = 33.75; // Icono: 37.5 reducido un 10%

  // Tamaños de fuente
  static const double fontSizeTitulo = 24;
  static const double fontSizeSaldo = 48;
  static const double fontSizePequeno = 11;
  static const double fontSizeNormal = 14;
  static const double fontSizeSubtitulo = 16;
  static const double fontSizeDetalle = 12; // Estados y notas bajo una cifra
  static const double fontSizeAyuda = 13; // Textos de ayuda bajo un título
  static const double fontSizeTituloSeccion = 18;

  // Valores de UI
  static const int maxCategoriasDefault = 8;
  static const int flexMultiplier = 1000; // para cálculos de flex en barras
  static const double radiusStandard = 8;
  static const double alturaBarra = 16;

  // Divisores de dinero
  static const int centimosEnEuro = 100;

  // Transparencias
  static const double opacityLigera = 0.1;
  static const double opacityMedia = 0.2;
  static const double opacityAlt = 0.5;
}
