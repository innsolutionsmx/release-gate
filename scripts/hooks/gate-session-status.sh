#!/usr/bin/env bash
# Hook SessionStart — imprime el tablero de estado del gate como contexto de
# sesión, invocando scripts/gate-status.sh sin correr ningún análisis. El
# guard por ausencia de .gate/baseline.json vive en gate-status.sh (cero
# output); este hook solo garantiza exit 0 SIEMPRE, incluso si algo falla.
#
# Registrado en settings.json bajo SessionStart SIN matcher.
#
# Vendoreado por /release-gate:init y /release-gate:upgrade como
# .claude/hooks/gate-session-status.sh — NO editar a mano.
set -euo pipefail

PROYECTO="${CLAUDE_PROJECT_DIR:-$(pwd)}"

bash "${PROYECTO}/scripts/gate-status.sh" || true

exit 0
