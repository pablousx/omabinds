# omabinds

Editor visual de relaciones **tecla → acción** para Omarchy Quattro. Panel QML
nativo, temas activos, selector de aplicaciones con iconos, comandos, acciones
de Omarchy/Hyprland y aliases que reutilizan directamente las acciones Lua.

Requiere Omarchy **4.0.4**, Hyprland **0.56.2** con configuración Lua,
Quickshell, Python 3, `libxkbcommon`, `gio` y una sesión Hyprland activa.
No necesita paquetes Python, privilegios de administrador, daemon ni acceso a
dispositivos de entrada. No diferencia teclados: ambos disparan los mismos atajos.

## Instalación

Desde este directorio, dentro de la sesión gráfica:

```sh
bash scripts/install.sh
```

El instalador copia el plugin a
`~/.config/omarchy/plugins/pablousx.omabinds`, registra el launcher y habilita el
icono de barra. Abre **omabinds** desde el launcher o el icono de teclado.
También puedes usar:

```sh
omarchy-shell shell summon pablousx.omabinds '{}'
```

El estado inicial está vacío. No se asignan F20/F21/F22 automáticamente.
El manifest permite distribuir el repositorio mediante `omarchy plugin add`;
después ejecuta `bash ~/.config/omarchy/plugins/pablousx.omabinds/scripts/install.sh`
para instalar la integración Lua y el launcher. Omarchy no ejecuta instaladores
de terceros al añadir un repositorio.

## Uso

1. Selecciona **Nuevo mapping**, escribe un nombre y pulsa **Capturar combinación**.
   También puedes escribir `F20`, `SUPER + V`, `XF86AudioPlay` o `code:191`.
2. Elige **Aplicaciones**, **Comando**, **Omarchy**, **Hyprland** o **Aliases**.
   Las aplicaciones se descubren desde los directorios XDG y se abren con
   `gio launch`, respetando los archivos `.desktop` (incluido su soporte DBus).
3. Pulsa **Validar y guardar**. Si hay un conflicto se muestra la acción que ocupa
   la combinación antes de aplicar nada. Cancela, cambia la combinación o elige
   **Reemplazar explícitamente**.

Para el portapapeles: crea un mapping F22, abre **Aliases**, busca `SUPER + V`
y selecciona su acción efectiva. F22 y SUPER + V reutilizan el mismo callable
Lua, con sus flags originales. No se sintetizan pulsaciones. Si el origen tiene
varias acciones, se conservan todas y su orden.

**Editar** permite cambiar nombre, acción y combinación; **Duplicar** exige una
nueva combinación. **Desactivar** mantiene la definición. **Restaurar** vuelve
a activarla con las mismas validaciones. Eliminar o desactivar un reemplazo
restaura el binding original, sin reconstruir sus archivos.

Las categorías filtran personalizados, aliases, desactivados y sistema.
Usa Tab/Shift+Tab, Enter/Espacio y **Ctrl+F** para navegar y buscar. Escape cancela
la captura; puedes introducir `Escape` manualmente para asignarlo. La captura
solicita el inhibidor de shortcuts de Wayland y no modifica la configuración
de entrada. Bindings con `dont_inhibit` y atajos reservados por el compositor
pueden impedir capturar una tecla: en ese caso introdúcela por nombre.

**Exportar** crea un JSON nuevo (no sobrescribe otro archivo). **Importar** valida
el JSON y pide confirmación antes de reemplazar el estado gestionado. Revisa los
comandos de exportaciones ajenas. **Restablecer** elimina solo los mappings del
plugin. Los archivos de backup pueden contener tus comandos y rutas personales.

## Seguridad y persistencia

- Solo se añaden dos bloques delimitados a `~/.config/hypr/hyprland.lua`:
  captura al principio y aplicación al final. El resto se conserva.
- `~/.config/omabinds/state.lua` es la única fuente de estado persistente; contiene
  una cabecera JSON y datos Lua escapados, nunca Lua proporcionado por una importación.
- Se comprueban revisión, combinaciones y conflictos; se ejecuta
  `Hyprland --verify-config` en un archivo temporal antes de reemplazar el estado.
- La escritura es atómica y sincronizada a disco. Se recarga Hyprland, se consulta
  `hyprctl configerrors` y se verifica la presencia de cada mapping efectivo.
  Ante un error se restaura el estado anterior y se verifica de nuevo.
- `state.previous.lua`, `transaction.json` y `pending.lua` permiten recuperar
  una aplicación interrumpida. Al arrancar, si el proceso de la transacción ya
  no existe, se carga la generación anterior. El siguiente acceso completa la
  recuperación. También puedes ejecutar:

  ```sh
  python3 ~/.config/omarchy/plugins/pablousx.omabinds/backend/omabinds.py recover
  ```

- Una actualización que cambie la descripción/flags o elimine un origen deja su
  alias sin aplicar y muestra un aviso. Los aliases siguen la acción del trigger
  de origen cuando este conserva su identidad; no son copias congeladas de código.
- Los archivos son propiedad del usuario; no se escribe en `/usr/share/omarchy`.
  Las actualizaciones normales no los reemplazan. Si se reemplaza manualmente
  todo `hyprland.lua`, reinstala la integración.

No se reutilizan bindings de ratón, catch-all, dispositivos específicos o
`ignore_mods`: aparecen como no compatibles para alias. Los conflictos de
submaps o creados dinámicamente fuera del archivo se bloquean sin reemplazarlos.
El catálogo de acciones del sistema procede de los bindings Lua efectivos
durante la carga, incluidos los overrides personales.

## Desinstalación

```sh
bash ~/.config/omarchy/plugins/pablousx.omabinds/scripts/install.sh --uninstall
```

Retira los bloques propios, recarga y valida Hyprland, deshabilita el plugin y
elimina su launcher y directorio. Conserva los mappings y backups para reinstalar.
Para eliminarlos también, añade `--purge --yes`. Desinstala con este comando
antes de usar `omarchy plugin remove`, para que no queden referencias Lua rotas.

## Desarrollo y validación

```sh
python3 -m unittest discover -s tests -v
lua tests/test_runtime.lua
```

Consulta [la matriz de validación](docs/VALIDATION.md) para distinguir pruebas
automatizadas, comprobaciones en la sesión real y pruebas físicas pendientes.
La [vista previa](docs/preview.png) usa datos de ejemplo.

API utilizada: manifest de `/usr/share/omarchy/shell/README.md`, stubs de
`/usr/share/hypr/stubs/hl.meta.lua` y [bindings oficiales de Hyprland](https://wiki.hypr.land/configuring/core/binds/).

Licencia MIT.
