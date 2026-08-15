---
description: "Instala el Release Gate en el repo: detecta perfil, vendorea scripts, mide y congela el baseline, y suma el gate a la CI"
---

Instalá el Release Gate en este repo, de punta a punta. Regla de oro: el gate se
INSTALA midiendo la realidad, nunca inventando números. Todo dato del proyecto
termina en `.gate/baseline.json`; los scripts son idénticos entre proyectos.

## 0. Guardas

- Tiene que ser un repo git con Laravel (`artisan` en la raíz). Si no, frená y explicá.
- Si ya existe `.gate/baseline.json`: el gate ya está instalado. Si le faltan
  herramientas de la versión actual del plugin, eso es `/release-gate:upgrade`;
  si no, ofrecé `/release-gate:doctor` (drift/salud) o `/release-gate:ratchet`
  (apretar). En cualquier caso frená acá.
- Flujo git de la casa: NO trabajes sobre `main`/`dev`. Creá la rama
  `chore/release-gate` desde `dev` actualizado antes de tocar nada.

## 1. Fase 0 — mapa del repo y perfil

Relevá el repo (stack, dominio, superficie) y proponé un perfil:

- **landing** — sitio de presentación: pocas rutas, sin dominio real. El riesgo
  está en la superficie (secretos, deps, XSS por innerHTML, links muertos, headers,
  performance) → Psalm taint por los formularios públicos, innerHTML, links; sin
  PHPStan ni mutación. **8 checks.**
- **medida** — sistema con dominio: hay `app/Actions/`, roles/permisos, admin,
  operaciones que mueven datos. Todo lo de landing **más** el análisis de la
  lógica: PHPStan n8 con trinquete, reglas propias, PHPMD y Deptrac. **14 checks.**

**medida es superconjunto ESTRICTO de landing.** Elegir medida nunca cuesta
cobertura: un sistema con dominio no deja de tener vistas y JS por tener Actions.
Por eso la pregunta no es "¿cuál de los dos?", es una sola: **¿este repo tiene
dominio propio?** Si sí, medida. Si no, landing.

**SIEMPRE confirmá el perfil con el usuario antes de seguir** (AskUserQuestion con
tu recomendación primera). La heurística propone; el humano dispone.

⚠️ El perfil se decide por el CÓDIGO, no por cómo se ve el sitio. Un sitio que por
fuera es una landing pero adentro tiene panel administrable, modelos y migraciones
propias es **medida**. Ante la duda, contá archivos en `app/` y mirá `app/Models/`:
si hay dominio, es medida. Y ante la duda que no se despeja, **medida**: como es
superconjunto, equivocarse hacia medida cuesta tiempo de CI; equivocarse hacia
landing cuesta no ver los bugs.

> Historia de por qué esto está escrito así: hasta la v0.2.0 medida NO incluía
> innerHTML ni links, así que reclasificar un repo de landing a medida le hacía
> PERDER dos checks. Cinco repos de la casa quedaron en landing por eso —
> aplicaciones con panel administrable y roles corriendo sin una sola línea de
> análisis estático. La primera vez que se les corrió PHPStan apareció un 500 en
> producción que llevaba meses escondido. La v0.3.0 cerró el agujero.

## 2. Vendorear scripts

Desde `${CLAUDE_PLUGIN_ROOT}/scripts/` copiá al repo (creando `scripts/` si falta):

| Perfil | Se copia | Como |
|---|---|---|
| ambos | `gate-check-<perfil>.sh` | `scripts/gate-check.sh` |
| ambos | `gate-headers.sh`, `gate-lighthouse.sh` | mismo nombre |
| ambos | `gate-links.php` | mismo nombre |
| ambos | `gate-status.sh` | mismo nombre — tablero de estado por conteo, invocado por el hook de sesión |
| ambos | `gate-run.sh` | mismo nombre — envoltorio que corre `gate-check.sh` intacto y escribe `.gate/last-run.json` |

Desde `${CLAUDE_PLUGIN_ROOT}/scripts/hooks/` copiá al repo (creando
`.claude/hooks/` si falta):

| Se copia | Como |
|---|---|
| `gate-session-status.sh` | `.claude/hooks/gate-session-status.sh` |
| `gate-push-guard.sh` | `.claude/hooks/gate-push-guard.sh` |

`chmod +x` a TODOS los `.sh` (los de `scripts/` y los de `.claude/hooks/`). NO
los edites: si un check no aplica, el dato va al baseline, no al script. Un
script editado a mano es drift y `/release-gate:doctor` lo va a delatar.

## 2b. Herramientas y plantillas

Instalá las dependencias de dev del perfil y copiá las plantillas. Los comandos
exactos, qué archivo va a dónde y el gotcha del `--with-all-dependencies` de
PHPMD están en `${CLAUDE_PLUGIN_ROOT}/plantillas/README.md`.

En **medida** hay un paso que toca el `composer.json` del proyecto: las reglas
propias necesitan `"Gate\\PHPStan\\": "phpstan/"` en `autoload-dev.psr-4` y un
`composer dump-autoload`. Mostrale el diff al usuario; no lo hagas en silencio.

## 2c. Hooks, bloque de doctrina y `settings.json`

Esto es lo que hace el gate **imposible de ignorar**: sin esto, los scripts
quedan vendoreados pero el tablero de sesión y el bloqueo de push no existen.

### Bloque de doctrina en `CLAUDE.md`

Copiá el contenido completo de
`${CLAUDE_PLUGIN_ROOT}/plantillas/claude-md-bloque.md` (delimitado por
`<!-- release-gate:inicio -->` / `<!-- release-gate:fin -->`) al final del
`CLAUDE.md` del repo. Si el repo no tiene `CLAUDE.md`, creálo con solo ese
bloque. **Nunca borres contenido previo del archivo.**

### `.gate/last-run.json` en `.gitignore`

Agregá la línea `.gate/last-run.json` a `.gitignore` (creá el archivo si no
existe). Es evidencia local por desarrollador — nunca se commitea.

### Merge de `.claude/settings.json`

Esto lo ejecutás vos con Read + Edit, **nunca reescribiendo el archivo
entero** — perderías `enabledPlugins`, `extraKnownMarketplaces` u otros hooks
de la casa (ej. los dos matchers de `PostToolUse` de pos-llantera). Algoritmo,
en orden:

1. **Sin `.claude/`**: creá el directorio y `settings.json` con solamente la
   clave `hooks` (los dos bloques de abajo).
2. **Con `settings.json` pero sin clave `hooks`**: agregá la clave `hooks` al
   objeto raíz, sin tocar `enabledPlugins` ni `extraKnownMarketplaces`.
3. **Detección de idempotencia**: buscá la subcadena `gate-session-status.sh`
   y `gate-push-guard.sh` en el archivo ANTES de tocar nada. Si ya aparecen,
   esa pieza ya está instalada — no agregues nada para ella.
4. **`SessionStart` ya existe**: hacé *append* del bloque de abajo al array
   existente. Nunca reemplaces el array.
5. **`PreToolUse` ya existe**: si hay una entrada con `matcher` exactamente
   `"Bash"`, agregá el hook al array `hooks` de **esa** entrada. Si no existe
   una entrada `"Bash"`, agregá una entrada nueva completa. No toques la
   entrada de `git-guard` (`Edit|Write|MultiEdit|NotebookEdit`) ni ningún
   otro matcher preexistente.
6. **Verificación post-merge, obligatoria**: confirmá que el archivo sigue
   siendo JSON válido (`php -r 'json_decode(file_get_contents(".claude/settings.json")) !== null || exit(1);'`)
   y revisá visualmente que las claves y hooks previos siguen presentes.

Shape exacto a insertar (calcado de `git-guard`/`git-session-status`):

```json
"SessionStart": [
  { "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gate-session-status.sh\"" } ] }
],
"PreToolUse": [
  { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/gate-push-guard.sh\"" } ] }
]
```

`SessionStart` **no lleva `matcher`**. `PreToolUse` sí, y `"Bash"` es lo más
fino que permite el campo — el filtrado por contenido (solo `git push`) va
adentro del script, no acá.

## 3. Medir y congelar `.gate/baseline.json` (schema 1)

Creá `.gate/` y medí la realidad, check por check:

1. **Pint**: `vendor/bin/pint --test`. Si está sucio, formateá primero
   (`vendor/bin/pint`) — el gate arranca con formato limpio, no perdonando mugre.
2. **PHPStan** (solo medida): si no hay `phpstan.neon`, crealo (nivel 8, paths
   `app/`, `includes` de larastan si está). Generá el baseline:
   `vendor/bin/phpstan analyse --memory-limit=2G --generate-baseline`.
   ⚠️ Gotcha vigente: PHPStan con poca memoria MUERE y reporta "0 errores" —
   SIEMPRE `--memory-limit=2G`, y desconfiá de un cero demasiado lindo.
   Contá entradas: `grep -c 'message:' phpstan-baseline.neon` → `entradas_baseline`.
   La medición por nivel (`medicion_inicial_por_nivel`) es opcional y cara:
   ofrecela, no la impongas.
3. **gitleaks**: `gitleaks git --no-banner --redact .` sobre el historial COMPLETO.
   Si encuentra algo: FRENÁ y traéselo al usuario. Rotar el secreto o aceptar el
   riesgo en `.gitleaksignore` es SIEMPRE decisión humana — jamás lo aceptes solo.
4. **composer**: `composer audit --locked`. Advisories abiertas van a
   `composer.abiertas`; `bloquea_desde` arranca en `"high"`.
5. **npm**: `npm audit`. El trinquete se congela en el estado REAL de hoy
   (ideal `{critical: 0, high: 0}`; si hay deuda, congelala y anotala — el
   trinquete impide que crezca).
6. **innerHTML** (ambos perfiles): buscá `innerHTML|v-html` en `resources/js` y
   `resources/views`. Por cada hit LEÉ el archivo y evaluá: ¿inyecta solo markup
   estático/constantes propias, sin input de usuario? Armá la lista PROPUESTA de
   permitidos con tu veredicto por archivo y **pedí confirmación humana explícita
   antes de escribirla**. Anotá en `inner_html.nota` qué se revisó y cuándo.
6b. **Psalm taint** (ambos perfiles), **PHPMD**, **Deptrac** y **reglas propias**
   (solo medida): medí y congelá cada uno como indica el paso 5 de
   `/release-gate:upgrade` — mismo procedimiento, mismos comandos, mismo criterio
   (un taint real es un bug de seguridad: mostralo antes de congelarlo).
6c. **links internos** (ambos perfiles): corré `php scripts/gate-links.php`.
   ⚠️ **Este check NO tiene baseline**: no hay nada que congelar, o pasa o bloquea.
   Si encuentra un `route('x')` que no existe, eso no es deuda técnica — es una
   vista que revienta con 500 el día que alguien la abra. Se ARREGLA antes de
   seguir. El caso más común es una vista huérfana de Breeze apuntando a una ruta
   deshabilitada (típico: `register.blade.php` con el registro público comentado):
   ahí lo correcto suele ser borrar la vista muerta, no resucitar la ruta.
7. Escribí el baseline con `schema: 1`, `perfil`, `congelado` (fecha de hoy),
   `plugin` (versión leída de `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`)
   y las secciones del perfil. Schema completo con ejemplo por perfil:
   `${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`.

## 4. Gate en CI

Agregá el job `gate` a `.github/workflows/ci.yml` (snippet exacto en
`${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`, sección CI). Claves que no se negocian:

- `fetch-depth: 0` en el checkout — gitleaks recorre el historial completo; con
  shallow clone el check miente.
- Instalar gitleaks (binario pinneado) en el runner.
- `composer install` antes del gate (Pint y PHPStan viven en `vendor/`).
- Preparación mínima de Laravel (`.env`, `storage/framework/*`) — recordá la
  falla histórica: `/storage` entero en `.gitignore` rompe el checkout limpio.

Si el repo no tiene workflows, creá `ci.yml` con el job `gate` y avisale al
usuario que tests no hay (eso es otra conversación).

## 5. Verificar y cerrar

1. Corré `./scripts/gate-check.sh` — la instalación termina con **✓ GATE APROBADO**,
   no antes. Si bloquea, arreglá la causa real (formatear, rotar secreto, subir dep);
   NUNCA aflojes el baseline para que pase.
2. Mostrale al usuario el resumen: perfil, qué se congeló, y qué números quedaron.
3. Commit en la rama `chore/release-gate` (Conventional Commits). El merge/push
   sigue el flujo git del repo — no lo saltees.
