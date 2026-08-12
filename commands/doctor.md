---
description: "Diagnostica la instalación del gate: baseline sano, scripts sin drift contra el plugin, herramientas y CI"
---

Chequeá la salud de la instalación del Release Gate en este repo y reportá una
tabla de estado. Diagnosticás primero; no arregles nada sin preguntar.

## Checks

1. **Baseline**: `.gate/baseline.json` existe, es JSON parseable, `schema: 1`,
   `perfil` ∈ {medida, landing}, y tiene las secciones de su perfil (ver
   `${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`). Registrá también `plugin`
   (versión con la que se vendoreó) si está.
2. **Scripts presentes y ejecutables**: `scripts/gate-check.sh`,
   `scripts/gate-headers.sh`, `scripts/gate-lighthouse.sh` (+ `scripts/gate-links.php`
   si el perfil es landing), todos con permiso de ejecución.
3. **Drift contra el plugin** (el check estrella): compará checksums —

   ```bash
   shasum scripts/gate-check.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-check-<perfil>.sh"
   shasum scripts/gate-headers.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-headers.sh"
   # ... ídem lighthouse y (landing) gate-links.php
   ```

   `<perfil>` sale del baseline. Checksums iguales = sin drift ✅. Distintos = ⚠️:
   mostrá el diff real (`diff` archivo por archivo) para distinguir los dos casos:
   - el plugin trae una versión más nueva → ofrecé re-vendorear (copiar encima,
     `chmod +x`, correr `./scripts/gate-check.sh` para verificar que sigue APROBADO,
     y actualizar `plugin` en el baseline). Solo con confirmación del usuario.
   - el script del repo fue editado a mano → eso es deuda contra el principio
     rector (datos al baseline, no al script). Explicá qué dato habría que mover
     al baseline y proponé el camino.
4. **Herramientas**: `vendor/bin/pint` existe; `vendor/bin/phpstan` +
   `phpstan-baseline.neon` (solo medida); `gitleaks`, `composer`, `npm` en PATH;
   Chrome para lighthouse (`CHROME_PATH` o el default macOS) — este último es ⚠️,
   no ❌: solo bloquea el post-deploy.
5. **CI corre el gate**: `.github/workflows/ci.yml` tiene un job que ejecuta
   `scripts/gate-check.sh`, su checkout usa `fetch-depth: 0` e instala gitleaks.
   Si el gate solo corre local, ⚠️ con el riesgo explícito: un push apurado lo
   saltea. Snippet para arreglarlo: `${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`.
6. **El gate pasa**: si todo lo anterior está sano, corré `./scripts/gate-check.sh`
   y reportá el veredicto.

## Salida

Tabla: check | estado (✅/⚠️/❌) | detalle | cómo arreglarlo. Cerrá con LA acción
más importante que sigue (una sola).
