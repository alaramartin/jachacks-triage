#!/usr/bin/env sh
# Regenerate client/global.css from client/tailwind.src.css.
#
# Run this after adding or changing any Tailwind class in a .cl.jac file - the
# generated stylesheet only contains the utilities that were present in the
# sources at build time. See the header comment in tailwind.src.css for why we
# compile by hand instead of relying on jac.toml's vite plugin table.
#
# Needs the root devDependencies once: `npm install`.
# Add --watch to keep it running alongside `jac start --dev`.
set -e
cd "$(dirname "$0")/.."
./node_modules/.bin/tailwindcss -i client/tailwind.src.css -o client/global.css "$@"
