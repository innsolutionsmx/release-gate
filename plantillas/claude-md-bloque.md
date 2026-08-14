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
<!-- release-gate:fin -->
