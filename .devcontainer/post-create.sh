#!/bin/bash
# post-create.sh - Install tools and configure the development environment
# Runs via postCreateCommand (after container creation)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Fix ownership of named volumes up front. Docker named volumes mount as root,
# so the vscode user cannot write into them until they are chowned. Do this
# before any installer writes into these paths (e.g. the Claude Code installer
# creates ~/.claude/downloads).
sudo chown vscode:vscode /workspaces/coding-tool/node_modules /home/vscode/.claude

# Install beads (git hooks are orchestrated by lefthook — see lefthook.yml —
# which calls `bd hooks run <stage>`, so we do NOT run `bd hooks install`).
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash

# Install Claude Code
curl -fsSL https://claude.ai/install.sh | bash

# Project-specific tools
npm install
npx playwright install-deps chromium
npx playwright install chromium
"$SCRIPT_DIR/install-nsjail.sh"

# Install gitleaks (secret scanner used by the pre-commit hook). No Go toolchain
# in this container, so fetch the release binary. Best-effort: the pre-commit
# hook skips the secret scan gracefully if gitleaks is absent.
if ! command -v gitleaks >/dev/null 2>&1; then
    case "$(uname -m)" in
        x86_64|amd64) GL_ARCH=x64 ;;
        aarch64|arm64) GL_ARCH=arm64 ;;
        *) GL_ARCH="" ;;
    esac
    GL_VER=$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"v\K[^"]+' | head -1)
    if [ -n "$GL_ARCH" ] && [ -n "$GL_VER" ]; then
        curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_linux_${GL_ARCH}.tar.gz" \
            | sudo tar -xz -C /usr/local/bin gitleaks 2>/dev/null \
            && echo "Installed gitleaks ${GL_VER}" \
            || echo "gitleaks install failed — pre-commit secret scan will skip"
    else
        echo "Skipping gitleaks install (unsupported arch or version lookup failed) — secret scan will skip"
    fi
fi

# Install Supabase CLI. We install it here rather than via the
# devcontainers-extra/supabase-cli feature because that feature pins to
# `latest`, which now resolves to a beta release that ships both a versioned
# (supabase_<ver>_linux_<arch>.tar.gz) and an unversioned
# (supabase_linux_<arch>.tar.gz) tarball — nanolayer's asset resolver refuses
# to choose between the two ("Too many matches found") and the build fails.
# Pulling an explicit versioned URL from the latest *stable* release avoids the
# ambiguity entirely. The tarball ships TWO co-located binaries: `supabase`
# (a thin shim) and `supabase-go` (the CLI the shim forwards to); both must be
# installed side by side or the shim aborts with "Could not find supabase-go".
if ! command -v supabase >/dev/null 2>&1; then
    case "$(uname -m)" in
        x86_64|amd64) SB_ARCH=amd64 ;;
        aarch64|arm64) SB_ARCH=arm64 ;;
        *) SB_ARCH="" ;;
    esac
    SB_VER=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest 2>/dev/null \
        | grep -oP '"tag_name":\s*"v\K[^"]+' | head -1)
    if [ -n "$SB_ARCH" ] && [ -n "$SB_VER" ]; then
        SB_TMP=$(mktemp -d)
        if curl -fsSL "https://github.com/supabase/cli/releases/download/v${SB_VER}/supabase_${SB_VER}_linux_${SB_ARCH}.tar.gz" \
            | tar -xz -C "$SB_TMP"; then
            sudo install -m 0755 "$SB_TMP/supabase" /usr/local/bin/supabase
            # Newer releases also ship the supabase-go companion binary.
            [ -f "$SB_TMP/supabase-go" ] && sudo install -m 0755 "$SB_TMP/supabase-go" /usr/local/bin/supabase-go
            echo "Installed supabase ${SB_VER}"
        else
            echo "supabase install failed"
        fi
        rm -rf "$SB_TMP"
    else
        echo "Skipping supabase install (unsupported arch or version lookup failed)"
    fi
fi

# Install git hooks (lefthook orchestrates beads sync + quality gates).
npx lefthook install
