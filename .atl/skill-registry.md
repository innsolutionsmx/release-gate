# Skill Registry — release-gate

Generado por `sdd-init`. Escaneo de skills user-level (`~/.claude/skills/`) y
project-level (`.claude/skills/`, etc.) en `release-gate`. Ninguna skill
project-level ni archivo de convenciones (`AGENTS.md`/`CLAUDE.md` de proyecto)
encontrado en el repo.

## Skills disponibles (user-level)

| Skill | Trigger |
|---|---|
| branch-pr | Crear un PR, abrir un pull request, preparar cambios para review. |
| design-forge-mejora | Registrar una mejora/gotcha/limitación/idea sobre el plugin design-forge. |
| go-testing | Escribir tests en Go, usar teatest, agregar cobertura de tests (Bubbletea TUI). |
| issue-creation | Crear un issue de GitHub, reportar un bug, pedir una feature. |
| judgment-day | Review adversarial en paralelo con dos jueces ciegos independientes. |
| product-ad-composer | Generar imágenes publicitarias de un producto real manteniendo el packaging 1:1. |
| skill-creator | Crear una nueva skill de agente IA, documentar patrones para IA. |

Nota: no se listan las skills `sdd-*`, `_shared` ni `skill-registry` (excluidas
por convención de la fase sdd-init).

## Convenciones de proyecto

Ninguna encontrada (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `GEMINI.md`,
`copilot-instructions.md`) a nivel de proyecto en release-gate. El usuario sí
tiene `~/.claude/CLAUDE.md` global (reglas de commits, herramientas
bat/rg/fd/sd/eza, verificación antes de afirmar, etc.) — aplica a toda sesión
pero no es específico de este repo.
