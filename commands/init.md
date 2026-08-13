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

- **medida** — sistema con dominio: hay `app/Actions/`, roles/permisos, admin,
  operaciones que mueven datos. El riesgo está en la lógica → PHPStan n8 con
  trinquete, reglas propias, Psalm taint, PHPMD y Deptrac.
- **landing** — sitio de presentación: pocas rutas, sin dominio real. El riesgo
  está en la superficie (secretos, deps, XSS por innerHTML, links muertos, headers,
  performance) → Psalm taint por los formularios públicos, sin PHPStan ni mutación.

**SIEMPRE confirmá el perfil con el usuario antes de seguir** (AskUserQuestion con
tu recomendación primera). La heurística propone; el humano dispone.

⚠️ El perfil se decide por el CÓDIGO, no por cómo se ve el sitio. Un sitio que por
fuera es una landing pero adentro tiene panel administrable, modelos y migraciones
propias es **medida**: lo que justifica el perfil landing son sus checks extra
(innerHTML, links), no que le falte análisis. Ante la duda, contá archivos en
`app/` y mirá `app/Models/`: si hay dominio, es medida.

## 2. Vendorear scripts

Desde `${CLAUDE_PLUGIN_ROOT}/scripts/` copiá al repo (creando `scripts/` si falta):

| Perfil | Se copia | Como |
|---|---|---|
| ambos | `gate-check-<perfil>.sh` | `scripts/gate-check.sh` |
| ambos | `gate-headers.sh`, `gate-lighthouse.sh` | mismo nombre |
| landing | `gate-links.php` | mismo nombre |

`chmod +x` a los `.sh`. NO los edites: si un check no aplica, el dato va al
baseline, no al script. Un script editado a mano es drift y `/release-gate:doctor`
lo va a delatar.

## 2b. Herramientas y plantillas

Instalá las dependencias de dev del perfil y copiá las plantillas. Los comandos
exactos, qué archivo va a dónde y el gotcha del `--with-all-dependencies` de
PHPMD están en `${CLAUDE_PLUGIN_ROOT}/plantillas/README.md`.

En **medida** hay un paso que toca el `composer.json` del proyecto: las reglas
propias necesitan `"Gate\\PHPStan\\": "phpstan/"` en `autoload-dev.psr-4` y un
`composer dump-autoload`. Mostrale el diff al usuario; no lo hagas en silencio.

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
6. **innerHTML** (solo landing): buscá `innerHTML|v-html` en `resources/js` y
   `resources/views`. Por cada hit LEÉ el archivo y evaluá: ¿inyecta solo markup
   estático/constantes propias, sin input de usuario? Armá la lista PROPUESTA de
   permitidos con tu veredicto por archivo y **pedí confirmación humana explícita
   antes de escribirla**. Anotá en `inner_html.nota` qué se revisó y cuándo.
6b. **Psalm taint** (ambos perfiles), **PHPMD**, **Deptrac** y **reglas propias**
   (solo medida): medí y congelá cada uno como indica el paso 5 de
   `/release-gate:upgrade` — mismo procedimiento, mismos comandos, mismo criterio
   (un taint real es un bug de seguridad: mostralo antes de congelarlo).
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
