---
description: "Corre el gate del repo y, si bloquea, interpreta la falla y guía el fix real"
---

Corré el Release Gate de este repo e interpretá el resultado.

## Guardas

- Si no existe `.gate/baseline.json` o `scripts/gate-check.sh`: el gate no está
  instalado — ofrecé `/release-gate:init` y frená.

## Correr

```bash
./scripts/gate-check.sh
```

Mostrá la salida completa. Si termina en **✓ GATE APROBADO**, listo — no inventes
trabajo.

## Si bloquea: interpretar y guiar

Por cada `FALLA`, el fix es la CAUSA, nunca el umbral:

| Falla | Fix real | Lo que NO se hace |
|---|---|---|
| Pint | `vendor/bin/pint` | — |
| PHPStan errores nuevos | arreglar el código nuevo | regenerar el baseline para perdonarlos |
| Trinquete engordó | borrar los errores nuevos, no perdonarlos | subir `entradas_baseline` |
| `gate.controllerQuery` / `gate.controllerPersist` | mover la query o la escritura del Controller a un Action | perdonarla en el baseline |
| Psalm taint | cortar el flujo: escapar/validar en el borde, o dejar de pasar input de usuario a ese sink | congelarlo — **un taint nuevo es un bug de seguridad, no deuda** |
| PHPMD | partir el método o la clase, borrar el código muerto, sacar el `dd()`/`dump()` que quedó | subir los umbrales de `phpmd.xml` |
| Deptrac | respetar la capa: la query va en el Action, no en el Controller | agregar la violación a `skip_violations` |
| gitleaks | rotar el secreto + limpiar; aceptar riesgo en `.gitleaksignore` es decisión del usuario | aceptarlo vos solo |
| composer/npm audit | subir la dependencia afectada | aflojar `bloquea_desde` o el trinquete |
| innerHTML | sanear el archivo o justificarlo ante el usuario para sumarlo a permitidos | agregarlo a `permitidos` sin revisión humana |
| gate-links | crear la ruta o corregir la vista | — |

**REGLA DURA**: modificar `.gate/baseline.json` o `phpstan-baseline.neon` para que
el gate pase está PROHIBIDO. El baseline solo se toca para APRETAR
(`/release-gate:ratchet`) o por decisión explícita del usuario, que queda anotada.

⚠️ Gotchas vigentes: PHPStan sin `--memory-limit=2G` muere y reporta "0 errores"
(el script ya lo pasa, pero si corrés PHPStan a mano, no lo olvides); gitleaks
necesita el historial completo (en un clone shallow miente).

Cerrá con el veredicto en una línea: qué bloqueó, qué falta para pasar.
