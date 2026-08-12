# Desarrollo y releases — release-gate

## Reglas de la casa (innegociables)

1. **Plan primero**: en este repo, todo cambio de comportamiento nace de un plan
   aprobado por Rodrigo ANTES de escribir, pushear o versionar.
2. **Push a `main` = release**: quien consume el plugin instala desde `main`. No
   se pushea a `main` nada que no esté listo para instalarse ya.
3. **Los scripts del gate son la fuente de verdad de los repos consumidores**:
   un cambio acá se propaga por re-vendoreo (`doctor` lo detecta y ofrece
   actualizar). Cambiar un script es tocar TODOS los repos con gate — actuar en
   consecuencia.

## Flujo de un cambio

1. Plan aprobado → rama de trabajo (`feat/...`, `fix/...`).
2. Cambios + bump de `version` en `.claude-plugin/plugin.json` (semver: fix =
   patch, comando/check nuevo = minor, cambio de schema del baseline o de
   contrato de scripts = major).
3. **Gate del manifest**: `bash scripts/validate-manifest.sh` tiene que pasar.
   Existe porque un `plugin.json` inválido se lleva puesto el plugin entero en la
   máquina del consumidor (lección de design-forge v0.6.0).
4. Merge a `main` + push (= release) + tag `vX.Y.Z`.
5. Post-release: en un repo consumidor, `claude plugin list` debe mostrar
   `✔ enabled`, y `/release-gate:doctor` debe detectar el drift esperado y
   ofrecer re-vendorear.

## Si cambia el schema del baseline

Subir `schema` (hoy: 1), documentar la migración en `docs/referencia.md`, y
enseñarle a `doctor` a detectar el schema viejo y guiar la migración. Nunca
romper en silencio un baseline existente.

## Capa 2 (futuro, post-v0.1.0)

Los agentes sec-* (tenant, ratelimit, authz) entran DESPUÉS, como capa asesora
que nunca bloquea, calibrados contra un proyecto real (CONAPESCA) con umbral de
rediseño en 30% de falsos positivos. No adelantar: el orden es parte del diseño.
