# Validación — 2026-09-17

Entorno: Omarchy 4.0.4-1, Hyprland 0.56.2, Qt 6.11.2, Quickshell de la instalación.

## Automatizada

- 14 pruebas Python: validación XKB, Unicode/escape Lua, comandos sin ejecutar,
  detección de conflictos estáticos/dinámicos, consentimiento de reemplazo,
  revisión concurrente, mappings desactivados, importación, catálogo XDG,
  fallo antes de escribir, rollback, recuperación y conservación de edición ajena
  durante desinstalación.
- 16 comprobaciones QML de captura (18 resultados QtTest contando inicio/final):
  F20/F21/F22/F35, multimedia, volumen, brillo, modificadores, combinaciones,
  Caps Lock, teclado numérico, AltGr, fallback de código y auto-repeat.
- Runtime Lua: descarta bindings eliminados por overrides; el alias conserva
  exactamente el callable original y ambos triggers siguen activos.
- El binario real `Hyprland --verify-config` acepta los hooks y el alias F22
  sobre la configuración completa existente.

## Sesión real

El registro reproducible está en [live-results.txt](live-results.txt).
`python3 tests/live_check.py --apply` es una prueba optativa con efectos temporales;
restaura el estado en `finally` y compara todos los bindings originales efectivos.

| Caso | Resultado |
|---|---|
| F20 → aplicación | Registrado y ejecutado el callable real; `gio launch` abre un `.desktop` descubierto por el catálogo. Obsidian no está instalado en esta máquina. |
| F21 → comando | El callable registrado crea un archivo temporal; comprobado y eliminado. |
| F22 → SUPER+V | Identidad de función comprobada dentro del compositor; SUPER+V conserva su binding efectivo. |
| Conflicto | Identifica «Keystroke clipboard» antes de escribir. |
| Desactivar/restaurar | Desaparece y reaparece el mapping efectivo, conservando su definición. |
| Error | Inyección de fallo de validación/recarga: estado previo restaurado y journal cerrado. |
| Persistencia | Recarga independiente de Hyprland conserva los tres mappings de prueba. |
| Interfaz | Panel carga en Wayland; 164 grupos de acciones, 92 aplicaciones y 30 comandos de Omarchy descubiertos en esta instalación. Guardar F24 desde QML y retirarlo funciona de extremo a extremo. |
| Estado final | Cero mappings gestionados; conjunto de bindings originales intacto. |
| Desinstalación | Ejecutada realmente: `hyprland.lua` restaurado byte por byte; launcher y plugin retirados. Reinstalación limpia completada. |
| Manifest/launcher | Registry de Omarchy reconoce `pablousx.omabinds`, habilitado; `summon` devuelve `ok` y `hide` cierra el panel. |

## Comprobaciones físicas pendientes

No se reinició el equipo ni se cerró la sesión del usuario. La persistencia está
verificada por recarga y por el análisis de configuración con el binario real.
Falta probar las pulsaciones físicas en ambos teclados, la captura de todas sus
teclas especiales y F20 con Obsidian una vez instalado. Una prueba con teclado
virtual `wtype` no disparó el binding; por eso las pruebas automatizadas de
ejecución llaman los **callables registrados**, y no se presentan como pruebas
de pulsación física.

## Diagnóstico durante desarrollo

`Hyprland --verify-config` tuvo un SIGSEGV al consultar `is_enabled()` en un
objeto que un override había eliminado. Ocurrió solo en procesos de validación.
Se correlacionó con coredumpctl y se aisló con una configuración mínima. El
runtime ahora registra `hl.unbind` y descarta esos objetos antes de consultarlos;
la configuración real y la regresión Lua pasan. No se publicó ningún informe
externo ni se modificaron archivos del sistema.

## Ejecutar comprobaciones locales

```sh
python3 -m unittest discover -s tests -v
lua tests/test_runtime.lua
QT_QPA_PLATFORMTHEME=basic /usr/lib/qt6/bin/qmltestrunner -platform offscreen -input tests
```

La captura [preview.png](preview.png) corresponde al panel real con el tema
activo. No es un diseño dibujado ni incluye el escritorio.
