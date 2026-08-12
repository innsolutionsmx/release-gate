---
description: "Gate post-deploy: headers de seguridad y Lighthouse contra el sitio VIVO; la primera corrida congela los mínimos"
---

Corré los checks post-deploy del gate contra el sitio DESPLEGADO. Estos checks no
corren en CI porque necesitan la URL viva.

## 0. URL

Resolvé la URL en este orden: argumento del usuario → `headers.url` del
`.gate/baseline.json` → preguntale. Sin URL no hay check.

## 1. Headers

```bash
./scripts/gate-headers.sh <url>
```

Checklist tabla-de-verdad: 5 headers obligatorios (HSTS, nosniff, x-frame-options,
referrer-policy, permissions-policy) y 2 prohibidos (x-powered-by, server: caddy).
Si falta alguno, el fix casi siempre es el Caddyfile del deploy — no lo "resolvés"
tocando el baseline. Con resultado limpio, registrá en el baseline:
`headers.verificado_en_vivo` (fecha), `headers.url`, `headers.resultado` ("7/7").

## 2. Lighthouse (con trinquete)

Necesita Chrome (`CHROME_PATH`; default macOS
`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`).

- **Primera corrida** (`lighthouse.minimos` en `null` o ausente): medí con
  `npx --yes lighthouse@12 <url> --quiet --chrome-flags="--headless --no-sandbox"
  --only-categories=performance,accessibility,best-practices,seo --output=json`,
  y CONGELÁ `lighthouse.minimos` con los puntajes medidos (enteros 0-100 por
  categoría). Eso ES el trinquete: el piso es la realidad de hoy. Mostrale los
  números al usuario antes de escribir.
- **Corridas siguientes**: `./scripts/gate-lighthouse.sh <url>` — ninguna
  categoría puede caer bajo su mínimo congelado. Si cae: FALLA del deploy (asset
  pesado nuevo, regresión de a11y…), se arregla el sitio, no el mínimo. Registrá
  `lighthouse.medido` (fecha) y los puntajes.

## 3. Cerrar

Resumen en una línea por check (headers X/7, lighthouse por categoría vs mínimo)
y commit del baseline actualizado siguiendo el flujo git del repo. Si algo falló,
decilo sin vueltas: el deploy tiene una regresión y el gate la cazó — ese es el
trabajo del gate.
