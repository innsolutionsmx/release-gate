# Referencia — release-gate

## Comandos

| Comando | Qué hace |
|---|---|
| `/release-gate:init` | Instala el gate: detecta perfil (confirmado por humano), vendorea scripts, mide y congela `.gate/baseline.json`, agrega el job de CI |
| `/release-gate:run` | Corre el gate e interpreta las fallas; el fix siempre es la causa, nunca el umbral |
| `/release-gate:ratchet` | Aprieta el trinquete donde la realidad mejoró; nunca afloja |
| `/release-gate:deploy-check` | Post-deploy: headers + Lighthouse contra el sitio vivo; la primera corrida congela los mínimos |
| `/release-gate:doctor` | Salud de la instalación: baseline, drift por checksum contra el plugin, herramientas, CI |

## Checks por perfil

**medida** (sistemas con dominio — `gate-check-medida.sh`):

| Check | Bloquea por | Dato en baseline |
|---|---|---|
| Pint `--test` | formato sucio | `pint.estado` |
| PHPStan nivel 8 + baseline | errores nuevos sobre el baseline | `phpstan.*` |
| Trinquete PHPStan | más entradas que las congeladas | `phpstan.entradas_baseline` |
| gitleaks (historial completo) | secretos nuevos | `secretos.*` (`.gitleaksignore` = riesgos aceptados) |
| composer audit | advisories ≥ `bloquea_desde` | `composer.bloquea_desde` |
| npm audit | superar el trinquete | `npm.trinquete` |

**landing** (sitios de presentación — `gate-check-landing.sh`): Pint, gitleaks,
composer audit, npm audit (mismos datos), más:

| Check | Bloquea por | Dato en baseline |
|---|---|---|
| innerHTML / v-html | archivos fuera de la lista permitida | `inner_html.permitidos` |
| `gate-links.php` | `route('x')` en vistas que no existe en el router | — |

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
        "medicion_inicial_por_nivel": { "0": 4, "8": 999 }
    },
    "pint": { "estado": "limpio" },
    "secretos": { "estado": "limpio", "riesgos_aceptados": ".gitleaksignore" },
    "composer": { "bloquea_desde": "high", "abiertas": {} },
    "npm": { "trinquete": { "critical": 0, "high": 0 } }
}
```

Perfil **landing** (sin `phpstan`, con `inner_html`, `headers` y `lighthouse`):

```json
{
    "schema": 1,
    "congelado": "2026-08-10",
    "perfil": "landing",
    "plugin": "0.1.0",
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
          curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v8.21.2/gitleaks_8.21.2_linux_x64.tar.gz | tar -xz gitleaks
          sudo mv gitleaks /usr/local/bin/

      - name: Install PHP dependencies
        run: composer install --no-interaction --prefer-dist --no-progress --optimize-autoloader

      - name: Prepare Laravel
        run: |
          cp .env.testing .env
          mkdir -p storage/framework/{sessions,views,cache} storage/logs
          chmod -R 777 storage bootstrap/cache
          php artisan key:generate --force

      - name: Release Gate
        run: ./scripts/gate-check.sh
```

Notas:

- gitleaks pinneado (v8.21.2); subir la versión es un cambio consciente, no un `latest`.
- `npm audit` corre desde `package-lock.json` — no hace falta `npm ci`.
- El paso "Prepare Laravel" existe porque `gate-links.php` bootea `artisan
  route:list` (landing) y por la falla histórica de `/storage` entero en
  `.gitignore` (checkout limpio sin `storage/framework` → `artisan` muere).
- El job de tests existente no se toca: el gate es un job aparte, en paralelo.

## Gotchas vigentes (aprendidos en producción)

- PHPStan con poca memoria MUERE y reporta "0 errores": siempre
  `--memory-limit=2G`, y desconfiar de un cero demasiado lindo.
- gitleaks sin historial completo (clone shallow) miente: `fetch-depth: 0`.
- Regenerar `phpstan-baseline.neon` solo está permitido para ACHICARLO
  (`/release-gate:ratchet`); el script cuenta entradas y bloquea si engordó.
- `route('x')` con `->route(` (accessor de Request) está excluido del check de
  links a propósito.
