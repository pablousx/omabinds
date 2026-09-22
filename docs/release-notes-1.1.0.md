# omabinds 1.1.0

Esta versión actualiza la experiencia visual y hace más robusta la instalación
sin cambiar el ID del plugin ni el formato de los mappings existentes.

## Destacado

- Panel rediseñado con componentes actuales de Omarchy Quattro.
- Búsqueda de combinaciones equivalente con o sin espacios y signos `+`.
- Setup bloqueante que comprueba por separado integración Lua y launcher.
- Recuperación de instalaciones antiguas sin una ubicación activa en la barra.
- Preflight independiente de errores históricos de `hyprctl eval`.
- Paquete reproducible con contenido cerrado, checksum y licencia verificables.

## Actualización

No hay migración manual. El formato persistente continúa en versión 1 y se
conservan mappings, reemplazos y backups. La reinstalación normal actualiza los
archivos del plugin y verifica la integración existente.

## Verificación

- 16 pruebas Python.
- Runtime Lua real con dobles mínimos de la API de Hyprland.
- 19 resultados QtTest/QML.
- `omarchy plugin validate` sobre fuente y paquete extraído.
- Aceptación real de F20/F21/F22 con restauración por hash del estado original.
- Inspección visual de lista, editor, conflicto y setup en la instancia instalada.
- Dos construcciones independientes del mismo commit deben producir el mismo SHA-256.

Las pulsaciones físicas en ambos teclados y un reinicio completo de sesión siguen
fuera de esta matriz; no se presentan como pruebas realizadas.
