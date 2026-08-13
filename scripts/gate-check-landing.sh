#!/usr/bin/env bash
# Release Gate — capa 1 determinista, PERFIL LANDING.
# Formato, secretos, dependencias, taint, innerHTML, links. Sin PHPStan ni
# mutación: en una landing la barra es superficie de ataque y performance.
#
# Psalm corre en modo taint-only (no necesita PHPStan): una landing tiene
# formularios públicos, que son la superficie de input más expuesta de todas.
#
# Vendoreado por /release-gate:init como scripts/gate-check.sh — NO editar a mano:
# el script es idéntico entre proyectos; TODO dato del proyecto vive en
# .gate/baseline.json. Drift contra el plugin: /release-gate:doctor.
#
# Este script corre en CI (todo lo que se puede verificar sin el sitio vivo).
# Los checks POST-DEPLOY (necesitan el sitio desplegado) van aparte:
#   ./scripts/gate-headers.sh <url>      headers de seguridad en vivo
#   ./scripts/gate-lighthouse.sh <url>   performance/a11y/bp/seo con trinquete
set -euo pipefail

cd "$(dirname "$0")/.."

FAIL=0

echo "── Gate: Pint (formato) ──────────────────────────────"
if vendor/bin/pint --test > /dev/null 2>&1; then
    echo "OK: formato limpio"
else
    echo "FALLA: hay archivos sin formatear. Corré: vendor/bin/pint"
    FAIL=1
fi

echo "── Gate: Psalm taint (input de usuario → sink) ───────"
# Rastrea flujo contaminado input → sink (XSS, SQLi, shell, unserialize,
# open redirect). Es el único análisis estático del perfil landing y es
# standalone: no requiere PHPStan ni su baseline.
PSALM_CONGELADOS=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->psalm->entradas_baseline ?? 0;')
PSALM_ARGS=(--taint-analysis --no-progress)
if [ -f psalm-taint-baseline.xml ]; then
    PSALM_ARGS+=(--use-baseline=psalm-taint-baseline.xml)
fi
if vendor/bin/psalm "${PSALM_ARGS[@]}" > /dev/null 2>&1; then
    echo "OK: sin flujos contaminados nuevos"
else
    echo "FALLA: flujos contaminados nuevos (el baseline solo perdona los congelados):"
    vendor/bin/psalm "${PSALM_ARGS[@]}" --output-format=compact 2>&1 | tail -30 || true
    FAIL=1
fi

echo "── Gate: trinquete taint (el baseline no puede engordar) ─"
PSALM_ACTUALES=0
if [ -f psalm-taint-baseline.xml ]; then
    PSALM_ACTUALES=$(grep -c '<code>' psalm-taint-baseline.xml || true)
fi
if [ "$PSALM_ACTUALES" -le "$PSALM_CONGELADOS" ]; then
    echo "OK: baseline de taint con $PSALM_ACTUALES entradas (congelado: $PSALM_CONGELADOS)"
else
    echo "FALLA: el baseline de taint creció de $PSALM_CONGELADOS a $PSALM_ACTUALES entradas."
    echo "Regenerar el baseline para perdonar flujos nuevos NO está permitido."
    FAIL=1
fi

echo "── Gate: gitleaks (historial completo) ───────────────"
if gitleaks git --no-banner --redact --exit-code 1 . > /dev/null 2>&1; then
    echo "OK: sin secretos (riesgos aceptados en .gitleaksignore)"
else
    echo "FALLA: gitleaks encontró secretos nuevos:"
    gitleaks git --no-banner --redact . 2>&1 | tail -20 || true
    FAIL=1
fi

echo "── Gate: composer audit ──────────────────────────────"
# La severidad que bloquea vive en .gate/baseline.json (composer.bloquea_desde),
# no acá: el script es idéntico entre proyectos, los datos son del proyecto.
COMPOSER_ALTAS=$( (composer audit --locked --format=json 2>/dev/null || true) | php -r '
    $d = json_decode(stream_get_contents(STDIN), true);
    $desde = json_decode(file_get_contents(".gate/baseline.json"), true)["composer"]["bloquea_desde"] ?? "high";
    $rango = ["low" => 0, "medium" => 1, "high" => 2, "critical" => 3];
    $min = $rango[$desde] ?? 2;
    $n = 0;
    $advs = $d["advisories"] ?? [];
    if (is_array($advs)) foreach ($advs as $adv) {
        if (is_array($adv)) foreach ($adv as $a) {
            if (($rango[$a["severity"] ?? ""] ?? -1) >= $min) $n++;
        }
    }
    echo $n;')
if [ "$COMPOSER_ALTAS" -eq 0 ]; then
    echo "OK: sin advisories que bloqueen en composer"
else
    echo "FALLA: $COMPOSER_ALTAS advisories bloqueantes:"
    composer audit --locked 2>&1 | tail -20 || true
    FAIL=1
fi

echo "── Gate: npm audit (trinquete) ───────────────────────"
NPM_CHECK=$( (npm audit --json 2>/dev/null || true) | php -r '
    $d = json_decode(stream_get_contents(STDIN), true);
    $b = json_decode(file_get_contents(".gate/baseline.json"), true)["npm"]["trinquete"];
    $v = $d["metadata"]["vulnerabilities"] ?? [];
    $crit = $v["critical"] ?? 0; $high = $v["high"] ?? 0;
    if ($crit > $b["critical"] || $high > $b["high"]) {
        echo "FALLA: critical=$crit (max {$b["critical"]}), high=$high (max {$b["high"]})";
    } else {
        echo "OK: critical=$crit/{$b["critical"]}, high=$high/{$b["high"]} (congelado)";
    }')
echo "$NPM_CHECK"
case "$NPM_CHECK" in FALLA*) FAIL=1;; esac

echo "── Gate: innerHTML / v-html ──────────────────────────"
# La lista de permitidos vive en .gate/baseline.json (inner_html.permitidos),
# no acá: el script es idéntico entre proyectos, los datos son del proyecto.
PERMITIDOS=$(php -r '
    $p = json_decode(file_get_contents(".gate/baseline.json"), true)["inner_html"]["permitidos"] ?? [];
    echo implode("|", array_map("preg_quote", $p));')
if [ -n "$PERMITIDOS" ]; then
    HITS=$(grep -rlnE 'innerHTML|v-html' resources/js resources/views 2>/dev/null | grep -vE "$PERMITIDOS" || true)
else
    HITS=$(grep -rlnE 'innerHTML|v-html' resources/js resources/views 2>/dev/null || true)
fi
if [ -z "$HITS" ]; then
    echo "OK: sin innerHTML fuera de la lista permitida"
else
    echo "FALLA: innerHTML/v-html en archivos no permitidos:"
    echo "$HITS"
    FAIL=1
fi

echo "── Gate: links internos (route() vs router) ──────────"
if php scripts/gate-links.php; then
    :
else
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "✗ GATE BLOQUEADO"
    exit 1
fi
echo "✓ GATE APROBADO"
