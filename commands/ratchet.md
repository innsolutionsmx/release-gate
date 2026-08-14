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
2. **Psalm `entradas_baseline`** (ambos perfiles): corré
   `vendor/bin/psalm --taint-analysis --no-progress`. Si el baseline perdona
   flujos que ya no existen, regenerá con
   `--set-baseline=psalm-taint-baseline.xml` y contá `grep -c '<code>'`.
   **Si el conteo llega a 0, BORRÁ el archivo** y dejá `entradas_baseline: 0`: un
   baseline vacío es un archivo que perdona nada y confunde al que lo lee.
3. **PHPMD `entradas_baseline`** (medida): `vendor/bin/phpmd <paths> text phpmd.xml`.
   Si hay menos violaciones que las congeladas, regenerá con `--generate-baseline`
   y contá `grep -c '<violation'`. Mismo criterio: en 0, borrá `phpmd.baseline.xml`.
4. **Deptrac `entradas_baseline`** (medida):
   `vendor/bin/deptrac analyse --formatter=baseline --output=deptrac.baseline.yaml`
   y contá `grep -c -- '- App'`. ⚠️ Acá el archivo **NO se borra aunque llegue a
   0**: `deptrac.yaml` lo importa siempre y sin él la herramienta no arranca. Dejalo
   con `deptrac:\n  skip_violations: {}`.
5. **npm `trinquete`**: si el audit real da menos que lo congelado (p. ej. quedó
   en 0/0 y el baseline decía 2 high), bajá el trinquete al valor real.
6. **composer `bloquea_desde`**: proponer subir la exigencia (`high` → `medium`)
   solo si el audit ya está limpio en ese nivel. Es decisión del usuario.
7. **Lighthouse `minimos`**: si `/release-gate:deploy-check` midió puntajes por
   encima de los mínimos congelados de forma sostenida, subí los mínimos al nuevo
   piso real. Nunca los bajes — si un puntaje cayó, eso es una FALLA del gate
   post-deploy, no un motivo de ajuste.
8. **`inner_html.permitidos`** (ambos perfiles): si un archivo permitido dejó de
   usar `innerHTML` —porque se saneó o se borró— sacalo de la lista. Un permitido
   que sobra es una puerta abierta a un archivo que mañana vuelve a inyectar.

⚠️ **Regla común a los cuatro baselines de análisis** (PHPStan, Psalm, PHPMD,
Deptrac): regenerar SIEMPRE se audita con el diff, no con el conteo. El diff solo
puede REMOVER entradas. Si agrega aunque sea una, no mejoraste: cambiaste el
problema de lugar. Abortá y restaurá el archivo.

## Cerrar

- Actualizá los valores apretados en `.gate/baseline.json` y anotá la fecha del
  nuevo congelado en cada sección tocada.
- Corré `./scripts/gate-check.sh` — tiene que dar APROBADO con los números nuevos.
- Mostrá el diff de números: congelado viejo → nuevo, por check.
- Commit en rama propia (`chore/gate-ratchet-...`), flujo git del repo.
