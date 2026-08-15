<!-- release-gate:inicio -->
## Release Gate

Este repo tiene un gate de calidad determinista (`./scripts/gate-check.sh`) que corre en CI
y bloquea el merge. Los números congelados viven en `.gate/baseline.json`.

- **El baseline nunca se edita para que el gate pase.** Si el gate bloquea, se arregla la
  causa: formatear, tipar, sacar el flujo contaminado, subir la dependencia.
- El baseline solo se toca en una dirección: **apretándolo**, con `/release-gate:ratchet`,
  cuando la realidad ya mejoró.
- Los scripts de `scripts/gate-*.sh` son idénticos entre repos y **no se editan a mano**:
  todo dato del proyecto va al baseline. `/release-gate:doctor` delata cualquier edición.
- Antes de pushear a `dev`/`main`: `/release-gate:run`. Un push sin corrida verde del commit
  actual queda bloqueado por el hook.
- Sin el plugin instalado, los scripts corren igual: `./scripts/gate-run.sh` (gate +
  evidencia) y `./scripts/gate-status.sh` (tablero). El plugin agrega los comandos guiados
  y se instala una sola vez desde `innsolutionsmx/release-gate`.
- ¿Primera vez con el gate? Leé (y ofrecele al desarrollador) la guía:
  https://github.com/innsolutionsmx/release-gate/blob/main/docs/guia-desarrollador.md
<!-- release-gate:fin -->
