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
   `scripts/gate-headers.sh`, `scripts/gate-lighthouse.sh`, `scripts/gate-links.php`,
   `scripts/gate-status.sh`, `scripts/gate-run.sh`,
   `.claude/hooks/gate-session-status.sh` y `.claude/hooks/gate-push-guard.sh`
   — todos en **ambos** perfiles; los `.sh` con permiso de ejecución. Si el
   perfil es `medida` y falta `gate-links.php`, el repo se vendoreó con un
   plugin < 0.3.0; si faltan `gate-status.sh`/`gate-run.sh`/los hooks, se
   vendoreó con un plugin < 0.4.0: en cualquiera de los dos casos → mandá a
   `/release-gate:upgrade`.
3. **Drift contra el plugin** (el check estrella): compará checksums —

   ```bash
   shasum scripts/gate-check.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-check-<perfil>.sh"
   shasum scripts/gate-headers.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-headers.sh"
   shasum scripts/gate-status.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-status.sh"
   shasum scripts/gate-run.sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate-run.sh"
   shasum .claude/hooks/gate-session-status.sh "${CLAUDE_PLUGIN_ROOT}/scripts/hooks/gate-session-status.sh"
   shasum .claude/hooks/gate-push-guard.sh "${CLAUDE_PLUGIN_ROOT}/scripts/hooks/gate-push-guard.sh"
   # ... ídem lighthouse y gate-links.php (ambos perfiles)
   ```

   `<perfil>` sale del baseline. Checksums iguales = sin drift ✅. Distintos = ⚠️:
   mostrá el diff real (`diff` archivo por archivo) para distinguir los dos casos:
   - el plugin trae una versión más nueva → ofrecé re-vendorear (copiar encima,
     `chmod +x`, correr `./scripts/gate-check.sh` para verificar que sigue APROBADO,
     y actualizar `plugin` en el baseline). Solo con confirmación del usuario.
   - el script del repo fue editado a mano → eso es deuda contra el principio
     rector (datos al baseline, no al script). Explicá qué dato habría que mover
     al baseline y proponé el camino.
3b. **Plantillas y reglas** (según perfil): `psalm.xml` (ambos); `phpmd.xml`,
   `deptrac.yaml`, `deptrac.baseline.yaml` y `phpstan/Rules/*.php` (medida). En
   medida verificá además que `phpstan.neon.dist` registre las dos reglas en
   `services:` y que `composer.json` tenga `"Gate\\PHPStan\\": "phpstan/"` en
   `autoload-dev.psr-4` — sin eso las reglas no cargan y el gate pasa por
   omisión, que es el peor de los mundos. Las reglas (`phpstan-rules/*.php`)
   también se comparan por checksum contra el plugin: son motor, no config.

3c. **Piezas de v0.4.0 — verificación por presencia** (no checksum: son
   archivos que el repo edita legítimamente):
   - Entradas `SessionStart` y `PreToolUse`/`Bash` en `.claude/settings.json`
     que invoquen `gate-session-status.sh` / `gate-push-guard.sh`. Si falta
     alguna, reportalo como hallazgo — el gate deja de imponerse aunque los
     scripts estén vendoreados.
   - Confirmá que los hooks preexistentes ajenos al gate (otros matchers de
     `PostToolUse`, otras entradas de `PreToolUse`/`SessionStart`) siguen
     intactos: si `upgrade` los pisó, es un bug del comando, no del repo.
   - Bloque delimitado `<!-- release-gate:inicio -->` / `<!-- release-gate:fin -->`
     en `CLAUDE.md`, con contenido igual al de
     `${CLAUDE_PLUGIN_ROOT}/plantillas/claude-md-bloque.md` vigente. Ausente o
     desactualizado → hallazgo.
   - Línea `.gate/last-run.json` en `.gitignore`. Ausente → hallazgo, sugerí
     agregarla (evita commitear evidencia local por desarrollador).

4. **Herramientas**: `vendor/bin/pint` existe; `vendor/bin/phpstan` +
   `phpstan-baseline.neon` (solo medida); `vendor/bin/psalm` (ambos);
   `vendor/bin/phpmd` y `vendor/bin/deptrac` (medida); `gitleaks`, `composer`,
   `npm` en PATH; Chrome para lighthouse (`CHROME_PATH` o el default macOS) —
   este último es ⚠️, no ❌: solo bloquea el post-deploy.
   Chequeá que PHPMD sea ≥ 2.15: una 2.5.x significa que se instaló sin
   `--with-all-dependencies` y arrastra un pdepend viejo.

4b. **Perfil bien asignado**: si el perfil es `landing` pero el repo tiene
   `app/Models/` con modelos propios, migraciones de dominio o controllers de
   admin más allá de los del base, marcá ⚠️: el perfil se decide por el código,
   no por cómo se ve el sitio, y un repo así se está quedando sin análisis
   estático. No lo cambies solo — es decisión del usuario.
   Desde la v0.3.0 medida es superconjunto estricto de landing, así que **pasar de
   landing a medida no cuesta ningún check**: si el ⚠️ aplica, no hay contraparte
   que sopesar. Traé números concretos (archivos en `app/`, cantidad de models,
   controllers de admin, migraciones), no impresiones: el usuario decide con datos.
5. **CI corre el gate**: `.github/workflows/ci.yml` tiene un job que ejecuta
   `scripts/gate-check.sh`, su checkout usa `fetch-depth: 0` e instala gitleaks.
   Si el gate solo corre local, ⚠️ con el riesgo explícito: un push apurado lo
   saltea. Snippet para arreglarlo: `${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`.
6. **El gate pasa**: si todo lo anterior está sano, corré `./scripts/gate-check.sh`
   y reportá el veredicto.

## Archivos custodiados

Prosa, no manifiesto JSON declarativo — coherente con el resto del comando.

**Por checksum contra `${CLAUDE_PLUGIN_ROOT}`** (idénticos entre repos, dato
del proyecto va al baseline, no al script):

- `scripts/gate-check.sh` (contra `gate-check-<perfil>.sh`)
- `scripts/gate-headers.sh`, `scripts/gate-lighthouse.sh`, `scripts/gate-links.php`
- `scripts/gate-status.sh`, `scripts/gate-run.sh`
- `.claude/hooks/gate-session-status.sh`, `.claude/hooks/gate-push-guard.sh`
- Plantillas (`psalm.xml`, `phpmd.xml`, `deptrac.yaml`) y `phpstan/Rules/*.php`

**Por presencia** (el repo edita legítimamente el resto del archivo; no tiene
sentido un checksum de archivo completo):

- Bloque delimitado de doctrina en `CLAUDE.md`
- Entradas `SessionStart` y `PreToolUse`/`Bash` en `.claude/settings.json`
- Línea `.gate/last-run.json` en `.gitignore`

## Salida

Tabla: check | estado (✅/⚠️/❌) | detalle | cómo arreglarlo. Cerrá con LA acción
más importante que sigue (una sola).
