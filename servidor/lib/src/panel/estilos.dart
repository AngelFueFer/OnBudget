// Hoja de estilos del panel. Mismo acento que la app (AppColors.acentoAzul, el azul del logo) y tonos
// al estilo Material 3; tema claro u oscuro según el sistema o la elección guardada (data-tema en <html>).
// Se sirve como archivo para no necesitar 'unsafe-inline'. Contrastes comprobados para WCAG AA (4,5:1).
const String estilosPanel = r'''
:root {
  --acento: #147AA3;
  --acento-texto: #0F6A8F;
  --sobre-acento: #FFFFFF;
  --acento-tenue: #E1F1F8;
  --cabecera: #147AA3;
  --fondo: #F5F7F8;
  --superficie: #FFFFFF;
  --texto: #1B1F23;
  --suave: #5F6B73;
  --borde: #DDE3E7;
  --error: #C62828;
  --error-tenue: #FDECEC;
  --aviso: #8A5300;
  --aviso-tenue: #FFF4E0;
  --exito: #2E7D32;
  --exito-tenue: #E8F5E9;
  --neutro-tenue: #ECEFF1;
  color-scheme: light;
}
/* Oscuro: el mismo bloque dos veces, por preferencia del sistema y por elección manual */
@media (prefers-color-scheme: dark) {
  :root:not([data-tema="claro"]) {
    --acento: #8CCBEA;
    --acento-texto: #8CCBEA;
    --sobre-acento: #00344A;
    --acento-tenue: #12313F;
    --cabecera: #0F5E7E;
    --fondo: #101415;
    --superficie: #1A2023;
    --texto: #E7ECEE;
    --suave: #9AA7AE;
    --borde: #2C3539;
    --error: #EF9A9A;
    --error-tenue: #3A1F1F;
    --aviso: #FFCC80;
    --aviso-tenue: #3A2E1A;
    --exito: #A5D6A7;
    --exito-tenue: #1F3321;
    --neutro-tenue: #262E32;
    color-scheme: dark;
  }
}
:root[data-tema="oscuro"] {
  --acento: #8CCBEA;
  --acento-texto: #8CCBEA;
  --sobre-acento: #00344A;
  --acento-tenue: #12313F;
  --cabecera: #0F5E7E;
  --fondo: #101415;
  --superficie: #1A2023;
  --texto: #E7ECEE;
  --suave: #9AA7AE;
  --borde: #2C3539;
  --error: #EF9A9A;
  --error-tenue: #3A1F1F;
  --aviso: #FFCC80;
  --aviso-tenue: #3A2E1A;
  --exito: #A5D6A7;
  --exito-tenue: #1F3321;
  --neutro-tenue: #262E32;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--fondo);
  color: var(--texto);
  font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

/* Enlaces y foco: siempre con el acento, también en oscuro */
a { color: var(--acento-texto); text-decoration: none; }
a:hover { text-decoration: underline; }
a:focus-visible, button:focus-visible, input:focus-visible, summary:focus-visible {
  outline: 2px solid var(--acento);
  outline-offset: 2px;
}

/* Cabecera: logo, título y menú. En móvil el menú baja a su propia fila y se desplaza en horizontal */
header {
  background: var(--cabecera);
  color: #fff;
  padding: 10px 16px;
  display: flex;
  flex-wrap: wrap;
  column-gap: 16px;
  row-gap: 4px;
  align-items: center;
}
header .marca {
  display: flex;
  align-items: center;
  gap: 10px;
  font-weight: 700;
  font-size: 17px;
  margin-right: auto;
  color: #fff;
}
header .marca:hover { text-decoration: none; }
header .marca img { width: 32px; height: 32px; display: block; }
header nav { display: flex; align-items: center; gap: 4px; overflow-x: auto; max-width: 100%; }
header nav a, header nav button.enlace {
  color: #fff;
  opacity: .88;
  padding: 8px 10px;
  border-radius: 20px;
  white-space: nowrap;
  min-height: 40px;
  display: inline-flex;
  align-items: center;
}
header nav a:hover, header nav button.enlace:hover { opacity: 1; background: rgba(255, 255, 255, .14); text-decoration: none; }
header nav a[aria-current="page"] { opacity: 1; font-weight: 600; background: rgba(255, 255, 255, .22); }
header a:focus-visible, header button:focus-visible { outline-color: #fff; }
@media (max-width: 640px) {
  header nav { width: 100%; }
}

main { max-width: 960px; margin: 0 auto; padding: 16px; }
h1 { font-size: 22px; margin: 8px 0 16px; display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
h2 { font-size: 17px; margin: 28px 0 10px; }
.volver { margin: 4px 0 0; }

.tarjeta {
  background: var(--superficie);
  border: 1px solid var(--borde);
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 16px;
}
.separada { margin-top: 16px; }
.cifras { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; }
.cifra { background: var(--superficie); border: 1px solid var(--borde); border-radius: 12px; padding: 12px 16px; }
.cifra .valor { font-size: 26px; font-weight: 700; color: var(--acento-texto); line-height: 1.3; }
.cifra .etiqueta { color: var(--suave); font-size: 13px; }

table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--borde); vertical-align: middle; }
tr:last-child > td, tr:last-child > th { border-bottom: 0; }
th { color: var(--suave); font-weight: 600; font-size: 13px; }
td.accion { text-align: right; white-space: nowrap; }
.tabla { overflow-x: auto; padding: 4px 16px; }
code, .codigo { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; word-break: break-all; }
.id-corto { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
.detalle { color: var(--suave); font-size: 13px; }
details summary { cursor: pointer; color: var(--suave); font-size: 13px; }

/* Código de invitación */
.codigo-grande {
  display: block;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 26px;
  letter-spacing: 2px;
  padding: 12px;
  margin: 8px 0;
  text-align: center;
  border: 2px dashed var(--acento);
  border-radius: 12px;
  user-select: all;
}
.fila-acciones { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 8px 0; }

/* Botones al estilo Material 3: relleno, contorno y peligro; 40 px de alto para tocar bien */
form.linea { display: inline; margin: 0; }
button, .boton {
  font: inherit;
  font-weight: 500;
  border: 1px solid transparent;
  border-radius: 20px;
  padding: 8px 20px;
  min-height: 40px;
  background: var(--acento);
  color: var(--sobre-acento);
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  text-decoration: none;
}
button:hover, .boton:hover { filter: brightness(1.08); text-decoration: none; }
button:active, .boton:active { filter: brightness(.94); }
button.secundario, .boton.secundario { background: transparent; color: var(--acento-texto); border-color: var(--acento); }
button.secundario:hover, .boton.secundario:hover { background: var(--acento-tenue); filter: none; }
button.peligro { background: var(--error); color: var(--superficie); }
button.enlace { background: none; padding: 0; border: 0; border-radius: 0; min-height: 0; font-weight: inherit; }
button[hidden] { display: none; }

input[type=password], input[type=text] {
  font: inherit;
  width: 100%;
  padding: 10px 12px;
  border-radius: 8px;
  border: 1px solid var(--borde);
  background: var(--fondo);
  color: var(--texto);
  margin: 6px 0 12px;
}
input[type=checkbox] { width: 18px; height: 18px; margin: 2px 0 0; accent-color: var(--error); flex: none; }
label.casilla { display: flex; gap: 10px; align-items: flex-start; margin: 4px 0 14px; }

/* Avisos con icono y fondo tintado, como los de la app */
.mensaje {
  display: flex;
  gap: 10px;
  align-items: flex-start;
  padding: 12px 14px;
  border-radius: 12px;
  margin-bottom: 16px;
  border: 1px solid;
}
.mensaje::before { font-weight: 700; flex: none; width: 20px; height: 20px; border-radius: 50%; display: inline-flex;
  align-items: center; justify-content: center; font-size: 13px; color: var(--superficie); }
.mensaje.error { color: var(--error); border-color: var(--error); background: var(--error-tenue); }
.mensaje.error::before { content: "!"; background: var(--error); }
.mensaje.aviso { color: var(--aviso); border-color: var(--aviso); background: var(--aviso-tenue); }
.mensaje.aviso::before { content: "!"; background: var(--aviso); }
.mensaje.exito { color: var(--exito); border-color: var(--exito); background: var(--exito-tenue); }
.mensaje.exito::before { content: "✓"; background: var(--exito); }

/* Etiquetas de estado (chips) */
.chip {
  display: inline-block;
  font-size: 13px;
  font-weight: 600;
  line-height: 1;
  padding: 6px 10px;
  border-radius: 8px;
  white-space: nowrap;
}
.chip.activo { color: var(--exito); background: var(--exito-tenue); }
.chip.inactivo { color: var(--suave); background: var(--neutro-tenue); }

/* Estados vacíos */
.vacio { text-align: center; padding: 28px 16px; }
.vacio .icono { font-size: 28px; line-height: 1; margin-bottom: 8px; color: var(--suave); }
.vacio p { color: var(--suave); margin: 0 0 12px; }

.suave { color: var(--suave); }
.peligro-titulo { color: var(--error); }

/* Entrada */
.entrada { max-width: 400px; margin: 56px auto; text-align: center; }
.entrada img { width: 72px; height: 72px; display: block; margin: 0 auto 8px; }
.entrada h1 { justify-content: center; margin: 0; }
.entrada form { text-align: left; }
.entrada button { width: 100%; }
.entrada .ayuda { font-size: 13px; color: var(--suave); margin: 0 0 4px; }

footer { text-align: center; color: var(--suave); font-size: 13px; padding: 24px 16px; }
footer a { color: inherit; text-decoration: underline; margin: 0 4px; display: inline-block; padding: 4px 0; }
footer .grupo { display: inline-block; margin: 0 8px; }
footer strong { margin: 0 4px; }
''';
