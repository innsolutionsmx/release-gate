# Gate Doctrina Specification

## Purpose

Un bloque de criterio corto, delimitado e idempotente en el `CLAUDE.md` de cada repo
gateado: fija por escrito que el baseline nunca se edita para pasar el gate, solo se
aprieta con `ratchet`, y que hay que correr `/release-gate:run` antes de pushear.

## Requirements

### Requirement: Contenido del bloque
`plantillas/claude-md-bloque.md` SHALL definir un bloque de doctrina con, como mínimo: (a)
que el baseline nunca se edita para que el gate pase, (b) que solo se aprieta vía
`/release-gate:ratchet` cuando la realidad mejoró, (c) que los scripts `scripts/gate-*.sh`
no se editan a mano y `doctor` delata cualquier edición, y (d) que un push a `dev`/`main`
sin corrida verde del commit actual queda bloqueado por el hook.

#### Scenario: Bloque instalado en repo nuevo
- GIVEN un repo que corre `/release-gate:init` por primera vez
- WHEN se vendorea el bloque de doctrina
- THEN el `CLAUDE.md` del repo contiene las 4 reglas de doctrina

### Requirement: Delimitadores para reemplazo idempotente
El bloque SHALL estar delimitado por los marcadores literales `<!-- release-gate:inicio -->`
y `<!-- release-gate:fin -->`. `upgrade` SHALL reemplazar únicamente el contenido entre
esos marcadores, preservando el resto del `CLAUDE.md` del repo intacto.

#### Scenario: Upgrade reemplaza el bloque sin tocar el resto del archivo
- GIVEN un `CLAUDE.md` con el bloque de doctrina de una versión anterior y contenido propio del repo antes y después
- WHEN corre `/release-gate:upgrade`
- THEN el contenido entre los marcadores se actualiza a la versión nueva y el resto del archivo queda idéntico

#### Scenario: CLAUDE.md sin bloque previo
- GIVEN un `CLAUDE.md` sin los marcadores `release-gate:inicio/fin`
- WHEN corre `/release-gate:init` o `/release-gate:upgrade`
- THEN se agrega el bloque completo con sus marcadores, sin eliminar contenido existente del archivo

### Requirement: Verificación de presencia por `doctor`
`/release-gate:doctor` SHALL verificar la presencia de los marcadores y del contenido
esperado del bloque (no por checksum, ya que el resto del archivo es editable legítimamente
por el repo), y SHALL reportar si el bloque falta o quedó desactualizado respecto a la
plantilla vigente del plugin.

#### Scenario: Bloque ausente
- GIVEN un repo gateado sin los marcadores de doctrina en `CLAUDE.md`
- WHEN corre `/release-gate:doctor`
- THEN reporta la ausencia del bloque de doctrina como hallazgo

#### Scenario: Bloque presente y vigente
- GIVEN un repo con el bloque de doctrina de la versión actual del plugin
- WHEN corre `/release-gate:doctor`
- THEN no reporta hallazgos sobre la doctrina
