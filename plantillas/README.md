# Plantillas

Configuración que `/release-gate:init` y `/release-gate:upgrade` copian al repo.
A diferencia de los scripts de `scripts/`, estos archivos **el proyecto los puede
tocar**: son su configuración, no el motor del gate.

| Archivo | Va a | Perfil | Se puede editar |
|---|---|---|---|
| `psalm.xml` | raíz del repo | medida y landing | sí, con criterio |
| `phpmd.xml` | raíz del repo | medida | sí — el set curado es un punto de partida |
| `deptrac.yaml` | raíz del repo | medida | sí, si el proyecto suma capas |
| `phpstan-rules/*.php` | `phpstan/Rules/` | medida | **no** — son el motor de las reglas |
| `phpstan-servicios.neon` | se pega en `phpstan.neon.dist` | medida | no |

## Qué instala cada perfil

**medida** — las cuatro: Psalm taint, PHPMD, Deptrac y las reglas propias de
PHPStan.

```bash
composer require --dev vimeo/psalm psalm/plugin-laravel deptrac/deptrac
composer require --dev "phpmd/phpmd:^2.15" --with-all-dependencies
```

**landing** — solo Psalm taint (es standalone: no necesita PHPStan).

```bash
composer require --dev vimeo/psalm psalm/plugin-laravel
```

> **El `--with-all-dependencies` de PHPMD no es opcional.** Sin él, composer
> resuelve `phpmd/phpmd` a la 2.5.0 (de 2016) porque `pdepend/pdepend` queda
> clavado en una versión vieja, y esa combinación tira deprecations en PHP 8.4.
> Con el flag sube pdepend a 2.16 y PHPMD a 2.15.

## Baselines

Cada herramienta trae el suyo, y todos son trinquete: **se achican, nunca crecen**.

| Herramienta | Archivo | Cómo se genera |
|---|---|---|
| Psalm taint | `psalm-taint-baseline.xml` | `vendor/bin/psalm --taint-analysis --set-baseline=psalm-taint-baseline.xml` |
| PHPMD | `phpmd.baseline.xml` | `vendor/bin/phpmd <paths> text phpmd.xml --generate-baseline` |
| Deptrac | `deptrac.baseline.yaml` | `vendor/bin/deptrac analyse --formatter=baseline --output=deptrac.baseline.yaml` |
| Reglas propias | entran al `phpstan-baseline.neon` que ya existe | `vendor/bin/phpstan analyse --generate-baseline` |

Si una herramienta no encuentra nada, **no generes el archivo**: los scripts
tratan la ausencia como cero congelados, que es más honesto que un baseline
vacío. La excepción es `deptrac.baseline.yaml`, que `deptrac.yaml` importa
siempre y por eso tiene que existir aunque sea con `skip_violations: {}`.
