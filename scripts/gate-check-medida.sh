#!/usr/bin/env bash
# Release Gate — capa 1 determinista, PERFIL MEDIDA.
# Pint + PHPStan n8 (con reglas propias) + Psalm taint + PHPMD + Deptrac +
# gitleaks + audits. Todo con trinquete. Pasa o no pasa. Sin opiniones.
#
# Vendoreado por /release-gate:init como scripts/gate-check.sh — NO editar a mano:
# el script es idéntico entre proyectos; TODO dato del proyecto vive en
# .gate/baseline.json. Drift contra el plugin: /release-gate:doctor.
#
# Los checks POST-DEPLOY (necesitan el sitio vivo) van aparte:
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

echo "── Gate: PHPStan nivel 8 + baseline (trinquete) ──────"
CONGELADOS=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->phpstan->entradas_baseline;')
if vendor/bin/phpstan analyse --memory-limit=2G --no-progress > /dev/null 2>&1; then
    echo "OK: sin errores nuevos sobre el baseline"
else
    echo "FALLA: errores nuevos de PHPStan (el baseline solo perdona los congelados):"
    vendor/bin/phpstan analyse --memory-limit=2G --no-progress 2>&1 | tail -40 || true
    FAIL=1
fi

echo "── Gate: trinquete (el baseline no puede engordar) ───"
ACTUALES=$(grep -c 'message:' phpstan-baseline.neon || true)
if [ "$ACTUALES" -le "$CONGELADOS" ]; then
    echo "OK: baseline con $ACTUALES entradas (congelado: $CONGELADOS)"
else
    echo "FALLA: el baseline creció de $CONGELADOS a $ACTUALES entradas."
    echo "Regenerar el baseline para perdonar errores nuevos NO está permitido."
    FAIL=1
fi

echo "── Gate: Psalm taint (input de usuario → sink) ───────"
# Taint-only: Psalm NO corre como segundo analizador general (eso ya lo hace
# PHPStan n8); acá solo rastrea flujo contaminado input → sink (XSS, SQLi,
# shell, unserialize, open redirect). Baseline aparte del de PHPStan.
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

echo "── Gate: PHPMD (complejidad / código muerto) ─────────"
# Set curado en phpmd.xml (unusedcode + codesize + design selecto; sin
# StaticAccess ni naming). Los directorios analizados son dato del proyecto:
# viven en .gate/baseline.json (phpmd.paths). Usa phpmd.baseline.xml si existe.
PHPMD_CONGELADOS=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->phpmd->entradas_baseline ?? 0;')
PHPMD_PATHS=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->phpmd->paths ?? "app,routes,database/seeders";')
if vendor/bin/phpmd "$PHPMD_PATHS" text phpmd.xml > /dev/null 2>&1; then
    echo "OK: sin violaciones nuevas sobre el baseline"
else
    echo "FALLA: violaciones nuevas de PHPMD (el baseline solo perdona las congeladas):"
    vendor/bin/phpmd "$PHPMD_PATHS" text phpmd.xml 2>/dev/null | tail -30 || true
    FAIL=1
fi

echo "── Gate: trinquete PHPMD (el baseline no puede engordar) ─"
PHPMD_ACTUALES=0
if [ -f phpmd.baseline.xml ]; then
    PHPMD_ACTUALES=$(grep -c '<violation' phpmd.baseline.xml || true)
fi
if [ "$PHPMD_ACTUALES" -le "$PHPMD_CONGELADOS" ]; then
    echo "OK: baseline de PHPMD con $PHPMD_ACTUALES entradas (congelado: $PHPMD_CONGELADOS)"
else
    echo "FALLA: el baseline de PHPMD creció de $PHPMD_CONGELADOS a $PHPMD_ACTUALES entradas."
    echo "Regenerar el baseline para perdonar violaciones nuevas NO está permitido."
    FAIL=1
fi

echo "── Gate: Deptrac (arquitectura de capas) ─────────────"
# La arquitectura de la casa como regla ejecutable (deptrac.yaml). Pragmático:
# Controller→Model está permitido porque Deptrac no distingue el route model
# binding de una query — eso lo cubren las reglas propias de PHPStan, que miran
# LLAMADAS. Violaciones congeladas en deptrac.baseline.yaml (skip_violations).
DEPTRAC_CONGELADOS=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->deptrac->entradas_baseline ?? 0;')
if vendor/bin/deptrac analyse --no-progress > /dev/null 2>&1; then
    echo "OK: sin violaciones de capas nuevas"
else
    echo "FALLA: violaciones de arquitectura nuevas (el baseline solo perdona las congeladas):"
    vendor/bin/deptrac analyse --no-progress 2>&1 | tail -30 || true
    FAIL=1
fi

echo "── Gate: trinquete Deptrac (el baseline no puede engordar) ─"
DEPTRAC_ACTUALES=0
if [ -f deptrac.baseline.yaml ]; then
    DEPTRAC_ACTUALES=$(grep -c -- '- App' deptrac.baseline.yaml || true)
fi
if [ "$DEPTRAC_ACTUALES" -le "$DEPTRAC_CONGELADOS" ]; then
    echo "OK: baseline de Deptrac con $DEPTRAC_ACTUALES entradas (congelado: $DEPTRAC_CONGELADOS)"
else
    echo "FALLA: el baseline de Deptrac creció de $DEPTRAC_CONGELADOS a $DEPTRAC_ACTUALES entradas."
    echo "Regenerar el baseline para perdonar violaciones nuevas NO está permitido."
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
    echo "FALLA: $COMPOSER_ALTAS advisories bloqueantes (ver: composer audit --locked)"
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

if [ "$FAIL" -ne 0 ]; then
    echo "✗ GATE BLOQUEADO"
    exit 1
fi
echo "✓ GATE APROBADO"
