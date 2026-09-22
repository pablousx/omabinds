# Changelog

Todas las versiones publicadas de omabinds se documentan aquí.

## 1.1.0 — 2026-09-22

### Cambios

- Rediseño del panel con componentes nativos actuales de Omarchy Quattro y un
  flujo más compacto para listar, filtrar, crear y editar atajos.
- Búsqueda de combinaciones independiente de mayúsculas, espacios y signos `+`.
- Estado de setup más preciso: la interfaz exige tanto la integración Lua como
  un launcher propiedad de omabinds antes de habilitar la edición.
- Migración segura de instalaciones antiguas que tenían el plugin registrado
  pero no una ubicación activa como bar widget.
- Reintentos acotados para las operaciones IPC del instalador.
- La reinstalación valida el archivo candidato y no queda bloqueada por errores
  históricos de comandos `hyprctl eval` ajenos al plugin.

### Distribución

- Paquete reproducible con una lista cerrada de archivos de ejecución, incluyendo
  el icono requerido `assets/keycap-3d.png`.
- `SHA256SUMS`, copia de la licencia y verificación del paquete extraído.
- Website, README y capturas sincronizados con la versión publicada.

### Compatibilidad

- Se conserva el ID permanente `pablousx.omabinds` y el formato de estado versión 1.
- No se requiere migración de mappings ni se modifican configuraciones personales
  durante una actualización normal.

## 1.0.0 — 2026-09-18

- Primera versión pública y primer snapshot listado en el marketplace de Omarchy.
