# Exploración: v0.4.0 "el gate imposible de ignorar"

## Estado actual

### El plugin (v0.3.0)

- `scripts/gate-check-medida.sh` (14 checks) y `scripts/gate-check-landing.sh` (8 checks,
  subconjunto estricto) son **idénticos entre proyectos**: no leen nada del filesystem del
  proyecto salvo `.gate/baseline.json` (vía `php -r 'json_decode(...)'`) y los archivos de
  baseline propios de cada herramienta (`phpstan-baseline.neon`, `psalm-taint-baseline.xml`,
  `phpmd.baseline.xml`, `deptrac.baseline.yaml`). Estilo: `set -euo pipefail`, `cd
  "$(dirname "$0")/.."`, `FAIL=0` acumulado (no `exit` temprano), cada sección con
  `echo "── Gate: … ──"`, conteos via `grep -c` con `|| true` obligatorio (el fix de la
  0.2.0: sin `|| true` un grep sin matches muere bajo `pipefail` y el script aborta antes
  de imprimir el resto de fallas).
- **Ninguno de los dos scripts escribe ningún artefacto de resultado.** Solo hacen
  `echo` a stdout y terminan con `exit 1` / `✓ GATE APROBADO`. No existe hoy
  `.gate/last-run.json` ni nada parecido — confirmado leyendo los ~140/~215 líneas
  completas de ambos scripts. Agregar un `last-run.json` sería tocar el script vendoreado
  (dato nuevo: fecha, veredicto, y quizás por-check pass/fail) — hoy el único
  "dato del proyecto" que el script consume es `.gate/baseline.json`; escribir de vuelta
  rompe la asimetría actual (script = lee, nunca escribe). Alternativa sin tocar
  `gate-check.sh`: que `gate-status.sh` derive todo por conteo directo (grep -c contra
  `phpstan-baseline.neon`, `psalm-taint-baseline.xml`, etc. — los mismos archivos que ya
  lee `gate-check.sh`) sin re-analizar, y que la "fecha del último gate" salga de
  `git log -1 --format=%ai -- .gate/baseline.json` o del mtime del baseline en vez de un
  archivo nuevo. Esto es más fiel al principio rector del plugin ("el script es idéntico
  entre proyectos, los datos viven en baseline.json") y evita inventar un segundo formato
  de estado.
- `commands/init.md` vendorea `scripts/gate-check-<perfil>.sh` → `scripts/gate-check.sh`,
  `gate-headers.sh`, `gate-lighthouse.sh`, `gate-links.php`, `chmod +x` a los `.sh`. Mide y
  congela `.gate/baseline.json` (schema 1). Agrega el job `gate` a `ci.yml`. **NO toca
  `.claude/settings.json` ni `CLAUDE.md` del repo gateado hoy** — v0.4.0 sería la primera
  vez que el gate vendorea algo bajo `.claude/`.
- `commands/upgrade.md` (repos ya instalados): compara versión del baseline vs
  `.claude-plugin/plugin.json`, instala lo que falte, re-vendorea scripts (pisa el viejo),
  mide y congela baselines NUEVOS, nunca re-mide los que ya existen (regenerar ≠ upgrade,
  eso es `ratchet`).
- `commands/doctor.md` custodia los checksums así: compara `shasum` de cada script del
  repo (`scripts/gate-check.sh`, `gate-headers.sh`, `gate-lighthouse.sh`, `gate-links.php`)
  contra el equivalente en `${CLAUDE_PLUGIN_ROOT}/scripts/gate-check-<perfil>.sh` (perfil
  sale del baseline) y contra las plantillas/reglas propias
  (`psalm.xml`, `phpmd.xml`, `deptrac.yaml`, `phpstan-rules/*.php` — "son motor, no
  config"). **No hay una lista declarativa de "archivos custodiados"** — la lista vive
  implícita en la prosa de `doctor.md` paso 2/3/3b (hardcodeada ahí). Para v0.4.0 esto
  importa: las 4 piezas nuevas (gate-status.sh, hook SessionStart, hook PreToolUse,
  bloque CLAUDE.md) tendrían que sumarse a esa misma lista prosa-que-doctor-lee, siguiendo
  el patrón existente — no hay infraestructura de manifiesto que extender, es "agregar
  más pasos al mismo checklist".
- `docs/referencia.md` es la fuente de verdad del schema `.gate/baseline.json` (schema 1,
  extensión compatible por sección) y del snippet CI. `plugin.json` → v0.3.0.

### Patrones de la casa (base-project)

`.claude/hooks/git-session-status.sh` (SessionStart, ~24 líneas): `set -euo pipefail`,
lee rama actual, si está vacía (fuera de un repo git) `exit 0` sin imprimir nada, si es
`main`/`dev` imprime aviso, si hay working tree sucio lo menciona. Sale siempre `exit 0`
— nunca bloquea, solo imprime texto que Claude Code inyecta como contexto de la sesión.

`.claude/hooks/git-guard.sh` (PreToolUse, matcher `Edit|Write|MultiEdit|NotebookEdit`,
~30 líneas): lee el payload JSON completo por stdin (`cat`), extrae `file_path` con un
`sed` regex (**no jq** — la casa evita dependencias extra), deriva el repo del ARCHIVO
(no del cwd de la sesión, por si es un submódulo), y si la rama ahí es `main`/`dev`
imprime a stdout:

```
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<mensaje>"}}
```

y `exit 0` (el exit code NO es lo que bloquea — es el JSON en stdout con
`permissionDecision: "deny"`). Si no bloquea, no imprime nada y sale `exit 0`. Para el
hook nuevo (`PreToolUse` sobre `Bash` matching `git push`) el payload trae `command` en
vez de `file_path` — mismo mecanismo, hay que extraer y regexear `tool_input.command` en
lugar de `tool_input.file_path`; matcher sería `"matcher": "Bash"` (Claude Code no
matchea por contenido de comando en el campo `matcher` — eso hay que hacerlo adentro del
script, regexeando el `command` del payload, tal como `git-guard.sh` ya regexea
`file_path` en vez de intentar matchear por archivo en el campo `matcher`).

`.claude/settings.json` (base-project) engancha ambos:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/git-session-status.sh\"" }] }],
    "PreToolUse": [{ "matcher": "Edit|Write|MultiEdit|NotebookEdit", "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/git-guard.sh\"" }] }]
  }
}
```

`SessionStart` **no lleva `matcher`** en absoluto (a diferencia de `PreToolUse`) — el
array de `hooks` va directo bajo `SessionStart`.

`/Users/.../Proyectos/.claude/settings.json` (guard de WORKSPACE, un nivel arriba de
todos los repos) solo tiene el `PreToolUse`/`git-guard` — sin `SessionStart`. Esto importa
para el diseño: hay guards a dos niveles (workspace y repo) y el nuevo hook de v0.4.0 va
a nivel REPO únicamente (el workspace no sabe qué repos tienen gate).

`.githooks/pre-push` (base-project) existe pero es **completamente ajeno al gate**: solo
avisa (no bloquea, `sleep 3` y sigue) si un commit `feat:/fix:/refactor:` no tocó
`ai/context/progreso-actual.md`. Es opt-in (`exit 0` si ese archivo no existe en el repo)
y requiere `git config core.hooksPath .githooks`, que **no está configurado** —
confirmado con `git config core.hooksPath` en base-project → sin salida. El punto ciego
señalado en el prompt es real: los devs de la casa pushean vía Claude, así que un hook
git nativo no configurado es letra muerta hoy; el mecanismo que sí corre siempre es
`PreToolUse` sobre `Bash`.

## Tabla — `.claude/settings.json` por repo (los 7 gateados)

| Repo | SessionStart (git-session-status) | PreToolUse Edit/Write (git-guard) | Otros hooks | Plugins/marketplaces declarados |
|---|---|---|---|---|
| base-project-laravel-blade-jquery | sí | sí | — | — |
| pos-llantera-jairo | sí | sí | **PostToolUse** Edit\|Write → `detect-ui-change.js`; PostToolUse Bash → `briefing-detect.sh` | — |
| landing-crb | **no** (sin bloque `hooks` en absoluto) | **no** | — | design-forge, impeccable, inns-ai-flow (`enabledPlugins` + `extraKnownMarketplaces`) |
| landing-urn | **no** | **no** | — | design-forge |
| landing-cursos-urn | sí | sí | — | design-forge, impeccable (conviven `hooks` + `enabledPlugins` en el MISMO settings.json) |
| landing-todopinto | sí | sí | — | — |
| landing-innsolutions | sí | sí | — | — |

Riesgo de convivencia concreto:
- **landing-crb y landing-urn no tienen carpeta `.claude/hooks/` ni bloque `hooks` en
  `settings.json`** — el merge para estos dos es un `settings.json` nuevo con clave
  `hooks` agregada junto al `enabledPlugins`/`extraKnownMarketplaces` existente (no hay
  nada que pisar, pero tampoco hay que borrar las claves de plugins).
- **landing-cursos-urn ya prueba que `hooks` + `enabledPlugins` conviven** en el mismo
  archivo sin problema — sirve de plantilla de merge para landing-crb/landing-urn.
- **pos-llantera-jairo tiene `PostToolUse` con DOS matchers** (`Edit|Write` y `Bash`) —
  el merge para agregar el hook nuevo de v0.4.0 (`PreToolUse` sobre `Bash` matching
  `git push`) tiene que **anidar dentro del array existente de `PreToolUse`** (agregar un
  nuevo objeto `{matcher: "Bash", hooks: [...]}` al array, no reemplazar el `PreToolUse`
  existente que ya tiene el matcher `Edit|Write|MultiEdit|NotebookEdit`) — Claude Code
  permite múltiples entries por evento con distinto `matcher`, confirmado por el propio
  ejemplo de `PostToolUse` en pos-llantera (dos objetos en el array, matchers distintos).
- El repo `release-gate` (este mismo plugin) no vendorea nada sobre sí mismo — no aplica.
- Todos los 7 repos usan la misma ruta de scripts `.claude/hooks/*.sh` y la misma
  convención `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<script>.sh"`.

## Tamaños reales de baseline (para el diseño de `gate-status.sh`)

| Repo | Perfil | Plugin (vendoreado) | phpstan.entradas_baseline | Tamaño baseline.json |
|---|---|---|---|---|
| base-project-laravel-blade-jquery | medida | 0.2.0 | 88 | 3.3k |
| pos-llantera-jairo | medida | 0.1.0 | **903** | 936 bytes (el baseline.json en sí es chico; lo grande es `phpstan-baseline.neon`, el archivo que `gate-status.sh` tendría que contar con `grep -c` sin re-analizar) |
| landing-crb | landing | 0.1.0 | — (landing no tiene phpstan) | 1.3k |
| landing-urn | landing | 0.1.0 | — | 2.5k |
| landing-cursos-urn | landing | 0.1.0 | — | 1.3k |
| landing-todopinto | landing | 0.1.0 | — | 1.4k |
| landing-innsolutions | landing | 0.1.0 | — | 1.3k |

Nota importante: **6 de 7 repos siguen en `plugin: 0.1.0`** en su baseline (solo
base-project subió a 0.2.0) mientras el plugin real está en 0.3.0 — esto es una señal de
drift de versión pendiente, independiente de v0.4.0, pero relevante porque
`gate-status.sh` va a mostrar "versión plugin" leyendo ese campo y hoy reportaría 0.1.0
en 5 de 7 repos aunque el plugin instalado localmente sea 0.3.0. El diseño de
`gate-status.sh` necesita decidir si compara contra `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
(mismo mecanismo que `doctor` usa para drift) para poder avisar "tu vendoreo está atrás".

`pos-llantera-jairo` con 903 entradas en `phpstan-baseline.neon` es el caso de estrés
mencionado en la tarea: contar con `grep -c 'message:' phpstan-baseline.neon` sobre un
archivo de ese tamaño es trivial en < 1s (es un grep de texto plano, no una re-corrida de
PHPStan) — confirma que la estrategia "grep/wc contra baselines y archivos, sin
re-analizar" cumple el objetivo de performance con margen.

## Shape del JSON de `git-guard.sh` (referencia exacta para el hook nuevo)

```bash
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${msg}"
exit 0
```

Cuando NO bloquea: ningún output, `exit 0`. El campo `hookEventName` está hardcodeado a
`"PreToolUse"` (coincide con el evento real). No hay un campo `allow` explícito — la
ausencia de `deny` en el JSON (o la ausencia de output) es la vía "no bloquear".

## Shape del output de `git-session-status.sh` (referencia para gate-status.sh)

Es texto plano a stdout (no JSON) — Claude Code lo inyecta como contexto de la sesión sin
estructura adicional. `gate-status.sh` seguiría el mismo patrón: texto plano, no JSON, con
formato tablero (perfil / versión plugin / baseline vs realidad por herramienta /
mensaje de ratchet / fecha del último gate).

## Riesgos y sorpresas

1. **gate-check.sh no persiste resultado** — la pieza "fecha del último gate" que pide el
   tablero no tiene fuente hoy. Dos caminos sin tocar el script vendoreado: (a) mtime/git-log
   de `.gate/baseline.json` como proxy de "última vez que se tocó el baseline" (no es lo
   mismo que "última vez que corrió el gate", pero es gratis); (b) agregar un
   `.gate/last-run.json` que **el hook PreToolUse de `git push`** escriba después de correr
   el gate exitosamente (el hook YA corre `gate-check.sh` antes de dejar pushear, así que
   es el punto natural para escribir el artefacto, sin tocar `gate-check.sh` en sí). (b) es
   más preciso y no requiere tocar el script "no editar a mano"; se resuelve en el hook, que
   sí es pieza nueva.
2. **Drift de versión ya existente** (5/7 repos en `plugin: 0.1.0` con plugin real en
   0.3.0) contamina cualquier reporte de "versión plugin" en `gate-status.sh` si se lee
   ingenuamente del baseline — puede hacer más ruido de lo esperado si no se explica bien
   en el propio tablero (ej. mostrar ambos: vendoreado vs. disponible).
3. **landing-crb y landing-urn sin ningún hook hoy** — instalar el `SessionStart` y
   `PreToolUse` nuevos ahí es la primera vez que esos dos repos tienen CUALQUIER hook de
   Claude Code. Menor riesgo de colisión (no hay nada que mergear con qué), pero también
   significa que hoy no tienen ni el guard de gitflow (`git-guard` de Edit/Write) — dato
   colateral, no pedido explícitamente pero visible en la tabla.
4. **matcher de `Bash` es amplio** — igual que `briefing-detect.sh` en pos-llantera ya
   matchea TODO `Bash` (no solo comandos de git), el hook nuevo también recibiría CADA
   comando Bash de la sesión y tendría que descartar rápido (regex sobre `command` que no
   sea `git push`) para no agregar latencia perceptible a cada tool call de Bash — esto es
   una restricción de diseño más que un riesgo, pero vale dejarlo explícito: el script
   nuevo corre en el hot path de TODA sesión, no solo en pushes.
5. **doctor.md no tiene una lista declarativa de archivos custodiados** — es prosa
   hardcodeada por paso. Extenderla para las 4 piezas nuevas es coherente con el patrón
   existente pero implica editar `doctor.md` (paso 2/3) para sumar
   `scripts/gate-status.sh`, el hook `SessionStart`, el hook `PreToolUse` git-push y el
   bloque de `CLAUDE.md`, cada uno con su propio checksum/verificación — no hay
   infraestructura previa que generalice esto (por ejemplo, un manifest.json de archivos
   vendoreados); construirla o no es una decisión de diseño abierta para la fase siguiente.
6. **PHPMD/Deptrac/Psalm/PHPStan baselines pueden estar AUSENTES** ("un baseline
   ausente cuenta como cero congelados" — confirmado en `docs/referencia.md`) —
   `gate-status.sh` tiene que manejar el caso "no existe el archivo" como 0, igual que ya
   hacen los scripts de gate-check (`[ -f archivo ] && ... || ACTUALES=0` pattern) — ojo
   con el gotcha de la casa: `[ -f x ] && VAR=... ` bajo `set -e` puede matar el script si
   el `[ -f x ]` es falso (el `&&` corta la cadena con exit status 1); los scripts actuales
   ya resuelven esto con `if [ -f archivo ]; then ...; fi` explícito, no con `&&` — patrón
   a copiar en `gate-status.sh`, no el `[ -f x ] && VAR=...` que rompe bajo `pipefail`.

## Ready for Proposal

Sí. Hay evidencia suficiente para diseñar las 4 piezas: formato exacto del baseline y de
sus archivos satélite, mecanismo probado de ambos tipos de hook (SessionStart texto plano,
PreToolUse JSON `permissionDecision`), la tabla completa de convivencia de hooks por
repo (incluyendo los 2 casos sin ningún hook y el caso con hooks extra en pos-llantera), y
el hueco real de "no hay artefacto de última corrida" con dos alternativas concretas.
Puntos que la propuesta debe decidir explícitamente (no son bloqueantes, son decisiones):
si `gate-status.sh` escribe o no `.gate/last-run.json` (y quién lo escribe), y si
`doctor.md` gana una lista declarativa de archivos custodiados o sigue en prosa.
