# Referencia — release-gate

## Comandos

| Comando | Qué hace |
|---|---|
| `/release-gate:init` | Instala el gate: detecta perfil (confirmado por humano), vendorea scripts, mide y congela `.gate/baseline.json`, agrega el job de CI |
| `/release-gate:run` | Corre el gate e interpreta las fallas; el fix siempre es la causa, nunca el umbral |
| `/release-gate:ratchet` | Aprieta el trinquete donde la realidad mejoró; nunca afloja |
| `/release-gate:deploy-check` | Post-deploy: headers + Lighthouse contra el sitio vivo; la primera corrida congela los mínimos |
| `/release-gate:doctor` | Salud de la instalación: baseline, drift por checksum contra el plugin, herramientas, CI |
| `/release-gate:upgrade` | Sube un repo YA gateado a la versión actual del plugin: instala lo que falte, vendorea, mide y congela los baselines nuevos |

## Checks por perfil

**medida** (sistemas con dominio — `gate-check-medida.sh`):

| Check | Bloquea por | Dato en baseline |
|---|---|---|
| Pint `--test` | formato sucio | `pint.estado` |
| PHPStan nivel 8 + baseline (incluye las reglas propias) | errores nuevos sobre el baseline | `phpstan.*`, `reglas_gate.*` |
| Trinquete PHPStan | más entradas que las congeladas | `phpstan.entradas_baseline` |
| Psalm `--taint-analysis` | flujo input de usuario → sink peligroso | `psalm.entradas_baseline` |
| Trinquete taint | más entradas que las congeladas | ídem |
| PHPMD (set curado) | complejidad, código muerto, restos de debugging | `phpmd.entradas_baseline`, `phpmd.paths` |
| Trinquete PHPMD | más entradas que las congeladas | ídem |
| Deptrac | dependencia entre capas no permitida | `deptrac.entradas_baseline` |
| Trinquete Deptrac | más entradas que las congeladas | ídem |
| gitleaks (historial completo) | secretos nuevos | `secretos.*` (`.gitleaksignore` = riesgos aceptados) |
| composer audit | advisories ≥ `bloquea_desde` | `composer.bloquea_desde` |
| npm audit | superar el trinquete | `npm.trinquete` |
| innerHTML / v-html | archivos fuera de la lista permitida | `inner_html.permitidos` |
| `gate-links.php` | `route('x')` en vistas que no existe en el router | — (sin baseline) |

**landing** (sitios de presentación — `gate-check-landing.sh`): **el mismo conjunto
menos los cuatro análisis de lógica.** Corre Pint, Psalm taint + trinquete,
gitleaks, composer audit, npm audit, innerHTML y links — 8 checks, con los mismos
datos de baseline. No corre PHPStan (ni las reglas propias), PHPMD ni Deptrac.

> **medida ⊇ landing.** Desde la v0.3.0 medida es superconjunto ESTRICTO: los dos
> checks de superficie corren en los dos perfiles. Elegir medida nunca cuesta
> cobertura, así que la decisión de perfil se reduce a una sola pregunta: **¿el
> repo tiene dominio propio?**
>
> Hasta la v0.2.0 no era así, y el costo fue real: cinco repos de la casa se
> quedaron en `landing` para no perder innerHTML y links, y por eso pasaron meses
> sin análisis estático. La primera corrida de PHPStan sobre uno de ellos destapó
> un 500 en producción escondido hacía meses.

> **Por qué taint también en landing**: es el único análisis estático que corre
> ahí, y es standalone (no necesita PHPStan). Una landing tiene formularios
> públicos de contacto: la superficie de input más expuesta de todas.

> **El perfil se decide por el código, no por el frontend.** Un sitio que por
> fuera parece landing pero adentro tiene modelos propios, migraciones de dominio
> y panel administrable es **medida**. Ante la duda, medida: como es superconjunto,
> el error hacia medida cuesta minutos de CI y el error hacia landing cuesta no
> ver los bugs.

> ⚠️ **El check de links no tiene baseline y no lo va a tener.** Los demás
> congelan la realidad y exigen que no empeore; este no perdona nada. Un
> `route('x')` que no existe no es deuda: es una vista que tira 500 el día que
> alguien la abra. Se arregla, no se congela.

## Herramientas por perfil

| Herramienta | medida | landing |
|---|---|---|
| Pint, gitleaks, composer, npm | sí | sí |
| PHPStan n8 + larastan | sí | no |
| Reglas propias (`phpstan/Rules/`) | sí | no (necesitan PHPStan) |
| Psalm + `psalm/plugin-laravel` | sí | sí |
| PHPMD ≥ 2.15 | sí | no |
| Deptrac | sí | no |

Instalación, plantillas y gotchas: `plantillas/README.md` del plugin.

⚠️ **PHPMD se instala con `--with-all-dependencies`**. Sin el flag, composer
resuelve `phpmd/phpmd` a la 2.5.0 (2016) porque `pdepend/pdepend` queda clavado
viejo, y esa combinación tira deprecations en PHP 8.4. Si `doctor` reporta PHPMD
2.5.x, se instaló mal.

**post-deploy** (ambos perfiles, necesitan URL viva): `gate-headers.sh <url>`
(5 headers obligatorios, 2 prohibidos) y `gate-lighthouse.sh <url>` (ninguna
categoría bajo su mínimo congelado).

## `.gate/baseline.json` — schema 1

El script es idéntico entre proyectos; TODO dato del proyecto vive acá.

Perfil **medida**:

```json
{
    "schema": 1,
    "congelado": "2026-08-10",
    "perfil": "medida",
    "plugin": "0.1.0",
    "phpstan": {
        "nivel": 8,
        "errores_baseline": 995,
        "entradas_baseline": 904,
        "nota_entradas": "por qué el número es el que es (útil cuando lo movió una regla nueva y no código nuevo)",
        "medicion_inicial_por_nivel": { "0": 4, "8": 999 }
    },
    "reglas_gate": {
        "descripcion": "Reglas propias en phpstan/Rules/: prohíben queries y escrituras de Eloquent en Controllers",
        "congelado": "2026-08-13",
        "ocurrencias_congeladas": 0
    },
    "psalm": { "modo": "taint-only", "congelado": "2026-08-13", "entradas_baseline": 0 },
    "phpmd": {
        "reglas": "curado: unusedcode + codesize + design selecto",
        "congelado": "2026-08-13",
        "entradas_baseline": 0,
        "paths": "app,routes,database/seeders"
    },
    "deptrac": {
        "modo": "pragmático: Controller→Model permitido (bindings); queries en Actions",
        "congelado": "2026-08-13",
        "entradas_baseline": 0
    },
    "pint": { "estado": "limpio" },
    "secretos": { "estado": "limpio", "riesgos_aceptados": ".gitleaksignore" },
    "composer": { "bloquea_desde": "high", "abiertas": {} },
    "npm": { "trinquete": { "critical": 0, "high": 0 } },
    "inner_html": {
        "permitidos": ["resources/js/admin/theme-editor.js"],
        "nota": "inyecta solo markup estático y constantes propias, sin input de usuario (revisado 2026-08-13)"
    }
}
```

⚠️ `inner_html` es obligatoria en medida **desde la v0.3.0**. Un baseline de
medida escrito con un plugin anterior no la tiene: sin la clave el check corre con
lista vacía y cualquier `innerHTML` bloquea. `/release-gate:upgrade` la agrega
midiendo, nunca copiándola de otro repo.

Perfil **landing** — las mismas claves menos `phpstan`, `reglas_gate`, `phpmd` y
`deptrac`:

```json
{
    "schema": 1,
    "congelado": "2026-08-10",
    "perfil": "landing",
    "plugin": "0.1.0",
    "psalm": { "modo": "taint-only", "congelado": "2026-08-13", "entradas_baseline": 0 },
    "pint": { "estado": "limpio" },
    "secretos": { "estado": "limpio", "riesgos_aceptados": ".gitleaksignore" },
    "composer": { "bloquea_desde": "high", "abiertas": {} },
    "npm": { "trinquete": { "critical": 0, "high": 0 } },
    "inner_html": {
        "permitidos": ["resources/js/landing.js"],
        "nota": "inyectan solo markup estático propio, sin input de usuario (revisado 2026-08-10)"
    },
    "headers": {
        "verificado_en_vivo": "2026-08-10",
        "url": "https://ejemplo.innsolutionsmx.com",
        "resultado": "7/7"
    },
    "lighthouse": {
        "minimos": { "performance": 90, "accessibility": 95, "best-practices": 100, "seo": 100 },
        "medido": "2026-08-10"
    }
}
```

Notas del schema:

- `plugin`: versión del plugin con la que se vendorearon los scripts (informativa;
  la verdad del drift son los checksums de `/release-gate:doctor`).
- `lighthouse.minimos: null` = pendiente de primera corrida de
  `/release-gate:deploy-check`, que los congela con los puntajes medidos.
- `medicion_inicial_por_nivel` es opcional: la foto histórica de errores PHPStan
  por nivel al momento de instalar. Cara de medir; solo si se pide.
- El trinquete se aprieta con `/release-gate:ratchet`; aflojarlo no tiene comando,
  a propósito. Toda excepción es decisión humana y queda anotada en el baseline.
- **Las secciones nuevas (`psalm`, `phpmd`, `deptrac`, `reglas_gate`) son extensión
  compatible: el schema sigue en 1.** Los checks leen sus claves con fallback a 0,
  así que un baseline viejo que no las tenga no rompe nada. Un repo sin la
  herramienta instalada sí falla el check correspondiente: por eso el upgrade
  instala y congela en el mismo paso.
- `phpmd.paths` es opcional; sin él se usa `app,routes,database/seeders`.
- **Fix de la 0.2.0 que afecta a todos los perfiles**: hasta la 0.1.1, cuando un
  check fallaba el script MORÍA ahí mismo. La línea de diagnóstico
  (`herramienta ... | tail -N`) devuelve non-zero y con `set -euo pipefail` mata
  el script antes de correr los checks siguientes y antes de imprimir
  `✗ GATE BLOQUEADO`. El exit code seguía siendo 1 —por eso la CI se ponía roja
  igual y el bug pasó desapercibido—, pero solo se veía la PRIMERA falla. Ahora
  esas líneas llevan `|| true`: el gate reporta TODAS las fallas de una pasada.
  Un repo que siga en 0.1.x arrastra el comportamiento viejo hasta re-vendorear.
- Un baseline **ausente** (no hay `psalm-taint-baseline.xml`, `phpmd.baseline.xml`)
  cuenta como cero congelados. Es lo correcto: si no hay nada que perdonar, no hay
  archivo. La excepción es `deptrac.baseline.yaml`, que `deptrac.yaml` importa
  siempre y debe existir aunque sea con `skip_violations: {}`.

## `.gate/last-run.json` — evidencia de la última corrida

Lo escribe **`scripts/gate-run.sh`**, siempre — corrida aprobada o bloqueada —
nunca `gate-check.sh` (que sigue leyendo y jamás escribiendo) ni ningún hook.
Es el ÚNICO punto que produce esta evidencia; el tablero (`gate-status.sh`) y
el guard de push (`.claude/hooks/gate-push-guard.sh`) la leen, nunca la
infieren.

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

| Campo | Qué es |
|---|---|
| `schema` | versión del schema de este archivo (hoy `1`) |
| `fecha` | timestamp ISO 8601 con offset, del momento de la corrida |
| `commit` | `git rev-parse HEAD` al momento de correr `gate-run.sh` |
| `arbol_limpio` | `true` si `git status --porcelain` no reportó nada |
| `veredicto` | `APROBADO` o `BLOQUEADO`, según el exit code de `gate-check.sh` |
| `perfil` | leído de `.gate/baseline.json` |
| `plugin` | leído de `.gate/baseline.json` (versión vendoreada) |
| `conteos` | conteo por `grep -c` en los archivos de baseline de cada herramienta del perfil activo — mismo conteo que `gate-status.sh`, nunca un re-análisis; fuera de perfil: `null` |

**Va en `.gitignore`** (línea `.gate/last-run.json`): es estado local por
desarrollador. Commitearlo produce conflictos en cada push y evidencia ajena
que el guard leería como propia. Tradeoff aceptado: en un clon nuevo no hay
evidencia, y el primer push a `dev`/`main` exige correr `/release-gate:run` —
que es exactamente el comportamiento deseado.

## Hooks — `SessionStart` y `PreToolUse`

Dos hooks vendoreados en `.claude/hooks/` (fuente en el plugin:
`scripts/hooks/gate-*.sh`), registrados en `.claude/settings.json` por
`/release-gate:init`/`upgrade` (algoritmo de merge documentado en esos
comandos). Ninguno de los dos corre análisis: ambos solo leen evidencia ya
escrita, nunca `gate-check.sh` ni ninguna herramienta.

### `gate-session-status.sh` (`SessionStart`, sin `matcher`)

Invoca `scripts/gate-status.sh` y muestra el tablero como contexto de
sesión. Termina siempre `exit 0`, incluso si algo falla adentro. Sin
`.gate/baseline.json`: cero output (el guard vive en `gate-status.sh`).
Presupuesto: menos de 2s de punta a punta.

### `gate-push-guard.sh` (`PreToolUse`, `matcher: "Bash"`)

Corre en el hot path de TODO comando Bash de la sesión — por eso el primer
paso es un descarte por regex antes de tocar disco (medido ~10ms para un
comando no-push). Orden de descarte:

1. Extrae `tool_input.command` del payload de stdin con `sed` (no `jq`, mismo
   patrón que `git-guard.sh`).
2. Si el comando no matchea un `git push` (con o sin flags entre `git` y
   `push`, solo o encadenado con `;`/`&&`/`|`), `exit 0` inmediato.
3. Excepciones explícitas: `--dry-run` en el comando → `exit 0`. `GATE_SKIP=1`
   presente en el comando → `exit 0` (ver override abajo).
4. Sin `.gate/baseline.json` → `exit 0` (repo sin gate, nada que exigir).
5. Resuelve la rama destino (refspec explícito del comando si está; si no,
   la rama actual). Si no es `main` ni `dev` → `exit 0` (rama no protegida).
6. Lee `.gate/last-run.json`: si `veredicto == APROBADO`, `commit == HEAD`
   actual, y `arbol_limpio == true`, deja pasar. Si no, deniega con el motivo
   exacto (sin evidencia / bloqueado / commit viejo / árbol sucio) vía:

   ```json
   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<mensaje>"}}
   ```

   El bloqueo es SIEMPRE por ese JSON — el exit code nunca bloquea nada; el
   script termina con `exit 0` en todos los casos, incluso al denegar.

Falsos positivos/negativos aceptados (CI sigue siendo la red final, esto es
fricción temprana, no la única barrera):

| Caso | Resultado |
|---|---|
| `git add . && git commit -m x && git push` | detectado — el regex ancla en `;`/`&`/`\|` |
| `git push --force origin dev` | detectado y denegado — `--force` no exime |
| `git push origin feat/x` | permitido — rama no protegida |
| `git -c foo=bar push origin dev` | detectado — el regex tolera flags entre `git` y `push` |
| `echo "git push"` / heredoc con `git push` | falso positivo — deny informativo, override disponible |
| comando con `\"` escapadas que rompe el `sed` | falso negativo — falla abierto, limitación heredada de `git-guard.sh` |
| `git push` a un remote no protegido con rama `dev` | denegado — el guard mira la rama, no el remote |

### Override: `GATE_SKIP=1`

Prefijo/substring literal en el comando (ej. `GATE_SKIP=1 git push origin dev`)
salta el guard con `exit 0`. Es visible y auditable a propósito: queda
escrito tal cual en el transcript de la sesión — no es una variable de
entorno silenciosa ni un flag oculto.

⚠️ **Deuda anotada para v0.5.0**: `doctor` NO audita el uso de `GATE_SKIP` en
esta release, y `gate-run.sh` no agrega el campo al schema de
`last-run.json`. Si el override se vuelve costumbre, hoy solo se detecta
revisando transcripts a mano; auditarlo automáticamente queda pendiente.

## Bloque de doctrina en `CLAUDE.md`

`plantillas/claude-md-bloque.md` — delimitado por
`<!-- release-gate:inicio -->` / `<!-- release-gate:fin -->`. `init` lo
agrega completo al `CLAUDE.md` del repo (sin borrar contenido previo);
`upgrade` reemplaza SOLO el contenido entre los marcadores, dejando el resto
del archivo intacto. Contenido mínimo: el baseline nunca se edita para pasar
el gate; solo se aprieta con `/release-gate:ratchet`; los scripts
`scripts/gate-*.sh` no se editan a mano y `doctor` delata cualquier edición;
un push a `dev`/`main` sin corrida verde del commit actual queda bloqueado
por el hook.

## Archivos vendoreados — qué instala/custodia cada comando

| Archivo | Custodia en `doctor` | `init` | `upgrade` |
|---|---|---|---|
| `scripts/gate-check.sh` (de `gate-check-<perfil>.sh`) | checksum | instala | re-vendorea (pisa) |
| `scripts/gate-headers.sh` | checksum | instala | re-vendorea |
| `scripts/gate-lighthouse.sh` | checksum | instala | re-vendorea |
| `scripts/gate-links.php` | checksum | instala | re-vendorea |
| `scripts/gate-status.sh` | checksum | instala | re-vendorea |
| `scripts/gate-run.sh` | checksum | instala | re-vendorea |
| `.claude/hooks/gate-session-status.sh` | checksum | instala | re-vendorea |
| `.claude/hooks/gate-push-guard.sh` | checksum | instala | re-vendorea |
| Plantillas (`psalm.xml`, `phpmd.xml`, `deptrac.yaml`, `phpstan-servicios.neon`) | checksum (reglas propias) | instala | instala si faltan; si difieren, muestra diff y pregunta |
| `phpstan/Rules/*.php` (medida) | checksum | instala | instala |
| Entradas `SessionStart`/`PreToolUse` en `.claude/settings.json` | presencia | merge aditivo (algoritmo de 6 pasos) | merge aditivo idempotente (mismo algoritmo) |
| Bloque delimitado en `CLAUDE.md` | presencia | instala completo | reemplaza solo el contenido entre marcadores |
| Línea `.gate/last-run.json` en `.gitignore` | presencia | agrega | agrega si falta |
| `.gate/baseline.json` | — (no vendoreado, es dato del repo) | mide y crea | NO re-mide (salvo `/release-gate:ratchet`) |

## CI — job `gate`

Job de referencia para `.github/workflows/ci.yml` (junto al job de tests):

```yaml
  gate:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout (historial completo)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0    # gitleaks recorre TODO el historial; shallow = check mentiroso

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.4'
          extensions: pdo_sqlite, gd, bcmath, ctype, json, mbstring, openssl, tokenizer, xml
          tools: composer

      - name: Install gitleaks
        run: |
          curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v8.24.3/gitleaks_8.24.3_linux_x64.tar.gz | tar -xz gitleaks
          sudo mv gitleaks /usr/local/bin/

      - name: Install PHP dependencies
        run: composer install --no-interaction --prefer-dist --no-progress

      - name: Release Gate
        run: ./scripts/gate-check.sh
```

Notas:

- gitleaks pinneado (v8.24.3, la versión que corre en los 7 repos de la casa);
  subir la versión es un cambio consciente, no un `latest`.
- `npm audit` corre desde `package-lock.json` — no hace falta `npm ci`.
- No hace falta preparar `.env` ni `storage/`: `artisan route:list` (que usa
  `gate-links.php`, en ambos perfiles) bootea sin ellos — probado por 7 CI verdes de la
  familia. Si un repo lo llegara a necesitar (p. ej. `/storage` entero en
  `.gitignore`, la falla histórica de pos-llantera), la señal es `route:list`
  muriendo en CI: ahí se agrega un paso de preparación como el del job de tests.
- El job de tests existente no se toca: el gate es un job aparte, en paralelo.

## Gotchas vigentes (aprendidos en producción)

- PHPStan con poca memoria MUERE y reporta "0 errores": siempre
  `--memory-limit=2G`, y desconfiar de un cero demasiado lindo.
- gitleaks sin historial completo (clone shallow) miente: `fetch-depth: 0`.
- Regenerar `phpstan-baseline.neon` solo está permitido para ACHICARLO
  (`/release-gate:ratchet`); el script cuenta entradas y bloquea si engordó.
- `route('x')` con `->route(` (accessor de Request) está excluido del check de
  links a propósito.
