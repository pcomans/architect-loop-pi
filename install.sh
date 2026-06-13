#!/usr/bin/env bash
set -euo pipefail

SRC_ROOT="$(cd "$(dirname "$0")" && pwd)/skills"
if [ "${1:-}" = "--project" ]; then
    DEST_ROOT="$(pwd)/.claude/skills"
else
    DEST_ROOT="$HOME/.claude/skills"
fi

mkdir -p "$DEST_ROOT"
for skill in "$SRC_ROOT"/*/; do
    name="$(basename "$skill")"
    rm -rf "${DEST_ROOT:?}/$name"
    cp -r "$skill" "$DEST_ROOT/$name"
    echo "Installed /$name to $DEST_ROOT/$name"
done

# Install the web_search tool (pi extension) globally so researchers can search.
EXT_SRC="$(cd "$(dirname "$0")" && pwd)/extensions/web-search"
EXT_DEST="$HOME/.pi/agent/extensions/web-search"
if [ -d "$EXT_SRC" ]; then
    mkdir -p "$(dirname "$EXT_DEST")"
    rm -rf "${EXT_DEST:?}"
    cp -r "$EXT_SRC" "$EXT_DEST"
    rm -rf "$EXT_DEST/node_modules"
    if command -v npm >/dev/null 2>&1; then
        ( cd "$EXT_DEST" && npm install --omit=dev --silent ) && \
            echo "Installed web_search extension to $EXT_DEST"
    else
        echo "web_search extension copied to $EXT_DEST - run 'npm install' there once npm is available"
    fi
fi

# Builder: pi pointed at a cheap model (DeepSeek by default).
if command -v pi >/dev/null 2>&1; then
    echo "pi found: $(pi --version)"
else
    echo "pi not found - install the builder: curl -fsSL https://pi.dev/install.sh | sh"
    echo "  (or: npm i -g --ignore-scripts @earendil-works/pi-coding-agent)"
fi
echo "Set your builder key:  export DEEPSEEK_API_KEY=sk-...   (see skills/architect/dispatch.md to switch models)"
echo "Optional better search: export TAVILY_API_KEY=tvly-...  (else web_search uses keyless DuckDuckGo)"
