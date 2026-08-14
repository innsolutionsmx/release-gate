# Gate Status Specification

## Purpose

Le da a cada sesión y a cada revisión manual un tablero honesto del estado del gate,
derivado por conteo (nunca por re-análisis), y produce/consume la evidencia de la última
corrida real (`.gate/last-run.json`). Nota de ubicación: `scripts/gate-run.sh` vive en esta
capability (no en `gate-vendoring`) porque su único propósito es alimentar el tablero y el
guard de push con evidencia fresca — es la contraparte que escribe lo que `gate-status.sh`
y el hook de push leen.

## Requirements

### Requirement: Tablero de tres columnas
`scripts/gate-status.sh` SHALL mostrar, por cada herramienta del perfil activo, tres
columnas: **congelado** (`.gate/baseline.json`), **en archivo** (conteo `grep -c` sobre el
archivo de baseline propio de la herramienta, con `|| true`) y **realidad** (siempre
"requiere análisis" — el script MUST NOT ejecutar ninguna herramienta de análisis ni
inferir la realidad del código a partir de un conteo de archivo).

#### Scenario: Perfil medida completo
- GIVEN un repo con perfil `medida` y `.gate/baseline.json` con `phpstan.entradas_baseline: 904`
- WHEN corre `gate-status.sh`
- THEN imprime las 4 filas (PHPStan, Psalm taint, PHPMD, Deptrac) con congelado/en archivo/realidad

#### Scenario: Perfil landing solo Psalm
- GIVEN un repo con perfil `landing`
- WHEN corre `gate-status.sh`
- THEN imprime solo la fila de Psalm taint

### Requirement: Presupuesto de tiempo
El algoritmo de conteo (sin contar overhead de Claude Code) MUST completar en menos de
300 ms usando solo `grep -c`, `php -r json_decode` y `git rev-parse` — cero red, cero
`vendor/bin/*`. El hook SessionStart end-to-end (invocación + tablero) SHOULD completar en
menos de 2 s, verificado contra pos-llantera (903 entradas de phpstan).

#### Scenario: Baseline grande no re-analiza
- GIVEN `phpstan-baseline.neon` con 903 entradas en pos-llantera
- WHEN corre `gate-status.sh`
- THEN responde en menos de 300 ms porque cuenta el archivo de texto, no re-corre PHPStan

### Requirement: Guard por ausencia de baseline
Si `.gate/baseline.json` no existe, `gate-status.sh` MUST NOT imprimir ningún output y
MUST terminar con `exit 0`.

#### Scenario: Repo sin gate
- GIVEN un repo sin `.gate/baseline.json`
- WHEN corre `gate-status.sh`
- THEN no hay salida y el código de salida es 0

### Requirement: Detección de "SE PUEDE APRETAR"
El script SHALL mostrar el aviso "SE PUEDE APRETAR → `/release-gate:ratchet`" únicamente
cuando exista evidencia concreta de mejora: el conteo "en archivo" es menor al "congelado"
para alguna herramienta, o `.gate/last-run.json` trae conteos menores a los congelados. El
script MUST NOT inferir mejora a partir de un análisis no ejecutado.

#### Scenario: Archivo de baseline se achicó
- GIVEN `phpstan-baseline.neon` con 903 entradas y `baseline.json` congelado en 904
- WHEN corre `gate-status.sh`
- THEN muestra "SE PUEDE APRETAR: PHPStan 903 < 904 congeladas → /release-gate:ratchet"

#### Scenario: Sin evidencia de mejora
- GIVEN conteo en archivo igual al congelado y sin `last-run.json` con conteos menores
- WHEN corre `gate-status.sh`
- THEN no muestra el aviso de ratchet

### Requirement: Versión vendoreada vs disponible
El tablero SHALL mostrar la versión de plugin `vendoreado` (`baseline.plugin`) junto a la
`disponible` (`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`), marcando ⚠ si difieren.
Si `CLAUDE_PLUGIN_ROOT` no está definida, el script SHALL omitir la columna "disponible" sin
fallar.

#### Scenario: Drift de versión
- GIVEN `baseline.plugin` en `0.1.0` y el plugin disponible en `0.4.0`
- WHEN corre `gate-status.sh`
- THEN muestra "vendoreado 0.1.0 | disponible 0.4.0 [ATRASADO → /release-gate:upgrade]"

### Requirement: `.gate/last-run.json` — escritura y ciclo de vida
`scripts/gate-run.sh` SHALL correr `gate-check.sh` intacto, y SHALL escribir
`.gate/last-run.json` siempre (tanto en aprobación como en bloqueo), propagando el código de
salida original de `gate-check.sh`. El archivo SHALL seguir el schema:
`{schema, fecha, commit, arbol_limpio, veredicto, perfil, plugin, conteos}`. El archivo SHALL
estar en `.gitignore` (estado local por desarrollador).

#### Scenario: Corrida aprobada escribe evidencia
- GIVEN un repo gateado con el árbol limpio
- WHEN corre `/release-gate:run` y `gate-check.sh` aprueba
- THEN `gate-run.sh` escribe `.gate/last-run.json` con `veredicto: "APROBADO"`, el commit HEAD y `arbol_limpio: true`

#### Scenario: Corrida bloqueada también escribe evidencia
- GIVEN un repo con el gate en rojo
- WHEN corre `/release-gate:run`
- THEN `gate-run.sh` escribe `.gate/last-run.json` con `veredicto` distinto de "APROBADO" y propaga el exit code de fallo

### Requirement: Fecha del último gate en el tablero
`gate-status.sh` SHALL leer `.gate/last-run.json` para mostrar fecha, commit y veredicto de
la última corrida. Si el archivo no existe, SHALL mostrar "Último gate: sin registro (corre
/release-gate:run)". Si el commit registrado difiere del HEAD actual, SHALL advertir que la
evidencia está vieja.

#### Scenario: Sin evidencia previa
- GIVEN un repo con `.gate/baseline.json` pero sin `.gate/last-run.json`
- WHEN corre `gate-status.sh`
- THEN muestra "Último gate: sin registro (corre /release-gate:run)"

#### Scenario: Evidencia desactualizada
- GIVEN `.gate/last-run.json` con `commit: a1b2c3d` y HEAD actual en `9f8e7d6`
- WHEN corre `gate-status.sh`
- THEN muestra el veredicto registrado junto con la advertencia "HEAD actual 9f8e7d6: la evidencia está vieja"
