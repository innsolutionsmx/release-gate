---
description: "Aprieta el trinquete: cuando la realidad mejoró, el baseline se congela más exigente. Una sola dirección."
---

Apretá el trinquete del gate: medí la realidad y, donde MEJORÓ respecto del
baseline congelado, congelá el número nuevo. El trinquete tiene UNA dirección —
más apretado. Aflojar no existe en este comando.

## Guardas

- Sin `.gate/baseline.json` → `/release-gate:init` y frená.
- Antes de apretar, el gate tiene que estar APROBADO (`./scripts/gate-check.sh`).
  Apretar sobre un gate roto es mentirse.

## Qué se puede apretar (por perfil)

1. **PHPStan `entradas_baseline`** (medida): si hay MENOS errores reales que
   entradas congeladas, regenerá el baseline —
   `vendor/bin/phpstan analyse --memory-limit=2G --generate-baseline` — y verificá
   con `grep -c 'message:' phpstan-baseline.neon` que el conteo BAJÓ. Regenerar
   está permitido ÚNICAMENTE acá y únicamente si achica; si el conteo sube, es un
   intento de aflojar disfrazado: abortá y restaurá el archivo.
2. **npm `trinquete`**: si el audit real da menos que lo congelado (p. ej. quedó
   en 0/0 y el baseline decía 2 high), bajá el trinquete al valor real.
3. **composer `bloquea_desde`**: proponer subir la exigencia (`high` → `medium`)
   solo si el audit ya está limpio en ese nivel. Es decisión del usuario.
4. **Lighthouse `minimos`**: si `/release-gate:deploy-check` midió puntajes por
   encima de los mínimos congelados de forma sostenida, subí los mínimos al nuevo
   piso real. Nunca los bajes — si un puntaje cayó, eso es una FALLA del gate
   post-deploy, no un motivo de ajuste.

## Cerrar

- Actualizá los valores apretados en `.gate/baseline.json` y anotá la fecha del
  nuevo congelado en cada sección tocada.
- Corré `./scripts/gate-check.sh` — tiene que dar APROBADO con los números nuevos.
- Mostrá el diff de números: congelado viejo → nuevo, por check.
- Commit en rama propia (`chore/gate-ratchet-...`), flujo git del repo.
