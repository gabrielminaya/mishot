# MiShot

Herramienta ligera de capturas de pantalla para macOS. Selecciona una zona de la pantalla, anótala y cópiala o guárdala. Sin cuentas, sin nube y sin dependencias.

## Funciones

- **Captura por zona** desde la barra de menú o con un atajo global (**⌘⇧9** por defecto). Todas las pantallas se congelan mientras seleccionas, y la selección se puede mover y redimensionar con sus esquinas.
- **Anotaciones:** lápiz, línea, flecha, rectángulo, marcador y texto, con una paleta de 8 colores.
  - Usa la rueda o el scroll para cambiar el grosor del trazo (también cambia el tamaño del texto).
  - Mantén **Shift** para ajustar líneas y flechas a 45° y dibujar cuadrados.
- **Copiar** al portapapeles (PNG + TIFF) o **guardar** como PNG a resolución Retina completa.
- Soporte para **varios monitores**.
- **Preferencias:** atajo personalizado, modo de guardado (preguntar o guardar directo en una carpeta), copiar al guardar, sonido e incluir el cursor.

## Atajos

| Tecla | Acción |
| --- | --- |
| ⌘⇧9 | Iniciar una captura (configurable) |
| ⌘C / Enter | Copiar y cerrar |
| ⌘S | Guardar |
| ⌘Z | Deshacer la última anotación |
| Esc | Cancelar el texto en edición / cerrar |
| Shift + arrastrar | Líneas a 45° y rectángulos cuadrados |
| Scroll | Cambiar el grosor / tamaño del texto |

## Requisitos

- macOS 14 Sonoma o posterior (Apple Silicon)
- Xcode Command Line Tools (Swift 5.9+)

## Compilar e instalar

```sh
./build.sh
```

Compila el código con `swiftc`, arma `build/MiShot.app`, lo firma y lo instala en `/Applications`.

La app se firma con una identidad fija para que macOS conserve el permiso de Grabación de pantalla entre compilaciones. Para usar otro certificado, pasa su nombre o su SHA-1:

```sh
SIGN_ID="Apple Development: Tu Nombre (TEAMID)" ./build.sh
```

Puedes ver los certificados disponibles con `security find-identity -v -p codesigning`.

La primera vez que la abras, da el permiso en **Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema** y vuelve a abrir MiShot.

### Regenerar el icono

```sh
swift tools/make_icon.swift && iconutil -c icns AppIcon.iconset && rm -rf AppIcon.iconset
```

## Estructura del proyecto

| Archivo | Función |
| --- | --- |
| `Sources/main.swift` | App delegate, icono de la barra de menú y atajo global (Carbon) |
| `Sources/Capture.swift` | Captura con ScreenCaptureKit y ventanas del overlay |
| `Sources/Overlay.swift` | Selección, edición de anotaciones, teclado y exportación |
| `Sources/Annotations.swift` | Herramientas y dibujo de las anotaciones |
| `Sources/Toolbar.swift` | Barras de herramientas, botones y selector de colores |
| `Sources/Preferences.swift` | Modelo de ajustes y ventana de Preferencias (SwiftUI) |
| `tools/make_icon.swift` | Generador del icono de la app |
