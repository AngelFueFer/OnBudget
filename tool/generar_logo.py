"""Genera el logo de la app y todos los iconos de plataforma.

Uso (desde la raíz del proyecto):
    python tool/generar_logo.py

Concepto: una casa (economía doméstica) cuya ventana es un gráfico de
anillo con el presupuesto repartido por categorías. Fondo azul aguamarina con
degradado, estilo plano y amable.
Para cambiar colores o proporciones, edita las constantes de abajo y
vuelve a ejecutar el script.
"""
import json
import math
import os

from PIL import Image, ImageDraw

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fondo del logo: degradado en tonos de azul aguamarina (solo afecta al logo/iconos,
# no a los colores de la app definidos en lib/constants/app_colors.dart)
AZUL_CLARO = (0x3D, 0xD6, 0xC6)
AZUL_OSCURO = (0x14, 0x7A, 0xA3)
BLANCO = (255, 255, 255)
SEGMENTOS = [  # (fracción del anillo, color)
    (0.40, (0xFF, 0x9F, 0x1C)),  # naranja
    (0.25, (0xFF, 0x5A, 0x5F)),  # coral
    (0.20, (0x3D, 0x8B, 0xFD)),  # azul
    (0.15, (0xFF, 0xC9, 0x3C)),  # amarillo
]

SS = 4  # supermuestreo para bordes suaves
BASE = 1024


def _degradado(tam):
    """Degradado diagonal de AZUL_CLARO (arriba-izq) a AZUL_OSCURO."""
    peq = 256
    img = Image.new("RGB", (peq, peq))
    px = img.load()
    for y in range(peq):
        for x in range(peq):
            t = (x + y) / (2 * (peq - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(AZUL_CLARO, AZUL_OSCURO))
    return img.resize((tam, tam), Image.BICUBIC)


def _poligono_redondeado(puntos, radio, pasos=24):
    """Devuelve los vértices de un polígono con las esquinas redondeadas."""
    res = []
    n = len(puntos)
    for i in range(n):
        p0, p1, p2 = puntos[i - 1], puntos[i], puntos[(i + 1) % n]
        d1 = math.dist(p0, p1)
        d2 = math.dist(p1, p2)
        r = min(radio, d1 / 2, d2 / 2)
        a = (p1[0] + (p0[0] - p1[0]) * r / d1, p1[1] + (p0[1] - p1[1]) * r / d1)
        b = (p1[0] + (p2[0] - p1[0]) * r / d2, p1[1] + (p2[1] - p1[1]) * r / d2)
        for k in range(pasos + 1):
            t = k / pasos
            res.append((
                (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * b[0],
                (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * b[1],
            ))
    return res


def _simbolo(tam, escala=1.0):
    """Casa + anillo de presupuesto sobre fondo transparente (lienzo tam x tam)."""
    t = tam * SS
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = t / BASE * escala
    off = t / 2 - BASE / 2 * f  # centra el dibujo al escalar

    def P(x, y):
        return (off + x * f, off + y * f)

    # Casa (pentágono) con esquinas redondeadas; centrada ópticamente en el lienzo
    casa = [P(512, 176), P(884, 486), P(792, 486), P(792, 836), P(232, 836), P(232, 486), P(140, 486)]
    d.polygon(_poligono_redondeado(casa, 40 * f), fill=BLANCO)

    # Anillo de presupuesto dentro de la casa
    cx, cy = P(512, 640)
    r_ext, r_int = 150 * f, 74 * f
    hueco = 5  # grados de separación entre segmentos
    inicio = -90
    for frac, color in SEGMENTOS:
        barrido = 360 * frac
        d.pieslice([cx - r_ext, cy - r_ext, cx + r_ext, cy + r_ext],
                   inicio + hueco / 2, inicio + barrido - hueco / 2, fill=color)
        inicio += barrido
    d.ellipse([cx - r_int, cy - r_int, cx + r_int, cy + r_int], fill=BLANCO)
    return img.resize((tam, tam), Image.LANCZOS)


def icono(tam, forma="redondeado", escala=1.0):
    """forma: 'redondeado' (Android/web), 'cuadrado' (iOS, sin transparencia),
    'circulo' (Android round)."""
    fondo = _degradado(tam * SS).convert("RGBA")
    mascara = Image.new("L", (tam * SS, tam * SS), 0)
    dm = ImageDraw.Draw(mascara)
    if forma == "redondeado":
        dm.rounded_rectangle([0, 0, tam * SS - 1, tam * SS - 1], radius=round(tam * SS * 0.225), fill=255)
    elif forma == "circulo":
        dm.ellipse([0, 0, tam * SS - 1, tam * SS - 1], fill=255)
    else:
        dm.rectangle([0, 0, tam * SS, tam * SS], fill=255)
    fondo = fondo.resize((tam, tam), Image.LANCZOS)
    mascara = mascara.resize((tam, tam), Image.LANCZOS)
    simbolo = _simbolo(tam, escala)
    fondo.alpha_composite(simbolo)
    if forma == "cuadrado":
        return fondo.convert("RGB")
    fondo.putalpha(mascara)
    return fondo


def guardar(img, *ruta):
    p = os.path.join(RAIZ, *ruta)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    print("  ", os.path.relpath(p, RAIZ))


def main():
    print("Marca:")
    guardar(icono(1024), "assets", "branding", "logo.png")
    guardar(icono(1024, "cuadrado"), "assets", "branding", "logo_cuadrado.png")
    guardar(_simbolo(1024), "assets", "branding", "simbolo.png")

    print("Android:")
    densidades = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = ("android", "app", "src", "main", "res")
    for nombre, k in densidades.items():
        guardar(icono(round(48 * k), escala=0.92), *res, f"mipmap-{nombre}", "ic_launcher.png")
        guardar(icono(round(48 * k), "circulo", escala=0.80), *res, f"mipmap-{nombre}", "ic_launcher_round.png")
        # Icono adaptativo: 108dp, el símbolo dentro de la zona segura (66dp)
        guardar(_simbolo(round(108 * k), escala=0.56), *res, f"drawable-{nombre}", "ic_launcher_foreground.png")

    print("iOS:")
    carpeta_ios = ("ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    with open(os.path.join(RAIZ, *carpeta_ios, "Contents.json"), encoding="utf-8") as fh:
        contenidos = json.load(fh)
    for im in contenidos["images"]:
        lado = float(im["size"].split("x")[0]) * int(im["scale"][0])
        guardar(icono(round(lado), "cuadrado"), *carpeta_ios, im["filename"])

    print("macOS:")
    carpeta_mac = ("macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    ruta_mac = os.path.join(RAIZ, *carpeta_mac, "Contents.json")
    if os.path.exists(ruta_mac):
        with open(ruta_mac, encoding="utf-8") as fh:
            for im in json.load(fh)["images"]:
                lado = float(im["size"].split("x")[0]) * int(im["scale"][0])
                guardar(icono(round(lado), escala=0.92), *carpeta_mac, im["filename"])

    print("Web:")
    guardar(icono(32), "web", "favicon.png")
    guardar(icono(192), "web", "icons", "Icon-192.png")
    guardar(icono(512), "web", "icons", "Icon-512.png")
    guardar(icono(192, "cuadrado", escala=0.8), "web", "icons", "Icon-maskable-192.png")
    guardar(icono(512, "cuadrado", escala=0.8), "web", "icons", "Icon-maskable-512.png")

    print("Sitio web:")
    if os.path.isdir(os.path.join(RAIZ, "sitio_web")):
        guardar(icono(1024), "sitio_web", "logo.png")
        guardar(icono(32), "sitio_web", "favicon.png")

    print("Windows:")
    ico = os.path.join(RAIZ, "windows", "runner", "resources", "app_icon.ico")
    if os.path.isdir(os.path.dirname(ico)):
        icono(256).save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        print("  ", os.path.relpath(ico, RAIZ))

    print("Panel del servidor:")
    guardar_logo_panel()


def guardar_logo_panel():
    """Logo del panel /admin incrustado en Dart: la imagen Docker solo copia servidor/."""
    import base64
    import io

    buf = io.BytesIO()
    icono(96).save(buf, "PNG", optimize=True)
    datos = base64.b64encode(buf.getvalue()).decode("ascii")
    trozos = "\n".join(f"  '{datos[i:i + 100]}'" for i in range(0, len(datos), 100))
    p = os.path.join(RAIZ, "servidor", "lib", "src", "panel", "logo.dart")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write("// Generado por tool/generar_logo.py: no editar a mano.\n")
        fh.write("// Logo de la app (96 px, PNG en base64) para la cabecera y el favicon del panel.\n")
        fh.write("const String logoPanelBase64 =\n" + trozos + ";\n")
    print("  ", os.path.relpath(p, RAIZ))


if __name__ == "__main__":
    main()
