# Tasks: v0.4.0 — El gate imposible de ignorar

> ✅ **DESBLOQUEADO** — Rodrigo resolvió las 3 decisiones abiertas del design:
> 1. `gate-run.sh` ENTRA como 5ª pieza vendoreada.
> 2. Override `GATE_SKIP=1` visible/auditable: SÍ (substring literal en el comando).
> 3. Auditoría de skips en `doctor`: DEUDA para v0.5.0 (NO en esta release; ver tarea 5.8).
> 4. Ruta de los hooks: en el PLUGIN viven en `scripts/hooks/gate-*.sh`; su destino vendoreado
>    en repos gateados es `.claude/hooks/gate-*.sh`. Las tareas de Batch 2 usan la ruta del
>    plugin (`scripts/hooks/`); Batch 3 (`commands/init.md`/`upgrade.md`) es responsable de
>    vendorearlos a `.claude/hooks/` en el repo consumidor.
>
> Batches 1, 2, 3 y 4 implementados y verificados manualmente (ver checkboxes). Batch 5
> (verificación end-to-end sobre los repos testigo reales + bump del plugin instalado por
> Rodrigo) queda pendiente para una sesión posterior — requiere `/plugin` + reinicio de
> Rodrigo y tocar los 7 repos gateados reales, fuera del alcance de un agente.

## Batch 1: Scripts nuevos — gate-status.sh y gate-run.sh

- [x] 1.1 Crear `scripts/gate-status.sh`: guard por ausencia de `.gate/baseline.json` (cero
      output, `exit 0`). — *gate-status: Requirement "Guard por ausencia de baseline"*
- [x] 1.2 Implementar conteo por herramienta (`grep -c ... || true`, guard `if [ -f ]` explícito,
      nunca `[ -f ] && VAR=`) para PHPStan/Psalm/PHPMD/Deptrac según perfil activo (medida = 4
      filas, landing = solo Psalm). — *gate-status: "Tablero de tres columnas", escenarios
      "Perfil medida completo" y "Perfil landing solo Psalm"*
- [x] 1.3 Columna "realidad" fija en `requiere analisis` para las 4 herramientas; el script
      MUST NOT ejecutar ninguna herramienta de análisis. — *gate-status: "Tablero de tres
      columnas"*
- [x] 1.4 Lógica "SE PUEDE APRETAR": disparar cuando `en_archivo < congelado` para alguna
      herramienta, o cuando `.gate/last-run.json` trae conteos menores a los congelados.
      — *gate-status: "Detección de SE PUEDE APRETAR", escenarios "Archivo de baseline se
      achicó" y "Sin evidencia de mejora"*
- [x] 1.5 Columna versión: `baseline.plugin` (vendoreado) vs
      `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (disponible), marca ⚠ si difieren; si
      `CLAUDE_PLUGIN_ROOT` no está definida, omitir columna sin fallar. — *gate-status:
      "Versión vendoreada vs disponible", escenario "Drift de versión"*
- [x] 1.6 Sección fecha del último gate: leer `.gate/last-run.json`; sin archivo → "Ultimo
      gate: sin registro (corre /release-gate:run)"; commit distinto al HEAD → advertencia de
      evidencia vieja. — *gate-status: "Fecha del último gate en el tablero", escenarios "Sin
      evidencia previa" y "Evidencia desactualizada"*
- [x] 1.7 Cerrar `gate-status.sh` con `set -euo pipefail`, `cd "$(dirname "$0")/.."`, texto
      plano a stdout, `exit 0` siempre. Verificar presupuesto <300ms sin overhead de Claude
      Code. — *gate-status: "Presupuesto de tiempo", escenario "Baseline grande no re-analiza"*
- [x] 1.8 ⚠ Crear `scripts/gate-run.sh`: correr `gate-check.sh` intacto (sin modificarlo),
      capturar su exit code, escribir siempre `.gate/last-run.json` (aprobado o bloqueado) con
      schema `{schema, fecha, commit, arbol_limpio, veredicto, perfil, plugin, conteos}`, y
      propagar el exit code original. — *gate-status: "`.gate/last-run.json` — escritura y
      ciclo de vida", escenarios "Corrida aprobada escribe evidencia" y "Corrida bloqueada
      también escribe evidencia"*. Resuelto por Rodrigo: SÍ se acepta como 5ª pieza vendoreada.
- [x] 1.9 Agregar `.gate/last-run.json` a `.gitignore` del repo consumidor. — *gate-status:
      "`.gate/last-run.json` — escritura y ciclo de vida" (SHALL estar en .gitignore)*.
      Cerrado en Batch 3: `commands/init.md` §2c agrega la línea en repo nuevo,
      `commands/upgrade.md` §3b la agrega si falta (sin duplicar).
- [x] 1.10 Verificación manual de cierre de batch: correr `gate-status.sh` en pos-llantera
      (903 phpstan) y medir <300ms; correr en un repo sin `.gate/baseline.json` y confirmar
      output vacío + exit 0; simular archivo de baseline achicado y confirmar aviso "SE PUEDE
      APRETAR"; correr `gate-run.sh` en aprobado y bloqueado y confirmar `last-run.json` en
      ambos casos con exit code correcto. Correr `bash scripts/validate-manifest.sh` (no debe
      romper: aún no tocamos el manifiesto en este batch).

## Batch 2: Plantillas de hooks + bloque CLAUDE.md

> Nota de ubicación (Decisión ratificada #4 de Rodrigo): en el PLUGIN los hooks viven como
> `scripts/hooks/gate-session-status.sh` y `scripts/hooks/gate-push-guard.sh`; su destino
> vendoreado en repos gateados (tarea de Batch 3, `commands/init.md`/`upgrade.md`) es
> `.claude/hooks/gate-*.sh`. Las tareas de abajo se implementaron en la ruta del PLUGIN.

- [x] 2.1 Crear `scripts/hooks/gate-session-status.sh` (fuente en el plugin; destino vendoreado
      `.claude/hooks/gate-session-status.sh`): registrable bajo `SessionStart` sin `matcher`,
      invoca `scripts/gate-status.sh`, termina siempre `exit 0`; sin `.gate/baseline.json`
      produce cero output (delegado al guard de gate-status.sh). — *gate-hooks: "Hook
      SessionStart — shape y guard", escenarios "Sesión en repo gateado" y "Sesión en repo sin
      gate"*
- [x] 2.2 Crear `scripts/hooks/gate-push-guard.sh` (fuente en el plugin; destino vendoreado
      `.claude/hooks/gate-push-guard.sh`) — paso 1: leer payload de stdin, extraer
      `tool_input.command` con `sed` (no `jq`, réplica del patrón `git-guard.sh` descrito en el
      design — `git-guard.sh` no está en este repo, no se pudo comparar byte a byte). —
      *gate-hooks: "Hook PreToolUse — descarte rápido en el hot path"*
- [x] 2.3 Descarte inmediato por regex antes de tocar disco: solo continúa si el comando
      matchea `(^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)`.
      — *gate-hooks: "Hook PreToolUse — descarte rápido...", escenarios "Comando Bash no
      relacionado" y "Push encadenado con otros comandos"*
- [x] 2.4 Orden de excepciones tras detectar push: (1) `--dry-run` → exit 0; (2)
      `GATE_SKIP=1` presente en el comando → exit 0 (override visible en transcript); (3) sin
      `.gate/baseline.json` → exit 0; (4) rama destino ≠ `main`/`dev` → exit 0. — *gate-hooks:
      "Orden de descarte y excepciones", escenarios "Push a rama no protegida", "Override
      explícito", "Repo sin baseline"*. Resuelto por Rodrigo: `GATE_SKIP=1` como prefijo/substring
      literal del comando, visible/auditable en el transcript.
- [x] 2.5 Resolver rama destino: refspec explícito del comando si está, si no
      `git branch --show-current`; deny (JSON `permissionDecision: deny`, nunca exit code) si
      no hay `.gate/last-run.json` con `veredicto == APROBADO`, `commit == HEAD` y
      `arbol_limpio`; mensaje de deny con motivo exacto (sin evidencia / bloqueado / commit
      viejo / árbol sucio) y fix `/release-gate:run`. — *gate-hooks: "Deny — evidencia
      insuficiente", escenarios "Evidencia verde y vigente", "Sin evidencia previa",
      "Evidencia de un commit viejo", "Fuerza no exime"*
- [x] 2.6 Formato exacto de bloqueo:
      `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<mensaje>"}}`
      seguido de `exit 0`. — *gate-hooks: "Formato de bloqueo", escenario "JSON de deny bien
      formado"*
- [x] 2.7 Validar contra la tabla de falsos positivos/negativos aceptados del design (echo con
      `git push` literal, comillas escapadas que rompen el sed, push a remote no protegido con
      rama `dev`) — no requiere código nuevo, es criterio de aceptación del script ya escrito.
      — *gate-hooks: "Falsos positivos y negativos aceptados", escenario "Falso positivo de
      echo"*. **Hallazgo de verificación**: con el regex EXACTO del design, `echo "git push
      origin dev"` y `git -c foo=bar push origin dev` NO se detectan como push (ver sección de
      desvíos del reporte de apply) — el regex ancla `git` a inicio de comando o a un operador
      de shell, y el grupo de flags no admite pares `-x valor`. La tabla de falsos
      positivos/negativos del design asume que SÍ se detectan. Implementado el regex tal cual
      el design lo especifica (fidelidad al spec); discrepancia reportada para revisión de
      Rodrigo, no corregida unilateralmente.
- [x] 2.8 Crear `plantillas/claude-md-bloque.md` con el bloque delimitado por
      `<!-- release-gate:inicio -->` / `<!-- release-gate:fin -->` y las 4 reglas de doctrina
      (baseline no se edita, ratchet aprieta, scripts no se editan a mano, push sin corrida
      verde queda bloqueado). — *gate-doctrina: "Contenido del bloque", escenario "Bloque
      instalado en repo nuevo"*
- [x] 2.9 Verificación manual de cierre de batch: batería de strings de la tabla de falsos
      positivos/negativos contra `gate-push-guard.sh` sin invocar Claude (comando no-push,
      push encadenado, `--dry-run`, `GATE_SKIP=1`, `--force`, rama no protegida, `echo "git
      push"`, comando con comillas escapadas); medir tiempo de descarte de un comando no-push
      (<100ms, medido ~10ms). `bash scripts/validate-manifest.sh` no debe fallar (pasa, sin
      tocar el manifiesto en este batch).

## Batch 3: Comandos init/upgrade/doctor + run.md

- [x] 3.1 Modificar `commands/init.md` §2: vendorear `gate-status.sh`, `gate-run.sh` y los 2
      hooks a `.claude/hooks/` con `chmod +x` sobre los `.sh`. — *gate-vendoring: "`init`
      instala las piezas nuevas", escenario "Init en repo limpio"*
- [x] 3.2 Agregar `commands/init.md` §2c (nuevo): algoritmo de merge de `settings.json`
      ejecutado por Claude con Read+Edit — sin `.claude/` crea directorio+archivo solo con
      `hooks`; con archivo sin `hooks` agrega la clave sin tocar `enabledPlugins`/
      `extraKnownMarketplaces`; detección de idempotencia por subcadena
      `gate-session-status.sh`/`gate-push-guard.sh`; `SessionStart` existente → append;
      `PreToolUse` existente con matcher `"Bash"` → agrega al array de ese matcher, si no
      existe crea la entrada nueva sin tocar la de `git-guard`; verificación post-merge con
      `php -r json_decode` + claves previas presentes. — *gate-vendoring: "`init` instala las
      piezas nuevas"; "Merge idempotente ejecutado por Claude"*
- [x] 3.3 `commands/init.md` §2c: instalar bloque de doctrina en `CLAUDE.md` (agregar completo
      con marcadores si no existen, sin eliminar contenido previo del repo) y agregar
      `.gate/last-run.json` a `.gitignore`. — *gate-doctrina: "CLAUDE.md sin bloque previo";
      gate-vendoring: "`init` instala las piezas nuevas"*
- [x] 3.4 Modificar `commands/upgrade.md` §3: re-vendorear las 5 piezas pisando versiones
      anteriores de scripts propios; reemplazo idempotente del bloque `CLAUDE.md` solo entre
      marcadores (resto del archivo intacto); mismo algoritmo de merge aditivo de
      `settings.json` que init (§3.2, ahora §3b de upgrade); MUST NOT re-medir baseline
      existente ni eliminar hooks/plugins/marketplaces preexistentes. — *gate-vendoring:
      "`upgrade` propaga sin perder estado ajeno", escenarios "Upgrade preserva hooks de la
      casa (pos-llantera)", "Upgrade en repo sin bloque hooks (landing-crb, landing-urn)",
      "Upgrade en repo con hooks + plugins declarados (landing-cursos-urn)", "Segunda corrida
      no duplica"; gate-doctrina: "Upgrade reemplaza el bloque sin tocar el resto del archivo";
      gate-vendoring: "Ausencia de re-medición", escenario "Upgrade no re-mide baseline
      existente"*
- [x] 3.5 Modificar `commands/doctor.md` §3: sumar checksum (`shasum` contra
      `${CLAUDE_PLUGIN_ROOT}`) de `gate-status.sh`, `gate-run.sh` y los 2 hooks a la lista
      existente. — *gate-vendoring: "Custodia de doctor — checksum", escenario "Script editado
      a mano"*
- [x] 3.6 Agregar `commands/doctor.md` §3c (nuevo): verificación por presencia (no checksum) de
      las 2 entradas de hooks en `settings.json`, del bloque delimitado en `CLAUDE.md`, y de la
      línea `.gate/last-run.json` en `.gitignore`; confirmar que hooks preexistentes ajenos
      siguen intactos. — *gate-vendoring: "Custodia de doctor — presencia", escenarios "Entrada
      de settings.json ausente" y "Línea de .gitignore ausente"; gate-doctrina: "Verificación
      de presencia por doctor", escenarios "Bloque ausente" y "Bloque presente y vigente"*
- [x] 3.7 Agregar a `commands/doctor.md` una tabla explícita en prosa de archivos custodiados
      (checksum: `gate-check.sh`, `gate-headers.sh`, `gate-lighthouse.sh`, `gate-links.php`,
      `gate-status.sh`, `gate-run.sh`, `.claude/hooks/gate-session-status.sh`,
      `.claude/hooks/gate-push-guard.sh`, plantillas, `phpstan/Rules/*.php`; presencia: bloque
      `CLAUDE.md`, entradas de `settings.json`, línea de `.gitignore`) — sin manifiesto JSON
      declarativo. — *gate-vendoring: "Custodia de doctor — presencia" (SHALL incluir tabla
      explícita)*
- [x] 3.8 ⚠ Modificar `commands/run.md`: invocar `./scripts/gate-run.sh` en vez de
      `gate-check.sh` directamente. — *gate-status: "`.gate/last-run.json` — escritura y ciclo
      de vida"; consistente con el diagrama del design (`/release-gate:run` → `gate-run.sh`)*.
      Decisión abierta #1 de Rodrigo resuelta: SÍ, `gate-run.sh` es la 5ª pieza vendoreada.
- [x] 3.9 Verificación manual de cierre de batch: sobre **fixtures sintéticos** de los 3 casos
      testigo (base-project con `SessionStart`+`PreToolUse:"Bash"` completos incluyendo
      `git-guard`, landing-crb sin clave `hooks` con `enabledPlugins`/`extraKnownMarketplaces`,
      pos-llantera con `PostToolUse` de 2 matchers ajenos) — NO sobre los repos reales, per
      instrucción explícita — se implementó el algoritmo de 6 pasos en PHP tal cual está escrito
      en `commands/init.md`/`upgrade.md` y se corrió DOS veces sobre cada fixture. Resultado:
      cero duplicados en la segunda corrida (detección por subcadena funciona), `git-guard`
      sigue intacto y el hook nuevo se agrega a SU MISMO array `hooks` (matcher `"Bash"`
      compartido), `enabledPlugins`/`extraKnownMarketplaces` de landing-crb intactos, los 2
      matchers de `PostToolUse` de pos-llantera intactos y `SessionStart`/`PreToolUse` nuevos
      agregados sin tocarlos. JSON válido en las 3 salidas. La mutación pieza-por-pieza contra
      `doctor` (script/hook/bloque CLAUDE.md/entrada settings.json/línea .gitignore) NO se
      ejecutó — `doctor.md` es prosa para un futuro Claude interactivo, no hay runner
      automatizado para simularla sin invocar el comando real; queda para Batch 5 (5.7, sobre
      repos reales). Cerrado con `bash scripts/validate-manifest.sh` (`claude plugin validate
      --strict`) → pasa en 0.4.0.

## Batch 4: docs/referencia.md y bump de versión 0.4.0

- [x] 4.1 Modificar `docs/referencia.md`: documentar schema de `.gate/last-run.json` (los 7
      campos: `schema, fecha, commit, arbol_limpio, veredicto, perfil, plugin, conteos`).
      — *gate-status: "`.gate/last-run.json` — escritura y ciclo de vida"*
- [x] 4.2 `docs/referencia.md`: documentar contrato de los 2 hooks (SessionStart sin matcher +
      guard por baseline; PreToolUse/Bash con orden de descarte, deny JSON, tabla de falsos
      positivos/negativos). — *gate-hooks: todos los requirements*
- [x] 4.3 `docs/referencia.md`: agregar/actualizar tabla de archivos vendoreados incluyendo las
      5 piezas nuevas y qué operación (init/upgrade/doctor) las toca. — *gate-vendoring:
      "`init` instala las piezas nuevas"; "`upgrade` propaga..."; "Custodia de doctor"*
- [x] 4.4 Modificar `.claude-plugin/plugin.json`: bump `version` de `0.3.0` a `0.4.0`.
      — *gate-vendoring: contexto general del change (v0.4.0); design "Rollout" (bump antes de
      `/plugin` + reinicio)*
- [x] 4.5 Verificación manual de cierre de batch: `bash scripts/validate-manifest.sh`
      (`claude plugin validate --strict`) debe pasar con el manifiesto en 0.4.0 → **pasa**
      (`✅ version: 0.4.0 (semver válido)`, `✅ claude plugin validate --strict: pasa`); revisión
      visual de que `docs/referencia.md` no contradice ninguna de las 4 specs (gate-status,
      gate-hooks, gate-vendoring, gate-doctrina) → sin contradicciones, contenido calcado del
      design.md ratificado.

## Batch 5: Verificación manual end-to-end en repo testigo

> **Verificación empírica sobre COPIAS (sesión 2026-08-14)** — batería completa corrida bajo
> `/private/tmp/.../scratchpad/batch5/`, sin tocar ningún repo real. Resultados (de-riesga los
> ítems 5.2–5.7/5.9 pero NO los cierra: esos exigen `/release-gate:upgrade` y `/release-gate:doctor`
> reales sobre los 7 repos, fuera del alcance de este agente):
> - **Regex del guard**: batería de 14+ casos contra `gate-push-guard.sh` (payload JSON de
>   `PreToolUse` por stdin) — todos PASS contra el comportamiento documentado en el design,
>   confirmando el hallazgo ya anotado en 2.7: `echo "git push origin dev"` y
>   `git -c foo=bar push origin dev` NO se detectan (la tabla de falsos positivos/negativos del
>   design dice que sí deberían). `git stash push` tampoco matchea (correcto, no es push remoto,
>   caso no cubierto explícitamente por la tabla). Los 5 escenarios de `last-run.json` (verde,
>   rojo/BLOQUEADO, commit distinto, árbol sucio, sin evidencia) deniegan con el motivo exacto
>   documentado.
> - **`gate-status.sh` contra baselines reales (copias)**: pos-llantera-jairo (medida, 903
>   PHPStan) y base-project (medida, 88 PHPStan + psalm/phpmd/deptrac en 0) reproducen EXACTO
>   el `entradas_baseline` congelado; landing-crb (landing, solo Psalm) también correcto.
>   **Hallazgo**: `pos-llantera-jairo/.gate/baseline.json` (plugin 0.1.0, `congelado: 2026-08-10`)
>   NO tiene las claves `psalm`/`phpmd`/`deptrac` — son anteriores a que existieran esos checks.
>   `gate-status.sh` igual imprime las 4 filas del perfil medida con "Congelado 0" (vía `?? 0`)
>   para las tres ausentes, indistinguible visualmente de un baseline realmente medido en 0. No
>   es un bug del script (hace lo que el design pide), pero pos-llantera necesita pasar por
>   `/release-gate:upgrade` + medición real antes de que esas filas signifiquen algo.
>   "SE PUEDE APRETAR" se disparó correctamente al achicar artificialmente
>   `phpstan-baseline.neon` (903→893). Guard mudo (sin `.gate/baseline.json`) confirmado en
>   `gate-status.sh` y `gate-session-status.sh`: cero output, exit 0.
> - **Timing**: `gate-status.sh` sobre la copia de pos-llantera, 5 corridas (Python
>   `time.perf_counter`): min 230.5 ms, mediana 232.3 ms, max 233.5 ms — **por debajo del
>   presupuesto de 300 ms pero con menos margen del esperado** (~70 ms libres; la mayor parte es
>   overhead de arrancar `php -r` 3–4 veces + `git rev-parse` x2, no el `grep -c` sobre las 5419
>   líneas del `.neon`). `gate-push-guard.sh` con stdin típico no-push: min 8.8 ms, mediana
>   9.1 ms, max 13.0 ms — muy por debajo de los 100 ms.
> - **Merge de `settings.json`**: algoritmo de 6 pasos de `commands/init.md` §2c implementado en
>   Python (fiel al pseudocódigo) y corrido DOS VECES sobre copias de los `settings.json`
>   **reales** (no fixtures sintéticos como en 3.9) de base-project, landing-crb y
>   pos-llantera-jairo. JSON válido en las 3 salidas (`python3 -m json.tool`). Diff
>   original→pasada 1: SOLO adiciones (`SessionStart`/`PreToolUse` nuevos) en los 3 casos.
>   Diff pasada 1→pasada 2: vacío en los 3 (idempotencia confirmada por detección de subcadena).
>   Confirmado a ojo: `git-guard.sh` intacto en base-project/pos-llantera (su matcher real es
>   `Edit|Write|MultiEdit|NotebookEdit`, no `"Bash"` — por eso el hook nuevo crea una entrada
>   `"Bash"` propia en vez de compartir array, tal como manda el paso 5 del algoritmo); los 2
>   matchers de `PostToolUse` de pos-llantera (`detect-ui-change.js`, `briefing-detect.sh`)
>   intactos; `enabledPlugins`/`extraKnownMarketplaces` de landing-crb intactos.
> - `bash scripts/validate-manifest.sh` → pasa en 0.4.0 (`claude plugin validate --strict`).
>
> Ningún ítem de abajo se marca `[x]`: todos exigen `/release-gate:upgrade`/`/release-gate:doctor`
> reales sobre los 7 repos o una sesión de Claude Code real (fuera del alcance de este agente,
> per instrucción explícita de no tocar los repos reales). Quedan **PENDIENTE MANUAL**.

- [ ] 5.1 Bump del plugin instalado: Rodrigo corre `/plugin` y reinicia Claude Code (fuera del
      alcance de este agente — anotado como paso manual del Rollout).
- [ ] 5.2 Ejecutar `/release-gate:upgrade` en **base-project** (menor riesgo, hooks completos)
      y confirmar: las 5 piezas presentes, `settings.json` válido con hooks previos intactos,
      bloque `CLAUDE.md` instalado, `.gate/baseline.json` sin cambios salvo campo `plugin`.
      — *design "Rollout"; gate-vendoring: "Ausencia de re-medición"*. Mecánica del merge
      ya verificada sobre copia real (ver nota de batch arriba); falta la corrida real.
- [ ] 5.3 SessionStart end-to-end en base-project: medir tiempo desde arranque de sesión hasta
      tablero impreso (<2s). — *gate-status: "Presupuesto de tiempo" (SHOULD <2s end-to-end)*.
      Timing de `gate-status.sh` solo (sin overhead de Claude Code) ya medido: ~232 ms mediana
      sobre el caso pesado (ver nota de batch); falta medir el end-to-end real con Claude.
- [ ] 5.4 **PENDIENTE MANUAL** — E2E push bloqueado: en rama `dev` de un repo de prueba sin
      `.gate/last-run.json`, intentar `git push` vía Claude y confirmar que no pasa; correr
      `/release-gate:run`, confirmar `last-run.json` verde y que el push subsiguiente sí pasa.
      — *gate-hooks: "Deny — evidencia insuficiente", escenario "Sin evidencia previa"; design
      "Estrategia de verificación" fila E2E*. La lógica de deny/allow del script ya se probó
      exhaustivamente sin Claude (batería de la nota de arriba); lo que falta es específicamente
      la interacción real vía Claude Code, que un agente no puede simular.
- [ ] 5.5 Ejecutar `/release-gate:upgrade` en **pos-llantera** (`PostToolUse` con 2 matchers) y
      en **landing-crb**/**landing-urn** (sin clave `hooks`) y confirmar en cada uno los
      escenarios específicos de `gate-vendoring` para esos repos. — *gate-vendoring: escenarios
      "Upgrade preserva hooks de la casa (pos-llantera)" y "Upgrade en repo sin bloque hooks
      (landing-crb, landing-urn)"*. Merge sobre copias reales de pos-llantera y landing-crb ya
      verificado (ver nota de batch); landing-urn no tiene copia probada, falta la corrida real
      de los 3.
- [ ] 5.6 Ejecutar `/release-gate:upgrade` en **landing-cursos-urn** (hooks + plugins
      declarados) y confirmar que ambos bloques conviven sin pérdida. — *gate-vendoring:
      escenario "Upgrade en repo con hooks + plugins declarados (landing-cursos-urn)"*. No
      verificado en esta sesión (no se copió su `settings.json`); pendiente completo.
- [ ] 5.7 **PENDIENTE MANUAL** — Rodar `/release-gate:doctor` en cada repo tras su upgrade y
      confirmar cero hallazgos sobre las piezas nuevas (checksum + presencia). — *gate-vendoring:
      "Custodia de doctor — checksum" y "— presencia"; gate-doctrina: "Bloque presente y
      vigente"*. `doctor.md` es prosa para un Claude interactivo real; no hay runner
      automatizado para simularlo sin invocar el comando real sobre los repos reales.
- [x] 5.8 N/A — DEUDA para v0.5.0 (decisión ratificada por Rodrigo): `doctor` NO audita el uso
      de `GATE_SKIP` en esta release. `gate-run.sh` no agrega el campo al schema de
      `last-run.json`. La deuda queda anotada en `docs/referencia.md` (Batch 4, pendiente) tal
      como está en el design, sección "Riesgos residuales".
- [ ] 5.9 Verificación de cierre final: `bash scripts/validate-manifest.sh` en 0.4.0 sobre el
      plugin ya instalado en los repos actualizados; correr los 7 repos por CI (red final) y
      confirmar que sigue en verde sin cambios de baseline salvo el campo `plugin`.
      `validate-manifest.sh` ya corrido y en verde sobre el manifiesto del plugin (ver nota de
      batch); falta la corrida sobre el plugin instalado en cada repo y la CI de los 7.
