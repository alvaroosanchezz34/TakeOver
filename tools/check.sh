#!/usr/bin/env bash
# Comprobación completa: formato, tipos (con la API de Roblox), tests y build Rojo.
# Uso: tools/check.sh [--fix]
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/.tools/bin:$PATH"

fix=0
[ "${1:-}" = "--fix" ] && fix=1
status=0
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
run() { "$@" || status=1; }

step "StyLua (formato)"
if [ $fix -eq 1 ]; then run stylua src tests; else run stylua --check src tests; fi

step "Rojo (sourcemap + build del lugar)"
run rojo sourcemap default.project.json --output sourcemap.json
mkdir -p build
run rojo build default.project.json --output build/TakeOver.rbxl

step "luau-lsp analyze (tipos y lint, con definiciones de Roblox)"
run luau-lsp analyze --definitions=.tools/globalTypes.d.luau --sourcemap=sourcemap.json src 2>&1 \
	| grep -v '^\[INFO\]\|^\[WARN\] client does not allow' || true
# luau-lsp devuelve 1 si hay errores de tipos: lo comprobamos aparte, de forma fiable.
if luau-lsp analyze --definitions=.tools/globalTypes.d.luau --sourcemap=sourcemap.json src >/dev/null 2>&1; then
	:
else
	status=1
fi

step "Tests (Lune)"
run lune run tests/run

echo
if [ $status -eq 0 ]; then echo "✔ todo correcto"; else echo "✘ hay fallos"; fi
exit $status
