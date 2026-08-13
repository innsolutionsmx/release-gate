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

**landing** (sitios de presentación — `gate-check-landing.sh`): Pint, gitleaks,
composer audit, npm audit (mismos datos), más:

| Check | Bloquea por | Dato en baseline |
|---|---|---|
| Psalm `--taint-analysis` | flujo input de usuario → sink peligroso | `psalm.entradas_baseline` |
| Trinquete taint | más entradas que las congeladas | ídem |
| innerHTML / v-html | archivos fuera de la lista permitida | `inner_html.permitidos` |
| `gate-links.php` | `route('x')` en vistas que no existe en el router | — |

> **Por qué taint también en landing**: es el único análisis estático que corre
> ahí, y es standalone (no necesita PHPStan). Una landing tiene formularios
> públicos de contacto: la superficie de input más expuesta de todas.

> **El perfil se decide por el código, no por el frontend.** Un sitio que por
> fuera parece landing pero adentro tiene modelos propios, migraciones de dominio
> y panel administrable es **medida**. Lo que justifica el perfil landing son sus
> checks extra (innerHTML, links), no que le falte análisis.

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
    "npm": { "trinquete": { "critical": 0, "high": 0 } }
}
```

Perfil **landing** (sin `phpstan` ni sus reglas, sin PHPMD ni Deptrac; con
`psalm`, `inner_html`, `headers` y `lighthouse`):

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
  `gate-links.php` en landing) bootea sin ellos — probado por 7 CI verdes de la
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
