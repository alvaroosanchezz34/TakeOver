#!/usr/bin/env bash
# Instala las herramientas del proyecto en ./.tools (Linux/macOS con Rust).
# Alternativa recomendada si ya usas Rokit:  rokit install   (ver rokit.toml)
#
# Resultado: .tools/bin/{rojo,lune,stylua,selene,luau-lsp} y
#            .tools/globalTypes.d.luau (tipos de la API de Roblox para luau-lsp)
set -euo pipefail
cd "$(dirname "$0")/.."

ROJO=7.7.1
LUNE=0.11.0
STYLUA=2.6.0
SELENE=0.31.0
LUAU_LSP=1.70.1

mkdir -p .tools/bin

need() { command -v "$1" >/dev/null 2>&1 || { echo "Falta '$1' en PATH" >&2; exit 1; }; }
need cargo
need curl
need unzip

install_crate() { # nombre versión [extra...]
	local name=$1 version=$2
	shift 2
	if [ -x ".tools/bin/$name" ]; then echo "• $name ya instalado"; return; fi
	echo "• compilando $name $version (puede tardar unos minutos)"
	cargo install "$name" --version "$version" --locked --root .tools "$@"
}

install_crate rojo "$ROJO"
install_crate lune "$LUNE"
install_crate stylua "$STYLUA" --features luau
install_crate selene "$SELENE"

if [ ! -x .tools/bin/luau-lsp ]; then
	echo "• descargando luau-lsp $LUAU_LSP"
	case "$(uname -s)-$(uname -m)" in
		Linux-x86_64) asset=luau-lsp-linux-x86_64.zip ;;
		Darwin-arm64 | Darwin-x86_64) asset=luau-lsp-macos.zip ;;
		*) echo "Plataforma no soportada por este script; instala luau-lsp manualmente" >&2; exit 1 ;;
	esac
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/lsp.zip" "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP/$asset"
	unzip -o -q "$tmp/lsp.zip" -d "$tmp/out"
	install -m 0755 "$tmp/out/luau-lsp" .tools/bin/luau-lsp
	rm -rf "$tmp"
fi

if [ ! -f .tools/globalTypes.d.luau ]; then
	echo "• descargando tipos de la API de Roblox"
	curl -fsSL -o .tools/globalTypes.d.luau \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "Listo. Usa:  export PATH=\"\$PWD/.tools/bin:\$PATH\"  y luego  tools/check.sh"
