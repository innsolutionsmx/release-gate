# Design: v0.4.0 — El gate imposible de ignorar

## Enfoque técnico

Cinco piezas vendoreadas, todas data-driven desde `.gate/baseline.json` (schema 1), todas
bajo la asimetría vigente: **`gate-check.sh` lee y nunca escribe**. Lo que escribe evidencia
es un envoltorio nuevo (`gate-run.sh`), no el checker. Los hooks son rápidos y tontos: nunca
corren análisis, solo leen archivos ya escritos.

    /release-gate:run ──► scripts/gate-run.sh ──► scripts/gate-check.sh (intacto)
                                  │
                                  └──escribe──► .gate/last-run.json  (gitignored)
                                                        ▲          ▲
                          .claude/hooks/gate-push-guard.sh          │ (lee)
                          .claude/hooks/gate-session-status.sh ──► scripts/gate-status.sh
                                                                    │
                                              .gate/baseline.json ──┘
                                              *-baseline.{neon,xml,yaml}

## Hallazgo que corrige el proposal

El proposal asume que el hook de push **corre el gate** antes de dejar pasar. No es viable:

1. Los hooks de Claude Code tienen timeout (60 s por defecto). PHPStan n8 sobre pos-llantera
   (903 entradas) tarda minutos. Subir `timeout` a 600 congela la sesión sin feedback.
2. El proposal también asume que `gate-status.sh` puede detectar "la realidad mejoró" por
   conteo. **Falso**: `grep -c 'message:' phpstan-baseline.neon` cuenta el **archivo de
   baseline**, no la realidad del código. Ese número solo baja si alguien ya regeneró el
   archivo. La realidad verdadera exige correr la herramienta.

Corrección adoptada: el hook **no corre el gate, exige evidencia fresca**; y el tablero
distingue tres columnas (`congelado` | `en archivo` | `realidad`) en vez de mentir con dos.

## Decisiones de arquitectura

| # | Cuestión | Decisión | Alternativas descartadas | Razón |
|---|---|---|---|---|
| 1 | ¿El hook de push bloquea? | **Deny, solo hacia `dev`/`main`, sin correr el gate**: exige `.gate/last-run.json` verde, del commit HEAD, con árbol limpio. Override visible: prefijo `GATE_SKIP=1` en el comando | Deny corriendo el gate (timeout de hook, minutos de bloqueo); aviso no bloqueante (repite el problema actual); deny en toda rama (fricción sin ganancia: CI cubre el PR) | El bloqueo cae donde importa y cuesta <100 ms. El override queda escrito en el transcript = auditable |
| 2 | Realidad de PHPStan / quién escribe `last-run.json` | `gate-status.sh` **nunca** corre análisis: muestra `requiere análisis` para las 4 herramientas de análisis. Lo escribe **`scripts/gate-run.sh`** (envoltorio nuevo, vendoreado), no el hook ni Claude | Que lo escriba el hook (ya no corre el gate); que lo escriba Claude siguiendo `run.md` (no determinista: si el agente se olvida, no hay evidencia); mtime/`git log` de baseline.json (mide "última edición", no "última corrida") | `gate-check.sh` sigue intacto (lee, nunca escribe). El envoltorio es determinista y es el único punto que produce evidencia |
| 3 | Guard por `.gate/baseline.json` en SessionStart | **Sí**, y también en el hook de push. Sin baseline: cero output, `exit 0` | Imprimir un aviso "este repo no tiene gate" (ruido en todo repo no gateado) | Patrón `git-session-status.sh` fuera de un repo git |
| 4 | Merge de hooks en los 7 `settings.json` | **Aditivo idempotente, ejecutado por Claude con Read+Edit** (init/upgrade son markdown), nunca reescribiendo el archivo entero | Normalizar los 7 a una config canónica (pisa hooks ajenos: `PostToolUse` de pos-llantera); merge con `php -r json_encode` (reindenta el archivo entero, churn cosmético en 7 repos) | Preserva `enabledPlugins`, `extraKnownMarketplaces`, indentación y hooks previos |
| 5 | Checksums en `doctor` | Checksum contra `${CLAUDE_PLUGIN_ROOT}` para los 4 scripts nuevos; **presencia** para el bloque de `CLAUDE.md` y las entradas de `settings.json`. `doctor.md` gana una **tabla explícita de archivos custodiados** (sigue siendo prosa; no hay manifiesto JSON) | Manifiesto declarativo `vendored.json` (infraestructura nueva sin consumidor); dejar la lista implícita en la prosa (es el hueco que el explore documentó) | La tabla cierra el hueco sin inventar infraestructura |
| 6 | `.githooks/pre-push` nativo | **No** en v0.4.0 | Instalarlo + `git config core.hooksPath` en los 7 repos | Hoy es letra muerta (`core.hooksPath` sin configurar) y los devs pushean vía Claude. CI sigue siendo la red final |

## `gate-status.sh` — algoritmo y contrato

**Presupuesto: < 300 ms.** Solo `grep -c`, `php -r json_decode` y `git rev-parse`. Cero red,
cero `vendor/bin/*`.

Conteo por herramienta (misma fuente que `gate-check.sh`, sin re-analizar):

| Herramienta | Congelado (baseline.json) | En archivo (`grep -c … \|\| true`) | Perfil |
|---|---|---|---|
| PHPStan | `phpstan.entradas_baseline` | `'message:'` en `phpstan-baseline.neon` | medida |
| Psalm taint | `psalm.entradas_baseline` | `'<code>'` en `psalm-taint-baseline.xml` | ambos |
| PHPMD | `phpmd.entradas_baseline` | `'<violation'` en `phpmd.baseline.xml` | medida |
| Deptrac | `deptrac.entradas_baseline` | `-- '- App'` en `deptrac.baseline.yaml` | medida |

Gotchas obligatorios (v0.2.0, no negociables):
- Todo `grep -c` lleva `|| true`: sin matches devuelve 1 y bajo `pipefail` mata el script.
- Archivo ausente ⇒ 0 con `if [ -f … ]; then … fi` explícito. **Nunca** `[ -f x ] && VAR=…`:
  si es la última sentencia del script o de una función, el AND-list devuelve 1 y el script
  sale con código 1 aunque no haya nada mal.
- `set -euo pipefail` + `cd "$(dirname "$0")/.."`, texto plano a stdout, **siempre `exit 0`**.

"SE PUEDE APRETAR" se dispara con `en_archivo < congelado` para alguna herramienta (el
archivo ya se achicó y el baseline.json quedó atrás), **o** si `last-run.json` trae conteos
menores a los congelados. Nunca se infiere de un análisis que no se corrió.

**Versión de plugin**: se muestran las dos — `vendoreado` (`baseline.plugin`) vs `disponible`
(`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`), con ⚠ si difieren. Es el drift 0.1.0
de 5 repos: v0.4.0 lo **reporta**, no lo corrige. Si `CLAUDE_PLUGIN_ROOT` no está definido
(el hook corre fuera del contexto del plugin), se omite la columna `disponible`, no se falla.

**Fecha del último gate**: `.gate/last-run.json`. Si no existe: `Ultimo gate: sin registro
(corre /release-gate:run)`.

Mockup exacto del output:

```
Release Gate — perfil medida (14 checks)
  Plugin: vendoreado 0.1.0 | disponible 0.4.0  [ATRASADO -> /release-gate:upgrade]
  Ultimo gate: 2026-08-12 14:31 commit a1b2c3d -> APROBADO
               HEAD actual 9f8e7d6: la evidencia esta vieja

  Herramienta    Congelado   En archivo   Realidad
  PHPStan              904          903   requiere analisis
  Psalm taint            0            0   requiere analisis
  PHPMD                  0            0   requiere analisis
  Deptrac                0            0   requiere analisis

  SE PUEDE APRETAR: PHPStan 903 < 904 congeladas -> /release-gate:ratchet
  El baseline no se toca para pasar el gate. Solo se aprieta.
```

Perfil `landing`: solo la fila de Psalm taint. Sin `.gate/baseline.json`: **cero output**.

## `.gate/last-run.json` — schema

```json
{
  "schema": 1,
  "fecha": "2026-08-12T14:31:07-06:00",
  "commit": "a1b2c3d4e5f6...",
  "arbol_limpio": true,
  "veredicto": "APROBADO",
  "perfil": "medida",
  "plugin": "0.4.0",
  "conteos": { "phpstan": 903, "psalm": 0, "phpmd": 0, "deptrac": 0 }
}
```

- **Escribe**: `scripts/gate-run.sh`, siempre (aprobado o bloqueado). **Leen**:
  `gate-status.sh` y `gate-push-guard.sh`. **Ausente** ⇒ ambos degradan sin error
  (status lo dice; el guard deniega pidiendo correr el gate).
- **Va a `.gitignore`** (`init`/`upgrade` agregan la línea `.gate/last-run.json`). Es estado
  local por desarrollador: commitearlo produce conflicto en cada push y evidencia ajena que
  el guard leería como propia. Tradeoff aceptado: en un clon nuevo no hay evidencia y el
  primer push a `dev`/`main` exige una corrida — que es exactamente lo que se quiere.

## Hooks — shapes exactos

`.claude/settings.json` (bloques a agregar, calcados de git-guard / git-session-status):

```json
"SessionStart": [
  { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gate-session-status.sh\"" } ] }
],
"PreToolUse": [
  { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gate-push-guard.sh\"" } ] }
]
```

`SessionStart` **no lleva `matcher`**. `PreToolUse` sí, y `"Bash"` es lo más fino que
permite el campo: el filtrado por contenido va adentro del script.

Bloqueo (idéntico a `git-guard.sh`; el exit code no bloquea, el JSON sí):

```bash
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${msg}"
exit 0
```

Orden de descarte en `gate-push-guard.sh` (corre en el hot path de TODO Bash):

1. `payload="$(cat 2>/dev/null || true)"`; extraer `command` con `sed` (no `jq`), igual que
   `git-guard.sh` extrae `file_path`.
2. Descarte inmediato: `printf '%s' "$cmd" | grep -Eq '(^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)'` — si no, `exit 0` **antes de tocar el disco**. El grupo de opciones globales (`([[:space:]]+-[^[:space:]]+(...)?)*`) admite, por cada repetición, un token de valor separado opcional que no empiece con `-` (cubre `-c clave=valor`, `-C dir`), pero exige que el token inmediato posterior sea `push` — por eso `git stash push` (con o sin `-C dir` antes) nunca matchea: `stash` no puede ser consumido como argumento de una opción que no está presente, y de estarlo, deja de haber un `push` inmediato.
3. `--dry-run` en el comando ⇒ `exit 0`. `GATE_SKIP=1` presente ⇒ `exit 0` (override visible).
4. Sin `.gate/baseline.json` ⇒ `exit 0`.
5. Resolver rama destino: refspec explícito del comando (`git push <remote> <rama>`), si no
   hay, `git branch --show-current`. Si no es `main` ni `dev` ⇒ `exit 0`.
6. Leer `.gate/last-run.json`: `veredicto == APROBADO` **y** `commit == $(git rev-parse HEAD)`
   **y** `arbol_limpio` ⇒ dejar pasar. Si no ⇒ deny con el motivo exacto (sin evidencia /
   bloqueado / commit viejo / árbol sucio) y el fix: `/release-gate:run`.

Falsos positivos/negativos conocidos (aceptados, CI es la red final):

| Caso | Resultado | Nota |
|---|---|---|
| `git add . && git commit -m x && git push` | **detectado** | el regex ancla en `;`/`&`/`\|` |
| `git push --force origin dev` | **detectado y denegado** | `--force` no exime |
| `git push origin feat/x` | permitido | rama no protegida |
| `git -c foo=bar push origin dev` | **detectado** (deny si rama protegida) | el grupo de opciones globales admite un token de valor separado (`-c clave=valor`, `-C dir`, en general `-X valor`) entre `git` y `push` |
| `git -C dir push origin dev` | **detectado** (deny si rama protegida) | mismo mecanismo; `-C` consume `dir` como argumento y `push` sigue siendo el token inmediato exigido |
| `git -C ../otro-repo push origin dev` | **detectado** (deny si rama protegida) | limitación aceptada: el guard evalúa el repo de la **sesión** (`$CLAUDE_PROJECT_DIR`), no el repo apuntado por `-C`; CI del repo real queda como red final |
| `git stash push` / `git -C dir stash push` | permitido | `stash` no empieza con `-`, no hay grupo de opciones que lo consuma como argumento, y `push` deja de ser el token inmediato tras `git`+opciones — nunca matchea |
| `echo "git push origin dev"` | **no matchea**: el ancla de inicio/encadenamiento evita el falso positivo | `git` aparece dentro de la cadena de `echo`, no en posición de inicio de comando ni tras `;`/`&`/`\|` — el allow es el comportamiento correcto, no un hallazgo pendiente |
| comando con `\"` escapadas que rompe el `sed` | **falso negativo** (falla abierto) | limitación heredada de `git-guard.sh` |
| `git push` a un remote no protegido con rama `dev` | denegado | el guard mira la rama, no el remote |

## Merge idempotente de `settings.json` (init / upgrade)

Ejecutado por Claude con Read + Edit, nunca reescribiendo el archivo:

1. Sin `.claude/` ⇒ crear directorio + `settings.json` con **solo** la clave `hooks`.
2. Con archivo pero sin `hooks` (landing-crb, landing-urn) ⇒ agregar la clave `hooks` al
   objeto raíz, **sin tocar** `enabledPlugins` ni `extraKnownMarketplaces`.
3. **Detección de idempotencia**: buscar la subcadena `gate-session-status.sh` /
   `gate-push-guard.sh` en el archivo. Si aparece, la pieza ya está: no se agrega nada.
4. `SessionStart` existente ⇒ **append** de `{ "hooks": [...] }` al array (nunca reemplazo).
5. `PreToolUse` existente ⇒ si hay una entrada con `matcher` exactamente `"Bash"`, se agrega
   el hook a **su** array `hooks`; si no, se agrega una entrada nueva `{matcher:"Bash",…}` al
   array. La entrada `Edit|Write|MultiEdit|NotebookEdit` de `git-guard` no se toca.
6. Verificación post-merge obligatoria: `php -r 'json_decode(...)' ` válido **y** que las
   claves/hooks previos sigan presentes (caso testigo: los dos `PostToolUse` de pos-llantera).

## Bloque de `CLAUDE.md` (borrador completo)

```markdown
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
```

## Cambios por archivo

| Archivo | Acción | Descripción |
|---|---|---|
| `scripts/gate-status.sh` | Crear | Tablero por conteo, `exit 0` siempre |
| `scripts/gate-run.sh` | Crear | Envoltorio: corre `gate-check.sh`, escribe `.gate/last-run.json`, propaga el exit code |
| `scripts/hooks/gate-session-status.sh` | Crear | Hook SessionStart: guard por baseline + invoca `scripts/gate-status.sh` |
| `scripts/hooks/gate-push-guard.sh` | Crear | Hook PreToolUse/Bash: intercepta `git push` a `dev`/`main` |
| `plantillas/claude-md-bloque.md` | Crear | Bloque delimitado de doctrina |
| `commands/init.md` | Modificar | §2 vendorea `gate-status.sh`, `gate-run.sh` y los 2 hooks a `.claude/hooks/` (`chmod +x`); §2c nuevo: merge de `settings.json` (algoritmo de arriba) + bloque en `CLAUDE.md` + `.gate/last-run.json` a `.gitignore` |
| `commands/upgrade.md` | Modificar | §3 propaga las 5 piezas; reemplazo idempotente del bloque `CLAUDE.md` por marcadores; mismo merge de `settings.json` |
| `commands/doctor.md` | Modificar | §3 suma checksums de `gate-status.sh`, `gate-run.sh` y los 2 hooks; §3c nuevo: presencia de las 2 entradas en `settings.json` + del bloque delimitado en `CLAUDE.md` + hooks preexistentes intactos; **tabla de archivos custodiados** |
| `commands/run.md` | Modificar | Invoca `./scripts/gate-run.sh` en vez de `gate-check.sh` |
| `docs/referencia.md` | Modificar | Schema de `.gate/last-run.json`, contrato de hooks, tabla de archivos vendoreados |
| `.claude-plugin/plugin.json` | Modificar | 0.3.0 → 0.4.0 |
| `scripts/gate-check-*.sh` | **Sin cambios** | Sigue leyendo y nunca escribiendo |

Lista nueva de archivos custodiados por `doctor` (checksum salvo donde se indica):
`scripts/gate-check.sh`, `gate-headers.sh`, `gate-lighthouse.sh`, `gate-links.php`,
`gate-status.sh`, `gate-run.sh`, `.claude/hooks/gate-session-status.sh`,
`.claude/hooks/gate-push-guard.sh`, plantillas y `phpstan/Rules/*.php`; **por presencia**:
bloque `CLAUDE.md`, entradas de `settings.json`, línea de `.gitignore`.

## Estrategia de verificación

Sin test runner (config.yaml). Verificación manual reproducible:

| Capa | Qué | Cómo |
|---|---|---|
| Unidad | `gate-status.sh` en los 4 casos | pos-llantera (903 phpstan), una landing, repo sin baseline (output vacío), baseline con archivo achicado (dispara "SE PUEDE APRETAR") |
| Unidad | Regex del guard | Batería de strings de la tabla de falsos positivos contra el script, sin invocar Claude |
| Integración | Merge de `settings.json` | Sobre copias de los 3 casos testigo: base-project (hooks completos), landing-crb (sin `hooks`), pos-llantera (`PostToolUse` con 2 matchers). Correr dos veces = idempotencia |
| Integración | `doctor` | Borrar/mutar cada pieza nueva y confirmar que la detecta |
| E2E | Push bloqueado | Rama `dev` de un repo de prueba, sin `last-run.json`: el push no pasa vía Claude |
| Manifiesto | `validate-manifest.sh` | Tras el bump a 0.4.0 |

Presupuesto de tiempo a verificar: SessionStart < 2 s end-to-end; guard < 100 ms por comando
Bash no-push.

## Rollout

Plugin primero (bump 0.4.0 + `/plugin` + reinicio de Rodrigo), después `/release-gate:upgrade`
repo por repo, empezando por **base-project** (hooks completos, menor riesgo) y terminando por
**pos-llantera** (`PostToolUse` con dos matchers) y **landing-crb/landing-urn** (estrenan
hooks). No se re-mide ningún baseline: v0.4.0 no toca `.gate/baseline.json` salvo el campo
`plugin`.

## Riesgos residuales

| Riesgo | Mitigación |
|---|---|
| `last-run.json` gitignored ⇒ clon nuevo siempre exige una corrida antes del primer push a `dev`/`main` | Es el comportamiento deseado; el mensaje de deny lo explica |
| El guard confía en el commit HEAD: un `git commit --amend` invalida la evidencia | Correcto por diseño (el árbol cambió); el mensaje lo dice |
| `GATE_SKIP=1` se vuelve costumbre | Queda en el transcript; `doctor` puede reportarlo a futuro (deuda anotada) |
| Falso negativo del `sed` con comillas escapadas ⇒ push sin gate | CI sigue bloqueando el merge |
| `PreToolUse` sobre `Bash` agrega latencia a cada comando | Descarte por regex antes de cualquier I/O; medir en pos-llantera |
| `gate-run.sh` es una pieza más que puede driftear | Custodiada por checksum en `doctor` |

## Rollback

1. Revertir el bump a 0.4.0 y el commit del plugin.
2. Por repo: borrar `scripts/gate-status.sh`, `scripts/gate-run.sh`, `.claude/hooks/gate-*.sh`
   y `.gate/last-run.json`; quitar las 2 entradas del array de hooks en `settings.json`
   (dejando intactas las preexistentes); borrar el bloque delimitado de `CLAUDE.md` y la
   línea del `.gitignore`; revertir `run.md` a `gate-check.sh`.
3. `gate-check.sh`, `.gate/baseline.json` y el job de CI quedan **intactos** por diseño: el
   gate sigue funcionando exactamente como en v0.3.0.

## Preguntas abiertas para Rodrigo

- [ ] ¿Se acepta `scripts/gate-run.sh` como **quinta** pieza vendoreada? Es la consecuencia
      de no dejar que el hook corra el gate (Decisión 1+2).
- [ ] Override: ¿`GATE_SKIP=1` o preferís que no exista salida y el único camino sea correr
      el gate?
- [ ] ¿`doctor` debería marcar ⚠ cuando `last-run.json` registra un push con `GATE_SKIP`?
      (hoy `gate-run.sh` no lo registra; sería un campo más del schema).
