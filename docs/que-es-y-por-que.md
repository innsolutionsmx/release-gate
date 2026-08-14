# Release Gate — qué es y por qué

## El problema

Los agentes escriben código rápido y con confianza — incluida la mugre: un secreto
commiteado, un `innerHTML` con input de usuario, una dependencia con CVE, un
`route()` a una ruta muerta, errores nuevos de tipos tapados por los viejos. La
revisión humana no escala al ritmo del agente, y "acordate de revisar X" no es un
control, es una esperanza.

## La solución: una compuerta, dos capas

**Capa 1 — determinista, BLOQUEA (este plugin).** Scripts sin opiniones: pasa o
no pasa. Pint, PHPStan con baseline, gitleaks sobre el historial completo, audits
de composer/npm, allowlist de innerHTML, links internos, headers en vivo,
Lighthouse. Si bloquea, no se releasea. Punto.

**Capa 2 — LLM, ASESORA, nunca bloquea (posterior a v0.1.0).** Agentes sec-*
(tenant, ratelimit, authz) que opinan sobre lo que un grep no ve. Criterio de
diseño: si sus falsos positivos superan el 30%, se rediseña. No está en este
plugin todavía — y meterla sin calibrar sería exactamente el tipo de apuro que el
gate existe para frenar.

## Trinquete, no umbral

Un umbral absoluto ("PHPStan en 0") es una fantasía en un codebase real: o se
ignora o se hace trampa. El trinquete congela la realidad de HOY y solo permite
una dirección: **mejorar**. El baseline de PHPStan no puede engordar; el audit de
npm no puede superar lo congelado; los mínimos de Lighthouse no pueden bajar.
Apretar tiene comando (`/release-gate:ratchet`); aflojar, a propósito, no.

## El principio rector: script idéntico, datos en el baseline

Todo script del gate es **byte a byte idéntico entre proyectos** (verificado por
checksum en los repos reales antes de empaquetar). TODO dato del proyecto —
congelados, permitidos, trinquetes, estados en vivo — vive en
`.gate/baseline.json` (schema 1). Consecuencias:

- Un fix del gate es un cambio en UN lugar (el plugin) que se propaga por
  re-vendoreo, no cinco ediciones a mano que divergen.
- El diff de un baseline cuenta la historia del proyecto; el diff de un script
  debería no existir.
- `/release-gate:doctor` reduce "¿este repo está al día?" a comparar checksums.

## Por qué vendorear y no ejecutar desde el plugin

Los scripts se COPIAN al repo (`/release-gate:init`) en vez de ejecutarse desde
el plugin porque el gate tiene que correr donde el plugin no existe: en la CI de
GitHub y en la máquina de un dev sin Claude. El repo queda autocontenido; el
riesgo de drift que el vendoreo introduce lo cubre `doctor` con checksums.

## Dos perfiles, porque el riesgo no es el mismo

- **landing**: sitios de presentación. El riesgo está en la superficie → formato,
  secretos, dependencias, taint por los formularios públicos, innerHTML, links,
  headers y Lighthouse. PHPStan ahí es burocracia, no seguridad.
- **medida**: sistemas con dominio (POS, admin). Tienen la misma superficie que
  una landing **y además** lógica → todo lo anterior, más PHPStan nivel 8 con
  trinquete, reglas propias, PHPMD y Deptrac.

**medida ⊇ landing.** Desde la v0.3.0 el superconjunto es estricto: no existe un
check que corra en landing y no en medida. Elegir medida nunca cuesta cobertura,
así que la decisión se reduce a una pregunta: ¿el repo tiene dominio propio?

Que esto no era así se pagó caro. Hasta la v0.2.0 medida no incluía innerHTML ni
links, así que reclasificar un repo de landing a medida le hacía PERDER dos
checks. Cinco repos de la casa se quedaron en landing por esa razón — aplicaciones
con panel administrable y roles, corriendo sin una sola línea de análisis
estático. La primera vez que se les corrió PHPStan apareció un 500 en producción
que llevaba meses escondido. **Un perfil no es configuración: decide qué sos capaz
de ver.**

## Historia

Diseño original: doc "Release Gate — Compuerta de calidad para código escrito por
agentes" (repo documentacion). Fase A se estrenó en base-project y se extendió a
los 5 derivados (pos-llantera + 4 landings) hasta que 3 repos seguidos pasaron
sin cambios en scripts ni formato — el disparador acordado para empaquetar esto
como plugin (2026-08).
