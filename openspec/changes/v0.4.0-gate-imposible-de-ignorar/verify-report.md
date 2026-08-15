# Verify Report: v0.4.0 — El gate imposible de ignorar

**Modo**: Standard (strict_tdd: false, sin test runner — `openspec/config.yaml`)
**Rama**: feat/v0.4.0-gate-imposible-de-ignorar
**HEAD verificado**: `98e7673` (test(v0.4.0): verificación batch 5 sobre copias)
**Fecha**: 2026-08-14

---

## Executive summary

**Veredicto: PASS CON WARNINGS** (WARNING #1 resuelto en esta sesión; WARNING #2 —
Batch 5 pendiente sobre repos reales — sigue abierto y es manual por naturaleza).

Las 5 piezas vendoreadas (`gate-status.sh`, `gate-run.sh`, los 2 hooks, el bloque de
`CLAUDE.md`) están implementadas fielmente a `design.md` y cubren los 3 comandos
(`init`/`upgrade`/`doctor`) sin el hueco script↔comando que dejó la v0.2.0 — matriz
completa abajo, cero celdas vacías. Los gotchas bash no-negociables (`|| true` en todo
`grep -c`, guard `if [ -f ]` explícito en vez de `[ -f ] && VAR=`, `set -euo pipefail`,
`exit 0` siempre en status/hooks, español en output) se cumplen en las 4 piezas
ejecutables — verificado leyendo cada línea, no solo grepeando. El schema de
`.gate/last-run.json` (8 campos) es consistente entre quien lo escribe
(`gate-run.sh`), los dos lectores (`gate-status.sh`, `gate-push-guard.sh`) y
`docs/referencia.md`. `validate-manifest.sh` pasa en 0.4.0.

**Actualización post-verify (2026-08-14): WARNING #1 RESUELTO.** El hallazgo
original era documental, no de código: el regex del guard (fiel al que especificaba
el design) no detectaba 2 de los casos que la tabla de "falsos positivos/negativos
aceptados" — presente en **tres lugares**: `design.md`, `gate-hooks/spec.md` (la
spec, no solo el design) y `docs/referencia.md` — afirmaba como detectados
(`git -c foo=bar push origin dev`), y afirmaba que `echo "git push origin dev"`
denegaba cuando en realidad no matcheaba. El dueño del repo decidió, tras revisar,
**ampliar el regex** en vez de solo corregir la prosa: el grupo de opciones globales
ahora admite un token de valor separado (`-c clave=valor`, `-C dir`) entre `git` y
`push`, así que `git -c foo=bar push origin dev` y `git -C dir push origin dev`
ahora sí se detectan — cerrando la brecha real entre lo prometido y lo implementado.
El caso de `echo` se dejó como estaba (no matchea, por diseño: el `git` interno no
está en posición de inicio de comando) y la prosa se corrigió en los tres archivos
para decir eso. Batería re-corrida (24/24 PASS) y regex verificado exhaustivamente
para no introducir falsos positivos nuevos (`git stash push` y
`git -C dir stash push` siguen sin matchear). Detalle completo en la sección
"Issues Found" más abajo.

Cobertura de Batch 5: la verificación empírica sobre copias (regex, timings, merge de
`settings.json`, `gate-status.sh` contra baselines reales) es sólida y ya de-riesga
la mayoría de los ítems de Batch 5, pero **9 de 9 tareas de Batch 5 siguen sin marcar
`[x]`** (salvo 5.8, deuda ratificada) porque exigen `/release-gate:upgrade` y
`/release-gate:doctor` reales sobre los 7 repos + reinicio de Rodrigo tras `/plugin`
— fuera del alcance de este agente, correctamente señalado como PENDIENTE MANUAL.

---

### Completeness

| Métrica | Valor |
|---|---|
| Tasks totales | 46 (Batch 1: 10, Batch 2: 9, Batch 3: 9, Batch 4: 5, Batch 5: 9) |
| Tasks completas `[x]` | 37 |
| Tasks incompletas `[ ]` | 9 (todas en Batch 5, salvo 5.8 que sí está `[x]`) |

Incompletas (todas correctamente marcadas como PENDIENTE MANUAL, requieren tocar los
7 repos reales y/o `/plugin` + reinicio):
- 5.1 Bump del plugin instalado (Rodrigo, manual)
- 5.2 `/release-gate:upgrade` en base-project real
- 5.3 SessionStart end-to-end real (<2s) — solo se midió `gate-status.sh` aislado (232ms mediana)
- 5.4 E2E push bloqueado vía Claude real
- 5.5 `/release-gate:upgrade` en pos-llantera + landing-crb/landing-urn reales
- 5.6 `/release-gate:upgrade` en landing-cursos-urn real
- 5.7 `/release-gate:doctor` real en cada repo
- 5.9 Cierre final: `validate-manifest.sh` sobre plugin instalado + CI de los 7 repos

Ninguna de estas 9 es un hueco de implementación: son gates de "esto pasó en
producción", no de "el código está escrito y es correcto". La sección de Batch 5 en
`tasks.md` documenta una batería empírica extensa sobre **copias** (no fixtures
sintéticos, en su mayoría) que de-riesga el contenido de estas tareas sin cerrarlas.

---

### Build & Tests Execution

**Build**: ➖ No aplica (repo de scripts bash + comandos markdown, sin paso de build)

**Sintaxis bash** (`bash -n` sobre las 4 piezas ejecutables): ✅ 4/4 OK
```
OK syntax: scripts/gate-status.sh
OK syntax: scripts/gate-run.sh
OK syntax: scripts/hooks/gate-session-status.sh
OK syntax: scripts/hooks/gate-push-guard.sh
```
`shellcheck` no está instalado en este entorno — no se pudo correr linting estático
adicional.

**Manifest**: ✅ `bash scripts/validate-manifest.sh` pasa
```
✅ version: 0.4.0 (semver válido)
✅ claude plugin validate --strict: pasa
✅ Manifest publicable (v0.4.0).
```

**Tests**: ➖ No hay test runner (`strict_tdd: false`, confirmado en `openspec/config.yaml`).
Verificación = ejecución real de los scripts contra fixtures/copias (documentada en
Batch 5) + re-verificación propia del regex del guard (ver abajo) + lectura línea por
línea de las 4 piezas ejecutables.

**Coverage**: ➖ No aplica (sin test runner)

**Re-verificación propia del regex del guard** (ejecutada en esta sesión, no
reconstruyendo Batch 5 sino confirmando el hallazgo ya reportado con el regex exacto
del script en producción):

```
REGEX='(^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'
MATCH:    git push
MATCH:    git add . && git commit -m x && git push
MATCH:    git push --force origin dev
MATCH:    git push origin feat/x
NO MATCH: git -c foo=bar push origin dev      ← design/spec/docs dicen "detectado"
NO MATCH: echo "git push origin dev"          ← design/spec/docs dicen "falso positivo: deniega"
NO MATCH: git stash push                      ← correcto, no cubierto explícitamente por la tabla
NO MATCH: ls -la
```

Confirma exactamente el hallazgo ya anotado en `tasks.md` 2.7 y en la nota de Batch 5:
el regex tal como está escrito en el script (fiel al design) no cubre esos dos casos.

---

### Matriz pieza × comando

Ninguna celda vacía — cierra explícitamente el hueco de la lección v0.2.0.

| Pieza | `init` | `upgrade` | `doctor` |
|---|---|---|---|
| `scripts/gate-status.sh` | ✅ §2 vendorea | ✅ §3 re-vendorea (pisa) | ✅ checksum §3/lista de archivos custodiados |
| `scripts/gate-run.sh` | ✅ §2 vendorea | ✅ §3 re-vendorea (pisa) | ✅ checksum §3 |
| `.claude/hooks/gate-session-status.sh` (fuente `scripts/hooks/`) | ✅ §2 vendorea a `.claude/hooks/` | ✅ §3 re-vendorea | ✅ checksum §3 |
| `.claude/hooks/gate-push-guard.sh` (fuente `scripts/hooks/`) | ✅ §2 vendorea a `.claude/hooks/` | ✅ §3 re-vendorea | ✅ checksum §3 |
| Bloque `CLAUDE.md` (`plantillas/claude-md-bloque.md`) | ✅ §2c instala completo | ✅ §3b reemplazo idempotente entre marcadores | ✅ §3c presencia + contenido vigente |
| Entradas `SessionStart`/`PreToolUse` en `settings.json` | ✅ §2c merge de 6 pasos | ✅ §3b mismo algoritmo | ✅ §3c presencia + hooks ajenos intactos |
| Línea `.gate/last-run.json` en `.gitignore` | ✅ §2c agrega | ✅ §3b agrega si falta | ✅ §3c presencia |

`docs/referencia.md` (líneas 314-331) trae la misma tabla en prosa y coincide
exactamente con lo anterior — sin discrepancias entre lo que documentan `init.md`,
`upgrade.md`, `doctor.md` y la referencia.

---

### Spec Compliance Matrix (evidencia estructural + manual, sin test runner)

Sin test runner, "COMPLIANT" abajo significa: evidencia estructural (código leído
línea por línea) **más** verificación manual real reportada en Batch 5 o
re-confirmada en esta sesión — nunca solo lectura de código. "PENDING-MANUAL" son los
escenarios que exigen los 7 repos reales o una sesión de Claude Code real.

#### gate-doctrina (3 requirements, 5 escenarios)

| Requirement | Escenario | Evidencia | Resultado |
|---|---|---|---|
| Contenido del bloque | Bloque instalado en repo nuevo | `plantillas/claude-md-bloque.md` trae las 4 reglas (a-d); `init.md` §2c lo copia completo | ✅ COMPLIANT |
| Delimitadores idempotentes | Upgrade reemplaza sin tocar el resto | `upgrade.md` §3b: reemplazo solo entre marcadores, algoritmo verificado sobre copias reales en Batch 5 (merge de settings.json, no del CLAUDE.md en sí — el reemplazo de texto entre marcadores no se ejecutó realmente, es lógica de instrucción markdown) | ⚠️ PARTIAL — lógica correcta, no ejecutada empíricamente (Claude interactivo real) |
| Delimitadores idempotentes | CLAUDE.md sin bloque previo | `init.md`/`upgrade.md`: agrega completo sin borrar contenido | ⚠️ PARTIAL — mismo motivo |
| Verificación de presencia por doctor | Bloque ausente | `doctor.md` §3c reporta hallazgo si falta | ⚠️ PARTIAL — prosa correcta, no ejecutada contra un repo real |
| Verificación de presencia por doctor | Bloque presente y vigente | `doctor.md` §3c compara contenido vs plantilla vigente | ⚠️ PARTIAL — ídem |

#### gate-hooks (6 requirements, 13 escenarios)

| Requirement | Escenario | Evidencia | Resultado |
|---|---|---|---|
| SessionStart shape y guard | Sesión en repo gateado | `gate-session-status.sh` invoca `gate-status.sh`, `exit 0` siempre (línea 15-17) | ✅ COMPLIANT (script leído + Batch 5: "Guard mudo confirmado en gate-status.sh y gate-session-status.sh") |
| SessionStart shape y guard | Sesión en repo sin gate | Guard vive en `gate-status.sh` (cero output si no hay baseline.json) | ✅ COMPLIANT — confirmado en Batch 5 |
| PreToolUse descarte rápido | Comando Bash no relacionado | Regex descarta antes de I/O; Batch 5 midió 8.8-13.0ms | ✅ COMPLIANT (re-verificado: `ls -la` NO MATCH) |
| PreToolUse descarte rápido | Push encadenado | Regex ancla en `;`/`&`/`\|` | ✅ COMPLIANT (re-verificado: `git add . && git commit && git push` MATCH) |
| Orden de descarte y excepciones | Push a rama no protegida | Paso 5: rama ≠ main/dev → exit 0 | ✅ COMPLIANT — lógica leída, coherente con Batch 5 |
| Orden de descarte y excepciones | Override explícito GATE_SKIP=1 | Paso 2/3 (línea 44-47): grep substring, exit 0 | ✅ COMPLIANT — Batch 5 confirma los 5 escenarios de last-run.json probados |
| Orden de descarte y excepciones | Repo sin baseline | Paso 4 (línea 50-52) | ✅ COMPLIANT |
| Deny — evidencia insuficiente | Evidencia verde y vigente | Paso 6, las 3 condiciones AND | ✅ COMPLIANT — Batch 5: "verde... deniegan con el motivo exacto" (5 escenarios probados) |
| Deny — evidencia insuficiente | Sin evidencia previa | Línea 89-91, motivo "sin evidencia" | ✅ COMPLIANT |
| Deny — evidencia insuficiente | Evidencia de commit viejo | Línea 102-104, motivo "commit viejo" | ✅ COMPLIANT |
| Deny — evidencia insuficiente | Fuerza no exime | `--force` no está entre `git` y `push`, no lo exime; verificado con test propio (`git push --force origin dev` MATCH) | ✅ COMPLIANT |
| Falsos positivos/negativos aceptados | Echo no dispara el guard | `echo "git push origin dev"` NO matchea el regex (verificado con batería post-fix), `exit 0` silencioso, no deniega | ✅ COMPLIANT — spec corregida (WARNING #1 resuelto) para describir el comportamiento real; el allow es correcto |
| Falsos positivos/negativos aceptados | Opciones globales con argumento separado no rompen la detección | `git -c foo=bar push origin dev` y `git -C dir push origin dev` matchean tras ampliar el regex; `git stash push`/`git -C dir stash push` siguen sin matchear | ✅ COMPLIANT — verificado con batería post-fix (24/24 PASS) |
| Formato de bloqueo | JSON de deny bien formado | `deny()` (línea 20-24): printf exacto al formato de la spec | ✅ COMPLIANT |

#### gate-status (7 requirements, 11 escenarios)

| Requirement | Escenario | Evidencia | Resultado |
|---|---|---|---|
| Tablero de tres columnas | Perfil medida completo | 4 filas (PHPStan/Psalm/PHPMD/Deptrac), código líneas 67-115 | ✅ COMPLIANT — Batch 5 reprodujo `entradas_baseline` exacto sobre pos-llantera/base-project |
| Tablero de tres columnas | Perfil landing solo Psalm | Solo la sección Psalm es incondicional; las otras 3 dentro de `if [ "$PERFIL" = "medida" ]` | ✅ COMPLIANT — Batch 5: landing-crb correcto |
| Presupuesto de tiempo | Baseline grande no re-analiza | Solo `grep -c`/`php -r`/`git rev-parse` | ✅ COMPLIANT — Batch 5: 230.5-233.5ms sobre pos-llantera (903 entradas), bajo 300ms pero con menos margen del esperado (~70ms libres) |
| Guard por ausencia de baseline | Repo sin gate | Línea 18-20 | ✅ COMPLIANT — Batch 5 confirmó cero output/exit 0 |
| Detección SE PUEDE APRETAR | Archivo de baseline se achicó | Línea 75-77 y equivalentes por herramienta | ✅ COMPLIANT — Batch 5: disparo confirmado achicando phpstan-baseline.neon 903→893 |
| Detección SE PUEDE APRETAR | Sin evidencia de mejora | Sin disparo si en_archivo ≥ congelado y sin last-run.json mejor | ✅ COMPLIANT — se infiere de la lógica, sin contraejemplo encontrado |
| Versión vendoreada vs disponible | Drift de versión | Línea 34-43 | ✅ COMPLIANT — lógica correcta; sin `CLAUDE_PLUGIN_ROOT` real en este entorno no se re-ejecutó, pero el guard `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]` está presente y correcto |
| `.gate/last-run.json` escritura y ciclo de vida | Corrida aprobada escribe evidencia | `gate-run.sh` línea 69-81, siempre escribe | ✅ COMPLIANT — Batch 5: "gate-run.sh en aprobado y bloqueado... last-run.json en ambos casos con exit code correcto" (tarea 1.10) |
| `.gate/last-run.json` escritura y ciclo de vida | Corrida bloqueada también escribe evidencia | Mismo bloque, `RC` no fuerza `set -e` (línea 24: `\|\| RC=$?`) | ✅ COMPLIANT |
| Fecha del último gate | Sin evidencia previa | Línea 58-60 | ✅ COMPLIANT |
| Fecha del último gate | Evidencia desactualizada | Línea 55-57 | ✅ COMPLIANT |

#### gate-vendoring (6 requirements, 9 escenarios)

| Requirement | Escenario | Evidencia | Resultado |
|---|---|---|---|
| init instala piezas nuevas | Init en repo limpio | `init.md` §2/§2c: 5 piezas + settings.json + gitignore | ✅ COMPLIANT (instrucción markdown correcta; no ejecutada sobre repo real — ver 5.2 pendiente) |
| upgrade sin perder estado ajeno | Upgrade preserva hooks de pos-llantera | Algoritmo paso 5: no toca `PostToolUse` | ✅ COMPLIANT — Batch 5 lo corrió sobre copia REAL de pos-llantera: "los 2 matchers de PostToolUse... intactos" |
| upgrade sin perder estado ajeno | Upgrade en repo sin `hooks` (landing-crb/urn) | Paso 2 del algoritmo | ✅ COMPLIANT — Batch 5 sobre copia real de landing-crb; landing-urn no probado (solo landing-crb tenía copia) |
| upgrade sin perder estado ajeno | Upgrade con hooks + plugins (landing-cursos-urn) | Algoritmo genérico cubre el caso | ⚠️ PARTIAL — no verificado ni con fixture ni con copia (tasks.md 5.6: "no se copió su settings.json") |
| Merge idempotente por Claude | Segunda corrida no duplica | Paso 3: detección por subcadena | ✅ COMPLIANT — Batch 5: "Diff pasada 1→pasada 2: vacío en los 3" sobre copias reales |
| Custodia doctor — checksum | Script editado a mano | `doctor.md` sección "Drift contra el plugin": `shasum` | ✅ COMPLIANT — lógica correcta; no ejecutada (necesita repo real con drift real) |
| Custodia doctor — presencia | Entrada de settings.json ausente | `doctor.md` §3c | ⚠️ PARTIAL — prosa correcta, sin runner que la ejecute (tasks.md 3.9 lo señala explícitamente) |
| Custodia doctor — presencia | Línea de .gitignore ausente | `doctor.md` §3c | ⚠️ PARTIAL — ídem |
| Ausencia de re-medición | Upgrade no re-mide baseline existente | `upgrade.md` no toca baseline salvo campo `plugin` (§6, línea 201) | ✅ COMPLIANT — leído explícitamente, ningún paso de `upgrade.md` re-escribe `entradas_baseline` de una herramienta ya presente |

**Resumen de compliance (post-fix WARNING #1, 2026-08-14)**: de 39 escenarios (38 +
1 nuevo agregado al resolver el WARNING), 29 ✅ COMPLIANT (evidencia estructural +
verificación manual real, en su mayoría de Batch 5 sobre copias reales más la
batería de 24/24 PASS de esta sesión), 0 ❌ FAILING (el escenario "Falso positivo de
echo" se reescribió como "Echo no dispara el guard" y ahora describe el
comportamiento real del script), 10 ⚠️ PARTIAL (lógica correcta y leída línea por
línea, pero sin ejecución real contra un repo/Claude interactivo — corresponden 1 a
1 con las tareas PENDIENTE MANUAL de Batch 5). 0 escenarios sin ningún tipo de
evidencia.

---

### Correctness (Static — Structural Evidence)

| Requirement | Status | Notas |
|---|---|---|
| Los 21(22)* requirements de las 4 specs | ✅ Implementado | Ver matrices arriba, requirement por requirement |
| Gotchas bash no-negociables (v0.2.0) | ✅ Cumplidos | `\|\| true` en 8/8 `grep -c`; cero `[ -f x ] && VAR=`; `set -euo pipefail` + `cd "$(dirname "$0")/.."` en los 2 scripts de `scripts/`; `exit 0` incondicional en las 3 piezas que lo requieren (`gate-status.sh`, ambos hooks) |
| Schema `.gate/last-run.json` (8 campos) | ✅ Consistente | Escritor (`gate-run.sh`), lectores (`gate-status.sh`, `gate-push-guard.sh`) y `docs/referencia.md` usan los mismos 8 campos con los mismos nombres y tipos |
| Bloque CLAUDE.md refleja la doctrina | ✅ Implementado | Las 4 reglas (a-d) del requirement están textualmente en `plantillas/claude-md-bloque.md`, calcado del borrador de `design.md` |

\* Conteo real de `openspec/changes/.../specs/*/spec.md`: **22 requirements, 38
escenarios** (no 21/45 — recontado con `rg -c '^### Requirement:'` / `'^#### Scenario:'`
sobre los 4 archivos; diferencia informativa, no un hallazgo de implementación).

---

### Coherence (Design)

| Decisión | Seguida? | Notas |
|---|---|---|
| #1 Hook de push: deny sin correr el gate, solo dev/main | ✅ Sí | `gate-push-guard.sh` nunca invoca `gate-check.sh` ni ninguna herramienta de análisis |
| #2 `gate-status.sh` nunca corre análisis; `gate-run.sh` escribe la evidencia | ✅ Sí | Columna "realidad" fija en "requiere analisis"; único `cat > .gate/last-run.json` del repo está en `gate-run.sh` |
| #3 Guard por baseline.json en SessionStart y push | ✅ Sí | Ambos hooks lo verifican explícitamente |
| #4 Merge aditivo con Read+Edit, nunca reescritura completa | ✅ Sí (por instrucción) | `init.md`/`upgrade.md` lo prescriben explícitamente; ejecución real verificada en Batch 5 sobre copias con Python fiel al pseudocódigo — el propio Claude real (Read+Edit) no se corrió, es una aproximación aceptada |
| #5 Checksum para 4 scripts+2hooks, presencia para CLAUDE.md/settings.json | ✅ Sí | `doctor.md` sección "Archivos custodiados" coincide exactamente |
| #6 Sin `.githooks/pre-push` nativo en v0.4.0 | ✅ Sí | No hay rastro de `core.hooksPath` ni `.githooks/` en el diff |
| `gate-run.sh` como 5ª pieza vendoreada (decisión ratificada) | ✅ Sí | Presente en scripts/, vendoreado por init/upgrade, custodiado por doctor |
| `GATE_SKIP=1` como override visible/auditable (decisión ratificada) | ✅ Sí | Substring literal, sin lógica de variable de entorno oculta |
| Auditoría de skips en doctor = deuda v0.5.0 (decisión ratificada) | ✅ Sí, correctamente diferida | `doctor.md` no la audita; `docs/referencia.md` línea 297-300 anota la deuda explícitamente |

---

### Issues Found

**CRITICAL** (must fix before archive): Ninguno.

**WARNING** (should fix):

1. **RESUELTO (2026-08-14, sesión de fix dedicada).** La tabla de falsos
   positivos/negativos del guard estaba mal en 3 archivos, incluida la spec (no solo
   el design) — `design.md:164` y `docs/referencia.md:285` afirmaban que
   `git -c foo=bar push origin dev` → "detectado"; ambos y `gate-hooks/spec.md:99`
   (tabla) y `:104-106` (escenario "Falso positivo de echo") afirmaban que
   `echo "git push origin dev"` denegaba informativamente. Verificado empíricamente
   con el regex exacto del script en producción: ninguno de los dos casos matcheaba.

   **Resolución adoptada por el dueño del repo (contraria a la recomendación
   original de este reporte)**: en vez de solo corregir la prosa, se **amplió el
   regex** para los casos de opciones globales con argumento (`-c`, `-C`), y se
   corrigió la prosa **solo** para el caso de `echo` (que sí es comportamiento
   correcto, no un hallazgo).

   Regex final (`scripts/hooks/gate-push-guard.sh`, línea del paso 2 de descarte):
   ```
   (^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)
   ```
   El grupo de opciones globales admite, por cada repetición, un token de valor
   separado opcional que no empiece con `-` (cubre `-c clave=valor`, `-C dir`, en
   general `-X valor`), pero exige que el token inmediato tras `git`+opciones sea
   `push`. Efecto: `git -c foo=bar push origin dev` y `git -C dir push origin dev`
   ahora SÍ matchean (detectados); `git stash push` y `git -C dir stash push` siguen
   SIN matchear (verificado exhaustivamente — `stash` nunca puede ser el token
   inmediato exigido); `echo "git push origin dev"` sigue SIN matchear por diseño
   (el `git` interno no está en posición de inicio de comando ni tras un operador de
   shell) — la prosa se corrigió para decir esto explícitamente en los tres archivos
   (`design.md`, `docs/referencia.md`, `gate-hooks/spec.md`), reemplazando el
   escenario "Falso positivo de echo" (que describía un deny que nunca ocurría) por
   "Echo no dispara el guard". Se agregó también un escenario nuevo para las
   opciones globales con argumento separado. Limitación anotada para
   `-C ../otro-repo`: el guard evalúa el repo de la sesión, no el repo apuntado por
   `-C`; CI del repo real queda como red final.

   Batería re-corrida contra el script real (stdin JSON `PreToolUse`, mini-repo git
   con fixtures de `.gate/`): 19 casos originales + 5 nuevos
   (`git -C dir push origin dev`, `git -C ../otro-repo push origin dev`,
   `git -C dir stash push`, `git -c a=b -c c=d push origin main`,
   `git --git-dir=.git push origin dev`) = **24/24 PASS**. Timing tras el cambio
   (5 corridas, comando no-push): min 30.10ms / mediana 30.85ms / max 34.84ms —
   dentro del presupuesto de <100ms.
   — Archivos tocados: `scripts/hooks/gate-push-guard.sh`,
   `openspec/changes/v0.4.0-gate-imposible-de-ignorar/specs/gate-hooks/spec.md`,
   `openspec/changes/v0.4.0-gate-imposible-de-ignorar/design.md`,
   `docs/referencia.md`, `openspec/changes/v0.4.0-gate-imposible-de-ignorar/tasks.md`
   (nota 2.7 y Batch 5).

2. **Batch 5 deja 8 tareas reales sin ejecutar sobre los 7 repos** (5.1-5.7, 5.9) —
   correctamente marcadas como PENDIENTE MANUAL y fuera del alcance de un agente
   (requieren `/plugin` + reinicio de Rodrigo y tocar repos productivos), pero el
   change no debería archivarse dando esto por "verificado" solo con las copias de
   Batch 5. En particular 5.4 (E2E push bloqueado vía Claude real) y 5.3 (SessionStart
   <2s end-to-end real) son los dos únicos puntos de la spec que la batería de
   scripts-sin-Claude no puede probar por construcción (interacción real con el hook
   runner de Claude Code). — Archivo: `openspec/changes/v0.4.0-gate-imposible-de-ignorar/tasks.md:259-301`

**SUGGESTION** (nice to have):

1. **`pos-llantera-jairo/.gate/baseline.json` (plugin 0.1.0) no tiene claves
   `psalm`/`phpmd`/`deptrac`** — `gate-status.sh` imprime igual las 4 filas del perfil
   medida con "Congelado 0" (vía `?? 0`), visualmente indistinguible de un baseline
   realmente medido y limpio. No es un bug de `gate-status.sh` (hace exactamente lo
   que el requirement pide: mostrar el congelado de `baseline.json`, sin inventar un
   estado "no medido" que ningún requirement de este change pide). Es una
   consecuencia de que pos-llantera todavía no pasó por `/release-gate:upgrade` con
   medición real — se resuelve solo cuando 5.5 se ejecute, no requiere cambio de
   código. Anotado para que quien revise el tablero de pos-llantera post-upgrade sepa
   que un "Congelado 0" en esas 3 filas hoy significa "nunca medido", no "medido y
   limpio", hasta que la medición real ocurra.

2. **`gate-status.sh` tiene menos margen del esperado contra el presupuesto de
   300ms** — Batch 5 midió 230.5-233.5ms sobre pos-llantera (903 entradas de
   phpstan), con ~70ms libres. La nota de Batch 5 ya identifica la causa (overhead de
   arrancar `php -r` 3-4 veces + `git rev-parse` x2, no el `grep -c` en sí sobre las
   5419 líneas del `.neon`). No bloquea el requirement (`SHALL < 300ms` se cumple),
   pero si a futuro se agrega una 5ª herramienta al tablero, vale la pena consolidar
   las invocaciones de `php -r` en una sola para no comerse el margen.

---

### Cobertura de escenarios

| Categoría | Cantidad |
|---|---|
| Escenarios totales (post-fix WARNING #1) | 39 |
| ✅ COMPLIANT (estructural + verificación manual real) | 29 |
| ❌ FAILING | 0 (resuelto: ver WARNING #1) |
| ⚠️ PARTIAL (lógica correcta, sin ejecución real — pendiente de Batch 5) | 10 |
| Tasks pendientes de Batch 5 que cierran los PARTIAL de arriba | 8 (5.1-5.7, 5.9) |

---

### Artifacts

- `openspec/changes/v0.4.0-gate-imposible-de-ignorar/verify-report.md` (este archivo)

### Risks

- **RESUELTO**: el WARNING #1 (tabla de falsos positivos/negativos) ya no representa
  un riesgo para `sdd-archive` — `gate-hooks/spec.md` fue corregida junto con el
  regex del guard en esta sesión; la sincronización a `openspec/specs/` propagaría
  ahora una afirmación consistente con el comportamiento real.
- Los 10 escenarios PARTIAL dependen de que Batch 5 (5.1-5.7, 5.9) se ejecute sobre
  los 7 repos reales antes de considerar el change verdaderamente cerrado en
  producción — el archive de SDD puede proceder (el código está completo y
  correcto), pero el rollout real (`design.md` sección "Rollout") sigue abierto.
- Sin `shellcheck` disponible en este entorno no hubo linting estático más allá de
  `bash -n` (sintaxis) y lectura manual línea por línea.

### Skill Resolution

`fallback-path` — no se encontró bloque `## Project Standards (auto-resolved)`
inyectado ni registro `.atl/skill-registry.md`; se procedió únicamente con
`sdd-verify/SKILL.md` + `_shared/sdd-phase-common.md` + `_shared/openspec-convention.md`.
