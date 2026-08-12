#!/usr/bin/env bash
# Gate post-deploy: Lighthouse contra el sitio DESPLEGADO, con trinquete.
# Ninguna categoría puede bajar del umbral congelado en .gate/baseline.json.
# Necesita el sitio vivo (como gate-headers.sh) -> no corre en CI, corre tras deploy:
#   ./scripts/gate-lighthouse.sh https://dominio-de-produccion.mx
#
# Vendoreado por /release-gate:init — NO editar a mano (drift: /release-gate:doctor).
set -euo pipefail

cd "$(dirname "$0")/.."
URL="${1:?Uso: gate-lighthouse.sh <url-desplegada>}"

CHROME_PATH="${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SALIDA=$(mktemp -t lh-gate.XXXXXX.json)
trap 'rm -f "$SALIDA"' EXIT

echo "Corriendo Lighthouse contra $URL ..."
CHROME_PATH="$CHROME_PATH" npx --yes lighthouse@12 "$URL" \
    --quiet --chrome-flags="--headless --no-sandbox" \
    --only-categories=performance,accessibility,best-practices,seo \
    --output=json --output-path="$SALIDA" > /dev/null 2>&1

php -r '
    $r = json_decode(file_get_contents($argv[1]), true)["categories"];
    $b = json_decode(file_get_contents(".gate/baseline.json"), true)["lighthouse"]["minimos"];
    $fail = 0;
    foreach ($b as $cat => $min) {
        $score = (int) round(($r[$cat]["score"] ?? 0) * 100);
        if ($score < $min) { echo "FALLA: $cat = $score (mínimo $min)\n"; $fail = 1; }
        else               { echo "OK: $cat = $score (mínimo $min)\n"; }
    }
    exit($fail);
' "$SALIDA"

echo "✓ LIGHTHOUSE EN ORDEN (ninguna categoría bajó del trinquete)"
