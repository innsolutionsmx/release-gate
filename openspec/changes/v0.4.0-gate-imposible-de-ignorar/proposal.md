# Proposal: v0.4.0 — El gate imposible de ignorar

## Intent

El gate existe y bloquea en CI, pero los devs (siempre vía Claude Code) no se enteran de
su estado, de los trinquetes ni de cuándo se puede apretar. La mejora real se pierde en
silencio y el bloqueo llega tarde (CI) en vez de temprano (sesión / push). v0.4.0 mete el
estado del gate en el contexto de cada sesión y en el camino del `git push`.

## Scope

### In Scope
- `scripts/gate-status.sh` — tablero baseline vs realidad **por conteo**, sin re-analizar
  (< 1-2 s incluso con las 903 entradas de phpstan en pos-llantera). Muestra perfil,
  versión de plugin (vendoreada vs disponible), fecha del último gate, y avisa
  "SE PUEDE APRETAR → `/release-gate:ratchet`".
- Hook **SessionStart** en `.claude/settings.json` del repo gateado → corre `gate-status.sh`.
- Hook **PreToolUse / Bash** que intercepta `git push` → corre el gate antes de dejar pushear.
- Bloque corto para el `CLAUDE.md` del repo gateado con el criterio: nunca tocar el baseline
  para pasar; editarlo solo al apretar vía `ratchet`.
- `commands/init.md`, `upgrade.md`, `doctor.md` aprenden las 4 piezas (instalar, propagar,
  custodiar checksums). Lección v0.2.0: sumar al script y olvidar los comandos deja huecos.

### Out of Scope
- Reescribir `gate-check-*.sh` (siguen siendo "leen, nunca escriben").
- Re-medir baselines existentes (eso es `ratchet`).
- Cerrar el drift 0.1.0 → 0.3.0 de los 5 baselines (v0.4.0 lo **reporta**, no lo corrige).
- `.githooks/pre-push` nativo — ver Cuestión 6.
- Instalar el plugin en los repos gateados (sigue siendo vendoring + checksums).

## Capabilities

### New Capabilities
- `gate-status`: tablero de estado del gate por conteo, sin re-análisis, y detección de
  "se puede apretar".
- `gate-hooks`: hooks de Claude Code vendoreados al repo gateado (SessionStart informativo,
  PreToolUse sobre `git push`) y reglas de merge no destructivo en `.claude/settings.json`.
- `gate-doctrina`: bloque de criterio inyectado en el `CLAUDE.md` del repo gateado.
- `gate-vendoring`: contrato de qué archivos instala `init`, propaga `upgrade` y custodia
  `doctor` (checksums), extendido a las piezas nuevas.

### Modified Capabilities
- None (`openspec/specs/` está vacío; este change funda las specs del plugin).

## Approach

| Pieza | Enfoque |
|---|---|
| `gate-status.sh` | `set -euo pipefail`, `cd "$(dirname "$0")/.."`, lee `.gate/baseline.json` (schema 1) y cuenta con `grep -c … \|\| true` sobre `phpstan-baseline.neon`, `psalm-taint-baseline.xml`, `phpmd.baseline.xml`, `deptrac.baseline.yaml`. Archivo ausente ⇒ 0, con `if [ -f … ]; then` explícito (nunca `[ -f x ] && VAR=…`). Texto plano a stdout, `exit 0` siempre. |
| Hook SessionStart | Patrón `git-session-status.sh`: sin `matcher`, texto plano, `exit 0`. Guard: sin `.gate/baseline.json` no imprime nada. |
| Hook PreToolUse | Patrón `git-guard.sh`: `matcher: "Bash"`, lee payload por stdin, extrae `tool_input.command` con `sed` (no `jq`), descarta rápido lo que no sea `git push`. Bloquea imprimiendo `{"hookSpecificOutput":{…,"permissionDecision":"deny","permissionDecisionReason":"…"}}` y `exit 0`. |
| Bloque CLAUDE.md | Delimitado por marcadores (`<!-- release-gate:inicio/fin -->`) para que `upgrade` lo reemplace idempotentemente y `doctor` lo checksumee. |
| init/upgrade/doctor | Merge no destructivo de `settings.json` (agregar objeto al array del evento, nunca reemplazarlo), + pasos nuevos en el checklist prosa de `doctor.md`. |

## Cuestiones abiertas (recomendación preliminar; Rodrigo decide en spec/design)

**1. ¿El hook de push bloquea?**
Recomendación: **deny con mensaje-fix + override documentado**, limitado a push a `dev`/`main`.
Tradeoffs: deny puro = máxima disciplina pero rompe el flujo si el gate tarda minutos
(phpstan) o si hay una urgencia real; aviso no bloqueante = cero fricción pero repite el
problema actual (nadie se entera). El intermedio conserva el bloqueo donde importa
(ramas protegidas) y deja salida explícita y auditable.

**2. Realidad de PHPStan en `gate-status` (correr el gate tarda minutos).**
Recomendación: **`gate-status` nunca corre el gate**. Deriva la realidad por conteo de los
archivos de baseline y muestra "último gate: `<fecha>`" leyendo `.gate/last-run.json`,
que escribe **el hook de push** tras una corrida exitosa (el explore confirmó que hoy
`gate-check.sh` no escribe nada, y el hook ya corre el gate: es el punto natural).
Tradeoffs: (a) mtime/`git log` de `baseline.json` — gratis pero mide "última edición del
baseline", no "última corrida"; (b) `last-run.json` desde el hook — preciso y no toca el
script vendoreado, pero inventa un segundo formato de estado; (c) re-correr bajo demanda —
descartado en SessionStart, aceptable solo como flag explícito.

**3. Guard por existencia de `.gate/baseline.json` en SessionStart.**
Recomendación: **sí**, y documentarlo. Sin baseline el hook sale mudo con `exit 0`
(patrón `git-session-status.sh` fuera de un repo git). Sin esto, cualquier sesión en un
repo no gateado escupiría ruido o error.

**4. Convivencia de hooks (7 repos, 5 configs distintas).**
Recomendación: **merge aditivo idempotente, sin normalizar**. `init`/`upgrade` agregan un
objeto `{matcher, hooks}` al array del evento existente y crean la clave `hooks` si falta,
preservando `enabledPlugins` / `extraKnownMarketplaces`. Casos: landing-crb y landing-urn
no tienen bloque `hooks` (crear, sin borrar claves de plugins); landing-cursos-urn prueba
que `hooks` + `enabledPlugins` conviven; pos-llantera tiene `PostToolUse` con dos matchers
— anidar, no reemplazar. Tradeoff: normalizar los 7 a una config canónica daría un estado
predecible y checksumeable, pero pisaría hooks de la casa ajenos al gate — se descarta.

**5. Impacto en los comandos del plugin (checksums).**
Recomendación: `doctor` custodia `scripts/gate-status.sh` y los dos scripts de hook por
`shasum` contra `${CLAUDE_PLUGIN_ROOT}` (patrón actual), y verifica el bloque de
`CLAUDE.md` y las entradas de `settings.json` por **presencia**, no por checksum
(son archivos que el repo edita legítimamente). Abierto: ¿`doctor.md` gana un manifiesto
declarativo de archivos custodiados o sigue en prosa? Recomendación preliminar: seguir en
prosa en v0.4.0 (coherente con el patrón vigente) y anotar el manifiesto como deuda.

**6. (Opcional) `.githooks/pre-push` nativo.**
Recomendación: **no** en v0.4.0. Hoy es letra muerta (`core.hooksPath` no está configurado
en ningún repo) y los devs siempre pushean vía Claude. Tradeoff: sin él, un push desde
terminal cruda esquiva el gate — mitigado porque CI sigue siendo la red final.

## Affected Areas

| Área | Impacto | Descripción |
|---|---|---|
| `scripts/gate-status.sh` | Nuevo | Tablero por conteo |
| `scripts/hooks/` (nuevo dir) | Nuevo | Los 2 scripts de hook a vendorear |
| `plantillas/claude-md-bloque.md` | Nuevo | Bloque de doctrina |
| `commands/init.md` | Modificado | Vendorea las 4 piezas + merge de `settings.json` |
| `commands/upgrade.md` | Modificado | Propaga e idempotencia del bloque CLAUDE.md |
| `commands/doctor.md` | Modificado | Checksums/presencia de las piezas nuevas |
| `docs/referencia.md` | Modificado | `.gate/last-run.json` y contrato de hooks |
| `.claude-plugin/plugin.json` | Modificado | 0.3.0 → 0.4.0 |

## Risks

| Riesgo | Prob. | Mitigación |
|---|---|---|
| Merge de `settings.json` pisa hooks de la casa (pos-llantera) | Med | Merge aditivo por evento+matcher; `doctor` verifica que los hooks previos sigan |
| `matcher: "Bash"` corre en el hot path de TODA sesión | Alta | Descarte por regex en las primeras líneas; sin I/O antes de confirmar `git push` |
| Drift de versión: 5/7 baselines en `plugin: 0.1.0` con plugin en 0.3.0 | Alta | `gate-status` muestra **vendoreado vs disponible** y sugiere `/release-gate:upgrade` |
| Hook bloqueante frustra y termina desactivado | Med | Mensaje-fix accionable + override documentado + alcance `dev`/`main` |
| Baselines ausentes rompen el conteo bajo `set -e` | Med | `if [ -f … ]; then` explícito y `grep -c … \|\| true` (gotchas v0.2.0) |
| `last-run.json` = segundo formato de estado a mantener | Med | Schema mínimo (fecha, veredicto, versión), documentado en `docs/referencia.md` |
| landing-crb/landing-urn estrenan hooks (nunca tuvieron) | Baja | Verificación post-instalación vía `doctor`; sin baseline el hook sale mudo |

## Rollback Plan

1. Revertir el bump a 0.4.0 en `.claude-plugin/plugin.json` y el commit del plugin.
2. Por repo gateado afectado: borrar `scripts/gate-status.sh` y `.claude/hooks/gate-*.sh`,
   quitar las entradas del array de hooks en `.claude/settings.json` (dejando intactas las
   preexistentes), borrar el bloque delimitado de `CLAUDE.md` y `.gate/last-run.json`.
3. `gate-check.sh`, `.gate/baseline.json` y el job de CI quedan **intactos** por diseño:
   el gate sigue funcionando exactamente como en v0.3.0.

## Dependencies

- Ninguna herramienta nueva. Sin `jq` (patrón de la casa: `sed`).
- Requiere que Rodrigo corra `/plugin` + reinicie para tomar la versión nueva.

## Success Criteria

- [ ] Abrir sesión en un repo gateado imprime el tablero en < 2 s (verificado en
      pos-llantera, 903 entradas phpstan).
- [ ] `gate-status.sh` detecta y anuncia "SE PUEDE APRETAR" cuando la realidad mejoró.
- [ ] Un `git push` a `dev`/`main` con el gate en rojo no pasa vía Claude Code.
- [ ] `init` en un repo limpio y `upgrade` en los 7 dejan las 4 piezas instaladas sin
      perder ningún hook, plugin ni marketplace preexistente.
- [ ] `doctor` detecta drift/ausencia de cada una de las 4 piezas nuevas.
- [ ] Sesión en un repo SIN `.gate/baseline.json`: cero output, cero errores.
