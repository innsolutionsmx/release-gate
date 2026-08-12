#!/usr/bin/env bash
# Gate post-deploy: headers de seguridad del sitio DESPLEGADO.
# Checklist = tabla de verdad, no criterio. Correr tras cada deploy:
#   ./scripts/gate-headers.sh https://dominio-de-produccion.mx
#
# Vendoreado por /release-gate:init — NO editar a mano (drift: /release-gate:doctor).
set -euo pipefail

URL="${1:?Uso: gate-headers.sh <url-desplegada>}"

HEADERS=$(curl -sI --max-time 20 "$URL")
FAIL=0

for esperado in \
    'strict-transport-security' \
    'x-content-type-options: nosniff' \
    'x-frame-options' \
    'referrer-policy' \
    'permissions-policy'; do
    if echo "$HEADERS" | tr '[:upper:]' '[:lower:]' | grep -q "$esperado"; then
        echo "OK: $esperado"
    else
        echo "FALTA: $esperado"
        FAIL=1
    fi
done

for prohibido in 'x-powered-by' 'server: caddy'; do
    if echo "$HEADERS" | tr '[:upper:]' '[:lower:]' | grep -q "$prohibido"; then
        echo "SOBRA: $prohibido (fuga de información del stack)"
        FAIL=1
    else
        echo "OK: sin $prohibido"
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo "✗ HEADERS INCOMPLETOS — ¿se desplegó el Caddyfile nuevo?"
    exit 1
fi
echo "✓ HEADERS EN ORDEN"
