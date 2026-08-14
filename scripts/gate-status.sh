#!/usr/bin/env bash
# Release Gate — tablero de estado por CONTEO, nunca por re-análisis.
# Tres columnas por herramienta: congelado (.gate/baseline.json), en archivo
# (grep -c sobre el archivo de baseline propio de la herramienta) y realidad
# (siempre "requiere analisis": este script NO corre ningún analizador).
#
# Vendoreado por /release-gate:init y /release-gate:upgrade tal cual — NO
# editar a mano: es idéntico entre repos, TODO dato del proyecto vive en
# .gate/baseline.json. Drift contra el plugin: /release-gate:doctor.
#
# Invocado por .claude/hooks/gate-session-status.sh (SessionStart) y a mano
# para revisión rápida. Presupuesto: <300ms sin overhead de Claude Code.
# Sin .gate/baseline.json: cero output, exit 0 siempre.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .gate/baseline.json ]; then
    exit 0
fi

PERFIL=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->perfil ?? "landing";')
PLUGIN_VENDOREADO=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->plugin ?? "?";')

if [ "$PERFIL" = "medida" ]; then
    CHECKS=14
else
    CHECKS=8
fi

echo "Release Gate — perfil ${PERFIL} (${CHECKS} checks)"

# ── Versión: vendoreado vs disponible ─────────────────────────────────────
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    if [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; then
        PLUGIN_DISPONIBLE=$(php -r "echo json_decode(file_get_contents('${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json'))->version ?? '?';")
        if [ "$PLUGIN_VENDOREADO" != "$PLUGIN_DISPONIBLE" ]; then
            echo "  Plugin: vendoreado ${PLUGIN_VENDOREADO} | disponible ${PLUGIN_DISPONIBLE}  [ATRASADO -> /release-gate:upgrade]"
        else
            echo "  Plugin: vendoreado ${PLUGIN_VENDOREADO} | disponible ${PLUGIN_DISPONIBLE}"
        fi
    fi
fi

# ── Último gate: .gate/last-run.json ──────────────────────────────────────
HEAD_ACTUAL=$(git rev-parse HEAD 2>/dev/null || echo "")
HEAD_CORTO=$(git rev-parse --short HEAD 2>/dev/null || echo "?")

if [ -f .gate/last-run.json ]; then
    LR_FECHA=$(php -r 'echo json_decode(file_get_contents(".gate/last-run.json"))->fecha ?? "?";')
    LR_COMMIT=$(php -r 'echo json_decode(file_get_contents(".gate/last-run.json"))->commit ?? "?";')
    LR_VEREDICTO=$(php -r 'echo json_decode(file_get_contents(".gate/last-run.json"))->veredicto ?? "?";')
    LR_COMMIT_CORTO=$(printf '%s' "$LR_COMMIT" | cut -c1-7)
    echo "  Ultimo gate: ${LR_FECHA} commit ${LR_COMMIT_CORTO} -> ${LR_VEREDICTO}"
    if [ -n "$HEAD_ACTUAL" ] && [ "$LR_COMMIT" != "$HEAD_ACTUAL" ]; then
        echo "               HEAD actual ${HEAD_CORTO}: la evidencia esta vieja"
    fi
else
    echo "  Ultimo gate: sin registro (corre /release-gate:run)"
fi

echo ""
printf "  %-12s %10s %12s   %s\n" "Herramienta" "Congelado" "En archivo" "Realidad"

APRETAR=""

# ── PHPStan (solo medida) ─────────────────────────────────────────────────
if [ "$PERFIL" = "medida" ]; then
    CONGELADO=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->phpstan->entradas_baseline ?? 0;')
    EN_ARCHIVO=0
    if [ -f phpstan-baseline.neon ]; then
        EN_ARCHIVO=$(grep -c 'message:' phpstan-baseline.neon || true)
    fi
    printf "  %-12s %10s %12s   %s\n" "PHPStan" "$CONGELADO" "$EN_ARCHIVO" "requiere analisis"
    if [ "$EN_ARCHIVO" -lt "$CONGELADO" ]; then
        APRETAR="${APRETAR}SE PUEDE APRETAR: PHPStan ${EN_ARCHIVO} < ${CONGELADO} congeladas -> /release-gate:ratchet\n"
    fi
fi

# ── Psalm taint (ambos perfiles) ──────────────────────────────────────────
CONGELADO=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->psalm->entradas_baseline ?? 0;')
EN_ARCHIVO=0
if [ -f psalm-taint-baseline.xml ]; then
    EN_ARCHIVO=$(grep -c '<code>' psalm-taint-baseline.xml || true)
fi
printf "  %-12s %10s %12s   %s\n" "Psalm taint" "$CONGELADO" "$EN_ARCHIVO" "requiere analisis"
if [ "$EN_ARCHIVO" -lt "$CONGELADO" ]; then
    APRETAR="${APRETAR}SE PUEDE APRETAR: Psalm taint ${EN_ARCHIVO} < ${CONGELADO} congeladas -> /release-gate:ratchet\n"
fi

# ── PHPMD (solo medida) ────────────────────────────────────────────────────
if [ "$PERFIL" = "medida" ]; then
    CONGELADO=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->phpmd->entradas_baseline ?? 0;')
    EN_ARCHIVO=0
    if [ -f phpmd.baseline.xml ]; then
        EN_ARCHIVO=$(grep -c '<violation' phpmd.baseline.xml || true)
    fi
    printf "  %-12s %10s %12s   %s\n" "PHPMD" "$CONGELADO" "$EN_ARCHIVO" "requiere analisis"
    if [ "$EN_ARCHIVO" -lt "$CONGELADO" ]; then
        APRETAR="${APRETAR}SE PUEDE APRETAR: PHPMD ${EN_ARCHIVO} < ${CONGELADO} congeladas -> /release-gate:ratchet\n"
    fi
fi

# ── Deptrac (solo medida) ──────────────────────────────────────────────────
if [ "$PERFIL" = "medida" ]; then
    CONGELADO=$(php -r 'echo json_decode(file_get_contents(".gate/baseline.json"))->deptrac->entradas_baseline ?? 0;')
    EN_ARCHIVO=0
    if [ -f deptrac.baseline.yaml ]; then
        EN_ARCHIVO=$(grep -c -- '- App' deptrac.baseline.yaml || true)
    fi
    printf "  %-12s %10s %12s   %s\n" "Deptrac" "$CONGELADO" "$EN_ARCHIVO" "requiere analisis"
    if [ "$EN_ARCHIVO" -lt "$CONGELADO" ]; then
        APRETAR="${APRETAR}SE PUEDE APRETAR: Deptrac ${EN_ARCHIVO} < ${CONGELADO} congeladas -> /release-gate:ratchet\n"
    fi
fi

# ── SE PUEDE APRETAR también por evidencia de la última corrida real ──────
# Además del conteo de archivo, last-run.json puede traer conteos (de la
# última corrida real de gate-run.sh) menores a los congelados: es la misma
# señal de mejora, vista desde la evidencia en vez del archivo de baseline.
if [ -f .gate/last-run.json ]; then
    for TOOL in phpstan psalm phpmd deptrac; do
        if [ "$PERFIL" != "medida" ] && [ "$TOOL" != "psalm" ]; then
            continue
        fi
        LR_CONTEO=$(php -r "
            \$lr = json_decode(file_get_contents('.gate/last-run.json'));
            \$c = \$lr->conteos->${TOOL} ?? null;
            echo \$c === null ? '' : \$c;
        ")
        if [ -z "$LR_CONTEO" ]; then
            continue
        fi
        CONGELADO=$(php -r "echo json_decode(file_get_contents('.gate/baseline.json'))->${TOOL}->entradas_baseline ?? 0;")
        if [ "$LR_CONTEO" -lt "$CONGELADO" ]; then
            case "$APRETAR" in
                *"SE PUEDE APRETAR: ${TOOL}"*) ;;
                *) APRETAR="${APRETAR}SE PUEDE APRETAR: ${TOOL} (ultima corrida) ${LR_CONTEO} < ${CONGELADO} congeladas -> /release-gate:ratchet\n" ;;
            esac
        fi
    done
fi

if [ -n "$APRETAR" ]; then
    echo ""
    printf "%b" "$APRETAR"
fi

echo ""
echo "  El baseline no se toca para pasar el gate. Solo se aprieta."

exit 0
