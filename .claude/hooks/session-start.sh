#!/bin/bash
# Claude Code cloud sessions: install the lint tools (selene, luau-lsp, Rojo) so scripts/lint.sh
# works straight away. Local sessions skip this; run scripts/install-lint-tools.sh yourself.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi
"$CLAUDE_PROJECT_DIR/scripts/install-lint-tools.sh"
