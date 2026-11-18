// Único JavaScript del panel: botón "Copiar" del código de invitación. Se sirve como archivo propio
// (CSP script-src 'self') y es opcional: sin JS el botón no aparece y el código se puede seleccionar.
const String scriptCopiar = r'''
document.querySelectorAll('[data-copiar]').forEach(function (boton) {
  var origen = document.getElementById(boton.getAttribute('data-copiar'));
  if (!origen || !navigator.clipboard) return;
  boton.hidden = false;
  boton.addEventListener('click', function () {
    navigator.clipboard.writeText(origen.textContent.trim()).then(function () {
      var texto = boton.textContent;
      boton.textContent = boton.getAttribute('data-copiado');
      setTimeout(function () { boton.textContent = texto; }, 2000);
    });
  });
});
''';
