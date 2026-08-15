#!/usr/bin/env bash
# Release Gate — envoltorio que corre gate-check.sh INTACTO y escribe la
# evidencia de la corrida (.gate/last-run.json), siempre — aprobado o
# bloqueado — propagando el exit code original.
#
# gate-check.sh sigue leyendo y nunca escribiendo (asimetría vigente desde
# v0.1.0). Este script es el ÚNICO punto que produce evidencia: el tablero
# (gate-status.sh) y el guard de push (.claude/hooks/gate-push-guard.sh) la
# leen, nunca la infieren.
#
# Vendoreado por /release-gate:init y /release-gate:upgrade tal cual — NO
# editar a mano. Invocado por /release-gate:run.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .gate/baseline.json ]; then
    echo "No hay .gate/baseline.json — corré /release-gate:init primero." >&2
    exit 1
fi

# ── Correr gate-check.sh intacto, capturar el exit code sin morir por -e ──
RC=0
./scripts/gate-check.sh || RC=$?

# ── Evidencia de la corrida ────────────────────────────────────────────────
PERFIL=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->perfil ?? "landing";')
PLUGIN=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->plugin ?? "?";')
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "desconocido")
FECHA=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')

if [ -z "$(git status --porcelain 2>/dev/null || true)" ]; then
    ARBOL_LIMPIO=true
else
    ARBOL_LIMPIO=false
fi

if [ "$RC" -eq 0 ]; then
    VEREDICTO="APROBADO"
else
    VEREDICTO="BLOQUEADO"
fi

# Conteos: mismo conteo por grep que gate-status.sh, solo para las
# herramientas del perfil activo. Fuera de perfil ⇒ null (no aplica).
CONTEO_PSALM=0
if [ -f psalm-taint-baseline.xml ]; then
    CONTEO_PSALM=$(grep -c '<code>' psalm-taint-baseline.xml || true)
fi

CONTEO_PHPSTAN=null
CONTEO_PHPMD=null
CONTEO_DEPTRAC=null
if [ "$PERFIL" = "medida" ]; then
    CONTEO_PHPSTAN=0
    if [ -f phpstan-baseline.neon ]; then
        CONTEO_PHPSTAN=$(grep -c 'message:' phpstan-baseline.neon || true)
    fi
    CONTEO_PHPMD=0
    if [ -f phpmd.baseline.xml ]; then
        CONTEO_PHPMD=$(grep -c '<violation' phpmd.baseline.xml || true)
    fi
    CONTEO_DEPTRAC=0
    if [ -f deptrac.baseline.yaml ]; then
        CONTEO_DEPTRAC=$(grep -c -- '- App' deptrac.baseline.yaml || true)
    fi
fi

mkdir -p .gate
cat > .gate/last-run.json <<EOF
{
  "schema": 1,
  "fecha": "${FECHA}",
  "commit": "${COMMIT}",
  "arbol_limpio": ${ARBOL_LIMPIO},
  "veredicto": "${VEREDICTO}",
  "perfil": "${PERFIL}",
  "plugin": "${PLUGIN}",
  "conteos": { "phpstan": ${CONTEO_PHPSTAN}, "psalm": ${CONTEO_PSALM}, "phpmd": ${CONTEO_PHPMD}, "deptrac": ${CONTEO_DEPTRAC} }
}
EOF

exit "$RC"
