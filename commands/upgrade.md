---
description: "Sube el gate de un repo ya instalado a la versión actual del plugin: instala las herramientas que falten, vendorea scripts y plantillas, mide y congela los baselines nuevos"
---

Llevá el Release Gate de este repo a la versión actual del plugin. `init` es para
repos sin gate; **este comando es para repos que YA lo tienen** y se quedaron atrás.

Regla de oro igual que en `init`: se mide la realidad, nunca se inventan números.
Y una más, propia de este comando: **lo que ya funciona no se toca**. Un baseline
existente no se regenera "de paso" — regenerar es apretar el trinquete y eso tiene
su propio comando (`/release-gate:ratchet`).

## 0. Guardas

- Tiene que existir `.gate/baseline.json`. Si no existe, el repo nunca tuvo gate:
  mandá a `/release-gate:init` y frená.
- Leé `plugin` del baseline (versión con la que se instaló) y la versión actual en
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Si son iguales y `doctor` no
  reporta drift, no hay nada que hacer: decilo y frená.
- Flujo git de la casa: NO trabajes sobre `main`/`dev`. Rama `chore/release-gate-upgrade`
  desde `dev` actualizado.
- Corré `./scripts/gate-check.sh` ANTES de tocar nada. **Si el gate ya viene
  bloqueado, frená**: primero se arregla lo que está roto, después se agrega
  exigencia. Traele el resultado al usuario.

## 1. Qué le falta a este repo

Leé el `perfil` del baseline y armá la lista de faltantes:

| Necesita | medida | landing |
|---|---|---|
| Psalm taint (`psalm.xml`) | sí | sí |
| PHPMD (`phpmd.xml`) | sí | no |
| Deptrac (`deptrac.yaml`) | sí | no |
| Reglas propias (`phpstan/Rules/`) | sí | no |

Las reglas propias son reglas de PHPStan: **si el repo no tiene PHPStan, no van**.
Un repo `landing` no tiene PHPStan por diseño; si el usuario quiere las reglas ahí,
eso no es un upgrade sino un cambio de perfil — es otra conversación, traésela.

Mostrale al usuario la lista de lo que falta y **confirmá antes de instalar**.

## 2. Dependencias

Según el perfil (comandos exactos y el porqué del flag: `${CLAUDE_PLUGIN_ROOT}/plantillas/README.md`):

```bash
# medida
composer require --dev vimeo/psalm psalm/plugin-laravel deptrac/deptrac
composer require --dev "phpmd/phpmd:^2.15" --with-all-dependencies

# landing
composer require --dev vimeo/psalm psalm/plugin-laravel
```

⚠️ El `--with-all-dependencies` de PHPMD **no es opcional**: sin él composer
resuelve la 2.5.0 de 2016 y tira deprecations en PHP 8.4.

Verificá versión de cada binario instalado antes de seguir.

## 3. Vendorear

Scripts, desde `${CLAUDE_PLUGIN_ROOT}/scripts/`: `gate-check-<perfil>.sh` →
`scripts/gate-check.sh` (pisa el viejo), y los demás del perfil según `init`.
`chmod +x`. NO los edites.

Plantillas, desde `${CLAUDE_PLUGIN_ROOT}/plantillas/`, solo las del perfil:

- `psalm.xml`, `phpmd.xml`, `deptrac.yaml` → raíz del repo.
- `phpstan-rules/*.php` → `phpstan/Rules/` (creá el directorio).
- `phpstan-servicios.neon` → **no se copia**: su contenido se PEGA en el
  `phpstan.neon.dist` del repo, al mismo nivel que `parameters:`.

Si alguno de esos archivos ya existe con contenido distinto, **no lo pises**:
mostrá el diff y preguntá.

## 4. Tocar el `composer.json` del repo (solo medida)

Las reglas necesitan autoload. Agregá a `autoload-dev.psr-4`:

```json
"Gate\\PHPStan\\": "phpstan/"
```

y corré `composer dump-autoload`. Verificá que la clase resuelve antes de seguir
(por ejemplo, que `vendor/bin/phpstan` arranque sin "class not found").

Este es el único paso donde el gate escribe en el `composer.json` del proyecto:
hacelo explícito al usuario, mostrale el diff y no lo hagas en silencio.

## 5. Medir y congelar los baselines nuevos

**Uno por uno, y en este orden** (de más barato a más caro de interpretar). Para
cada uno: corré la herramienta, mostrale al usuario lo que encontró, y recién
después congelá.

1. **Psalm taint**: `vendor/bin/psalm --taint-analysis --no-progress`.
   - Sin hallazgos → **no generes archivo**, `psalm.entradas_baseline: 0`.
   - Con hallazgos → LEÉLOS con el usuario antes de congelar. Un taint real es un
     bug de seguridad, no deuda técnica: puede convenir arreglarlo en vez de
     congelarlo. Si se congela:
     `vendor/bin/psalm --taint-analysis --set-baseline=psalm-taint-baseline.xml`
     y contá con `grep -c '<code>'`.
2. **PHPMD** (medida): `vendor/bin/phpmd <paths> text phpmd.xml`. Si hay
   violaciones, `--generate-baseline` y contá `grep -c '<violation'`. Guardá los
   paths analizados en `phpmd.paths` si difieren del default
   (`app,routes,database/seeders`).
3. **Deptrac** (medida): creá `deptrac.baseline.yaml` con `deptrac:\n  skip_violations: {}`
   ANTES de correr (el `deptrac.yaml` lo importa siempre). Después
   `vendor/bin/deptrac analyse --formatter=baseline --output=deptrac.baseline.yaml`
   y contá `grep -c -- '- App'`.
4. **Reglas propias** (medida): `vendor/bin/phpstan analyse --memory-limit=2G`.
   Los hallazgos son deuda vieja que una regla nueva recién ve — mismo criterio
   que las otras herramientas: se congelan.
   `--generate-baseline`, y **auditá el diff**: tienen que aparecer SOLO entradas
   con identifier `gate.controllerQuery` / `gate.controllerPersist`. Si aparece
   otra cosa, el refactor rompió algo: frená.
   Actualizá `phpstan.entradas_baseline` y dejá en `phpstan.nota_entradas` por qué
   creció (regla nueva, no código nuevo).

## 6. Actualizar `.gate/baseline.json`

Schema sigue en **1** — las secciones nuevas son extensión compatible, no bump.
Agregá solo las del perfil (ejemplos completos en `${CLAUDE_PLUGIN_ROOT}/docs/referencia.md`):

```json
"psalm":   { "modo": "taint-only", "congelado": "<hoy>", "entradas_baseline": 0 },
"phpmd":   { "reglas": "curado: unusedcode + codesize + design selecto", "congelado": "<hoy>", "entradas_baseline": 0 },
"deptrac": { "modo": "pragmático: Controller→Model permitido (bindings); queries en Actions", "congelado": "<hoy>", "entradas_baseline": 0 },
"reglas_gate": { "descripcion": "Reglas propias en phpstan/Rules/: prohíben queries y escrituras de Eloquent en Controllers", "congelado": "<hoy>", "ocurrencias_congeladas": 0 }
```

Actualizá también `plugin` a la versión nueva.

## 7. Verificar y cerrar

1. `./scripts/gate-check.sh` tiene que terminar en **✓ GATE APROBADO**. Si bloquea,
   arreglá la causa real; NUNCA aflojes un baseline para que pase.
2. Corré los tests del repo. Si el upgrade tocó código (no debería), tienen que
   seguir verdes.
3. La CI **no cambia**: el job `gate` ya corre `./scripts/gate-check.sh` y las
   herramientas entran por `composer install`. Verificá igual que el workflow no
   use `--no-dev`.
4. Mostrale al usuario el resumen: qué se instaló, qué se congeló y con qué números.
5. Commit en la rama (Conventional Commits) y seguí el flujo git del repo.
