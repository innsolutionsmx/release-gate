# Gate Hooks Specification

## Purpose

Los hooks vendoreados de Claude Code que llevan el gate al camino del desarrollador: un
`SessionStart` informativo (invoca `gate-status.sh`) y un `PreToolUse` sobre `Bash` que
exige evidencia fresca antes de dejar pasar un `git push` a rama protegida. Ninguno de los
dos ejecuta análisis: solo leen archivos ya escritos.

## Requirements

### Requirement: Hook SessionStart — shape y guard
`.claude/hooks/gate-session-status.sh` SHALL registrarse en `settings.json` bajo
`SessionStart` **sin** campo `matcher`. SHALL invocar `scripts/gate-status.sh` y SHALL
terminar siempre con `exit 0`. Si `.gate/baseline.json` no existe, SHALL producir cero
output (delegado en el guard de `gate-status.sh`).

#### Scenario: Sesión en repo gateado
- GIVEN un repo con `.gate/baseline.json`
- WHEN arranca una sesión de Claude Code
- THEN el hook imprime el tablero de `gate-status.sh` como contexto de sesión

#### Scenario: Sesión en repo sin gate
- GIVEN un repo sin `.gate/baseline.json`
- WHEN arranca una sesión de Claude Code
- THEN el hook no imprime nada y sale con código 0

### Requirement: Hook PreToolUse — descarte rápido en el hot path
`.claude/hooks/gate-push-guard.sh` SHALL registrarse bajo `PreToolUse` con
`matcher: "Bash"` y SHALL recibir CADA comando Bash de la sesión. El script MUST descartar,
antes de cualquier I/O a disco, todo comando cuyo `tool_input.command` no matchee el regex
`(^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)`,
saliendo con `exit 0` sin output.

#### Scenario: Comando Bash no relacionado
- GIVEN el comando `ls -la`
- WHEN el hook procesa el payload
- THEN sale con `exit 0` sin tocar el disco ni imprimir output

#### Scenario: Push encadenado con otros comandos
- GIVEN el comando `git add . && git commit -m x && git push`
- WHEN el hook procesa el payload
- THEN detecta el `git push` (el regex ancla en `&&`)

### Requirement: Orden de descarte y excepciones
Tras detectar `git push`, el script SHALL seguir en orden: (1) `--dry-run` en el comando ⇒
`exit 0`; (2) variable `GATE_SKIP=1` presente en el comando ⇒ `exit 0` (override visible en
el transcript); (3) sin `.gate/baseline.json` ⇒ `exit 0`; (4) rama destino distinta de
`main`/`dev` ⇒ `exit 0`.

#### Scenario: Push a rama no protegida
- GIVEN `git push origin feat/x`
- WHEN el hook resuelve la rama destino
- THEN permite el push sin evaluar evidencia

#### Scenario: Override explícito
- GIVEN `GATE_SKIP=1 git push origin dev`
- WHEN el hook detecta la variable
- THEN permite el push y el override queda en el transcript de la sesión

#### Scenario: Repo sin baseline
- GIVEN un repo sin `.gate/baseline.json` y `git push origin main`
- WHEN el hook evalúa el paso 3
- THEN permite el push sin evaluar `.gate/last-run.json`

### Requirement: Deny — evidencia insuficiente
Para un `git push` a `main`/`dev` con baseline presente, el script SHALL denegar (vía JSON
`permissionDecision: "deny"`, nunca por exit code no-cero) salvo que
`.gate/last-run.json` exista con `veredicto == "APROBADO"`, `commit` igual al HEAD actual, y
`arbol_limpio == true`. El mensaje de deny SHALL indicar el motivo exacto (sin evidencia,
bloqueado, commit viejo, o árbol sucio) y el fix (`/release-gate:run`).

#### Scenario: Evidencia verde y vigente
- GIVEN `.gate/last-run.json` con `veredicto: APROBADO`, commit igual al HEAD y árbol limpio
- WHEN corre `git push origin dev`
- THEN el hook no imprime `deny` y el push procede

#### Scenario: Sin evidencia previa
- GIVEN un repo con baseline pero sin `.gate/last-run.json`
- WHEN corre `git push origin main`
- THEN el hook deniega con el motivo "sin evidencia" y sugiere `/release-gate:run`

#### Scenario: Evidencia de un commit viejo
- GIVEN `.gate/last-run.json` con `commit: a1b2c3d` y HEAD actual `9f8e7d6` (post-amend)
- WHEN corre `git push origin dev`
- THEN el hook deniega con el motivo "commit viejo"

#### Scenario: Fuerza no exime
- GIVEN evidencia ausente
- WHEN corre `git push --force origin dev`
- THEN el hook detecta el push y deniega igual que sin `--force`

### Requirement: Falsos positivos y negativos aceptados
El regex del guard SHALL aceptar los siguientes casos conocidos como comportamiento
esperado (CI queda como red final):

| Caso | Resultado |
|---|---|
| `echo "git push"` / heredoc con `git push` literal | Falso positivo: deny informativo, override disponible |
| Comando con comillas escapadas que rompe el `sed` de extracción | Falso negativo: falla abierto (limitación heredada de `git-guard.sh`) |
| `git push` a remote no protegido con rama `dev` | Denegado — el guard mira la rama destino, no el remote |

#### Scenario: Falso positivo de echo
- GIVEN el comando `echo "git push origin dev"`
- WHEN el hook lo procesa
- THEN deniega informativamente aunque no sea un push real; el override `GATE_SKIP=1` lo destraba

### Requirement: Formato de bloqueo
Cuando deniega, el script SHALL imprimir exactamente
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<mensaje>"}}`
y SHALL terminar con `exit 0` (el exit code nunca bloquea; el JSON sí).

#### Scenario: JSON de deny bien formado
- GIVEN un push denegado por evidencia ausente
- WHEN el hook produce su salida
- THEN el JSON es válido y contiene `permissionDecision: "deny"` con el motivo en `permissionDecisionReason`
