// Rellena los datos de config.js, el selector de tema y los botones de copiar. Sin rastreo ni cookies.
(function () {
  var datos = window.ON_BUDGET || {};
  var raiz = document.documentElement;

  // Tema: el elegido se recuerda solo en este navegador
  function aplicarTema(tema) {
    if (tema === 'claro' || tema === 'oscuro') raiz.setAttribute('data-tema', tema);
    else raiz.removeAttribute('data-tema');
    document.querySelectorAll('.tema button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.tema === (tema || 'auto')));
    });
  }
  var guardado = null;
  try { guardado = localStorage.getItem('tema'); } catch (e) {}
  aplicarTema(guardado);

  document.addEventListener('DOMContentLoaded', function () {
    aplicarTema(guardado);
    document.querySelectorAll('.tema button').forEach(function (b) {
      b.addEventListener('click', function () {
        var tema = b.dataset.tema === 'auto' ? null : b.dataset.tema;
        try { tema ? localStorage.setItem('tema', tema) : localStorage.removeItem('tema'); } catch (e) {}
        aplicarTema(tema);
      });
    });

    // Textos: <span data-dato="email">[EMAIL]</span>
    document.querySelectorAll('[data-dato]').forEach(function (el) {
      var valor = datos[el.dataset.dato];
      if (valor) el.textContent = valor;
    });

    // Correo: <a data-correo>…</a>
    document.querySelectorAll('a[data-correo]').forEach(function (el) {
      if (datos.email) { el.href = 'mailto:' + datos.email; el.textContent = datos.email; }
    });

    // Enlaces: <a data-enlace="paypal">…</a>; sin enlace queda desactivado con su texto alternativo
    document.querySelectorAll('a[data-enlace]').forEach(function (el) {
      var url = datos[el.dataset.enlace];
      if (url) {
        el.href = url;
        el.removeAttribute('aria-disabled');
        el.rel = 'noopener';
      } else {
        el.removeAttribute('href');
        el.setAttribute('aria-disabled', 'true');
        if (el.dataset.sinEnlace) el.textContent = el.dataset.sinEnlace;
      }
    });

    // Bloques que solo tienen sentido cuando existe el dato: <div data-si="paypal">
    document.querySelectorAll('[data-si]').forEach(function (el) {
      el.hidden = !datos[el.dataset.si];
    });
    document.querySelectorAll('[data-si-no]').forEach(function (el) {
      el.hidden = !!datos[el.dataset.siNo];
    });

    // Botones de copiar y contador de caracteres (límites de Play Console)
    document.querySelectorAll('.copiable').forEach(function (bloque) {
      var texto = bloque.querySelector('pre');
      var contador = bloque.querySelector('.contador');
      var limite = Number(bloque.dataset.limite || 0);
      if (contador) {
        var n = Array.from(texto.textContent.trim()).length;
        contador.textContent = limite ? n + ' / ' + limite : n + ' caracteres';
        if (limite && n > limite) contador.classList.add('mal');
      }
      var boton = bloque.querySelector('.copiar');
      if (boton) boton.addEventListener('click', function () {
        var valor = texto.textContent.trim();
        var hecho = function () { boton.textContent = 'Copiado'; setTimeout(function () { boton.textContent = 'Copiar'; }, 1500); };
        if (navigator.clipboard) navigator.clipboard.writeText(valor).then(hecho);
        else {
          var area = document.createElement('textarea');
          area.value = valor; document.body.appendChild(area); area.select();
          document.execCommand('copy'); area.remove(); hecho();
        }
      });
    });

    // Pestañas de idioma
    document.querySelectorAll('.pestanas').forEach(function (grupo) {
      var botones = grupo.querySelectorAll('button');
      botones.forEach(function (b) {
        b.addEventListener('click', function () {
          botones.forEach(function (o) {
            o.setAttribute('aria-selected', String(o === b));
            document.getElementById(o.dataset.panel).hidden = o !== b;
          });
        });
      });
    });
  });
})();

// En la galería, «Ver en grande» abre la captura del tema que se está viendo
document.addEventListener('click', function (e) {
  var marco = e.target.closest && e.target.closest('a.movil');
  if (!marco) return;
  var visible = Array.prototype.find.call(marco.querySelectorAll('img'), function (i) { return i.offsetParent !== null; });
  if (visible) marco.href = visible.getAttribute('src');
});
