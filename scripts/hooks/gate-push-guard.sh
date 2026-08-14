#!/usr/bin/env bash
# Hook PreToolUse/Bash — corre en el hot path de TODO comando Bash de la
# sesión. Exige evidencia fresca (.gate/last-run.json) antes de dejar pasar
# un `git push` a `dev`/`main`. NUNCA corre el gate (timeout de hook de 60s
# vs. minutos de PHPStan); solo lee evidencia ya escrita por gate-run.sh.
#
# Descarte por regex ANTES de tocar disco (I/O solo si ya es un push).
# El bloqueo es SIEMPRE por JSON permissionDecision:deny — el exit code
# nunca bloquea nada, así que este script termina con exit 0 siempre.
#
# Registrado en settings.json bajo PreToolUse con matcher "Bash".
#
# Vendoreado por /release-gate:init y /release-gate:upgrade como
# .claude/hooks/gate-push-guard.sh — NO editar a mano.
set -euo pipefail

PROYECTO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROYECTO" 2>/dev/null || true

deny() {
    local motivo="$1"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$motivo"
    exit 0
}

# ── Paso 1: leer el payload de stdin, extraer tool_input.command con sed ──
# (igual que git-guard.sh extrae file_path: sin jq, para no sumar una
# dependencia al hot path de cada comando Bash).
PAYLOAD="$(cat 2>/dev/null || true)"
# -E (ERE): el sed de macOS (BSD) no soporta \| como alternación en BRE, GNU sí
# — con -E y | a secas el mismo patrón funciona igual en los dos.
CMD=$(printf '%s' "$PAYLOAD" | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p')

# ── Paso 2: descarte inmediato por regex, ANTES de cualquier I/O a disco ──
if ! printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
    exit 0
fi

# ── Paso 3: excepciones explícitas ─────────────────────────────────────────
if printf '%s' "$CMD" | grep -q -- '--dry-run'; then
    exit 0
fi

if printf '%s' "$CMD" | grep -q 'GATE_SKIP=1'; then
    # Override visible: queda escrito tal cual en el transcript de la sesión.
    exit 0
fi

# ── Paso 4: sin baseline, no hay nada que exigir ───────────────────────────
if [ ! -f .gate/baseline.json ]; then
    exit 0
fi

# ── Paso 5: resolver rama destino ──────────────────────────────────────────
# Refspec explícito del comando (git push <remote> <rama>) si está; si no,
# la rama actual del repo.
RESTO=$(printf '%s' "$CMD" | sed -E 's/.*push[[:space:]]*//')
REMOTE=""
RAMA=""
for TOK in $RESTO; do
    case "$TOK" in
        --*|-*)
            continue
            ;;
        '&&'|'||'|';'|'&'|'|')
            break
            ;;
        *)
            if [ -z "$REMOTE" ]; then
                REMOTE="$TOK"
            else
                RAMA="$TOK"
                break
            fi
            ;;
    esac
done

if [ -z "$RAMA" ]; then
    RAMA=$(git branch --show-current 2>/dev/null || echo "")
fi

if [ "$RAMA" != "main" ] && [ "$RAMA" != "dev" ]; then
    exit 0
fi

# ── Paso 6: evidencia fresca — .gate/last-run.json verde, del HEAD actual,
# con árbol limpio. Cualquier otra condición: deny con el motivo exacto. ────
if [ ! -f .gate/last-run.json ]; then
    deny "sin evidencia: corré /release-gate:run antes de pushear a ${RAMA}"
fi

VEREDICTO=$(php -r 'echo json_decode(file_get_contents(".gate/last-run.json"))->veredicto ?? "";' 2>/dev/null || echo "")
LR_COMMIT=$(php -r 'echo json_decode(file_get_contents(".gate/last-run.json"))->commit ?? "";' 2>/dev/null || echo "")
ARBOL_LIMPIO=$(php -r 'echo (json_decode(file_get_contents(".gate/last-run.json"))->arbol_limpio ?? false) ? "true" : "false";' 2>/dev/null || echo "false")
HEAD_ACTUAL=$(git rev-parse HEAD 2>/dev/null || echo "")

if [ "$VEREDICTO" != "APROBADO" ]; then
    deny "el último /release-gate:run quedó bloqueado: corré /release-gate:run antes de pushear a ${RAMA}"
fi

if [ -z "$HEAD_ACTUAL" ] || [ "$LR_COMMIT" != "$HEAD_ACTUAL" ]; then
    deny "la evidencia es de un commit viejo: corré /release-gate:run antes de pushear a ${RAMA}"
fi

if [ "$ARBOL_LIMPIO" != "true" ]; then
    deny "el árbol estaba sucio cuando se corrió el gate: corré /release-gate:run antes de pushear a ${RAMA}"
fi

exit 0
