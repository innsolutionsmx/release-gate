# Gate Vendoring Specification

## Purpose

El contrato de qué instala `init`, qué propaga `upgrade` y qué custodia `doctor` — extendido
a las piezas nuevas de v0.4.0 (`gate-status.sh`, `gate-run.sh`, los dos hooks, el bloque de
`CLAUDE.md`, las entradas de `settings.json` y la línea de `.gitignore`). El principio
rector no cambia: los scripts son idénticos entre repos, los datos del proyecto viven en
`.gate/baseline.json`.

## Requirements

### Requirement: `init` instala las piezas nuevas
`/release-gate:init` SHALL vendorear `scripts/gate-status.sh`, `scripts/gate-run.sh`,
`.claude/hooks/gate-session-status.sh` y `.claude/hooks/gate-push-guard.sh` (con
`chmod +x` sobre los `.sh`), SHALL mergear las entradas de hooks en `.claude/settings.json`,
SHALL instalar el bloque de doctrina en `CLAUDE.md`, y SHALL agregar
`.gate/last-run.json` a `.gitignore`.

#### Scenario: Init en repo limpio
- GIVEN un repo sin ninguna pieza del gate
- WHEN corre `/release-gate:init`
- THEN quedan instaladas las 5 piezas nuevas (2 scripts, 2 hooks, bloque CLAUDE.md) más las entradas de settings.json y la línea de .gitignore

### Requirement: `upgrade` propaga sin perder estado ajeno
`/release-gate:upgrade` SHALL re-vendorear las piezas nuevas (pisando versiones anteriores
de los scripts propios), SHALL reemplazar el bloque de `CLAUDE.md` de forma idempotente por
marcadores, y SHALL aplicar el mismo merge aditivo de `settings.json` que `init`. `upgrade`
MUST NOT re-medir ningún baseline existente ni eliminar hooks, plugins o marketplaces
preexistentes ajenos al gate.

#### Scenario: Upgrade preserva hooks de la casa (pos-llantera)
- GIVEN `pos-llantera-jairo` con `PostToolUse` de dos matchers (`Edit|Write` y `Bash`) ajenos al gate
- WHEN corre `/release-gate:upgrade`
- THEN los dos matchers de `PostToolUse` siguen intactos y se agrega el `PreToolUse` nuevo con `matcher: "Bash"` como entrada adicional del array

#### Scenario: Upgrade en repo sin bloque `hooks` (landing-crb, landing-urn)
- GIVEN un `settings.json` con `enabledPlugins`/`extraKnownMarketplaces` pero sin clave `hooks`
- WHEN corre `/release-gate:upgrade`
- THEN se agrega la clave `hooks` con `SessionStart` y `PreToolUse` nuevos, sin tocar `enabledPlugins` ni `extraKnownMarketplaces`

#### Scenario: Upgrade en repo con `hooks` + plugins declarados (landing-cursos-urn)
- GIVEN un `settings.json` con bloque `hooks` completo y `enabledPlugins` en el mismo archivo
- WHEN corre `/release-gate:upgrade`
- THEN ambos bloques conviven sin pérdida tras el merge

### Requirement: Merge idempotente ejecutado por Claude
El merge de `settings.json` SHALL ejecutarse con Read + Edit (nunca reescribiendo el archivo
completo), SHALL detectar idempotencia buscando la subcadena `gate-session-status.sh` /
`gate-push-guard.sh` en el archivo antes de agregar nada, y tras el merge SHALL validarse con
`php -r 'json_decode(...)'` y verificando que las claves/hooks previos sigan presentes.

#### Scenario: Segunda corrida no duplica
- GIVEN un repo donde `/release-gate:upgrade` ya instaló las entradas de hooks
- WHEN corre `/release-gate:upgrade` de nuevo
- THEN no se agregan entradas duplicadas en `settings.json`

### Requirement: Custodia de `doctor` — checksum
`/release-gate:doctor` SHALL custodiar por `shasum` contra `${CLAUDE_PLUGIN_ROOT}`:
`scripts/gate-check.sh`, `gate-headers.sh`, `gate-lighthouse.sh`, `gate-links.php`,
`gate-status.sh`, `gate-run.sh`, `.claude/hooks/gate-session-status.sh`,
`.claude/hooks/gate-push-guard.sh`, las plantillas y `phpstan/Rules/*.php`.

#### Scenario: Script editado a mano
- GIVEN `scripts/gate-status.sh` con contenido distinto al vendoreado en `${CLAUDE_PLUGIN_ROOT}`
- WHEN corre `/release-gate:doctor`
- THEN reporta drift de checksum sobre ese archivo

### Requirement: Custodia de `doctor` — presencia
`/release-gate:doctor` SHALL verificar por **presencia** (no checksum) el bloque delimitado
de `CLAUDE.md`, las entradas de hooks en `settings.json`, y la línea
`.gate/last-run.json` en `.gitignore` — son archivos que el repo edita legítimamente.
`doctor.md` SHALL incluir una tabla explícita de archivos custodiados (en prosa, coherente
con el patrón vigente; sin manifiesto JSON declarativo).

#### Scenario: Entrada de settings.json ausente
- GIVEN un repo donde se borró manualmente la entrada `PreToolUse` de `gate-push-guard.sh`
- WHEN corre `/release-gate:doctor`
- THEN reporta la ausencia de esa entrada como hallazgo

#### Scenario: Línea de .gitignore ausente
- GIVEN un repo sin la línea `.gate/last-run.json` en `.gitignore`
- WHEN corre `/release-gate:doctor`
- THEN reporta el hallazgo y sugiere agregarla

### Requirement: Ausencia de re-medición
Ninguna de las operaciones de esta capability (`init`, `upgrade`, `doctor`) SHALL modificar
`.gate/baseline.json` salvo el campo `plugin` (versión). Re-medir baselines es
responsabilidad exclusiva de `/release-gate:ratchet`, fuera de este change.

#### Scenario: Upgrade no re-mide baseline existente
- GIVEN un repo con `.gate/baseline.json` congelado en `phpstan.entradas_baseline: 904`
- WHEN corre `/release-gate:upgrade`
- THEN el valor de `phpstan.entradas_baseline` no cambia, solo el campo `plugin` se actualiza
