#!/usr/bin/env bash
# Builds release binaries and packages them with the runtime assets into
# distributable zips: a native Linux build, and a Windows build cross-linked
# from Linux via mingw-w64.
#
# Usage: scripts/build_dist.sh [version] [linux|windows|all]
#   version  defaults to today's date (YYYYMMDD)
#   target   defaults to "all"
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(date +%Y%m%d)}"
TARGET="${2:-all}"
NAME="towerdef-first-impact"
DIST="dist"
CACHE=".build-cache"

# Must match the raylib_version string baked into whatever the vendored
# odin/vendor/raylib binaries were built from (checked by dumping the
# raylib_version symbol out of vendor/raylib/linux/libraylib.so.600 with
# objdump — see the Windows section below for how this was worked out).
# If Odin's vendored raylib ever moves to a newer tag, bump this and delete
# $CACHE/raylib-mingw to force a rebuild against the matching source.
RAYLIB_TAG="6.0"

build_linux() {
	local stage="$DIST/linux/$NAME"
	echo "==> [linux] Cleaning $stage"
	rm -rf "$stage"
	mkdir -p "$stage"

	echo "==> [linux] Compiling (release)"
	odin build . -out:"$stage/towerdef" -o:speed

	copy_assets "$stage"

	local zip_path="$DIST/${NAME}-linux-${VERSION}.zip"
	echo "==> [linux] Zipping"
	rm -f "$zip_path"
	( cd "$DIST/linux" && zip -rq "../../$zip_path" "$NAME" )
	echo "==> [linux] Done: $zip_path"
}

copy_assets() {
	local stage="$1"
	cp -r images fonts audio music assets maps models "$stage/"
	cp translations.txt campaign.bin README.md "$stage/"
	# savegame.bin / settings.bin deliberately NOT copied: those are
	# per-player state (progress, settings), not game content — a fresh
	# download should start clean, not with whoever built the zip's save.
}

# Ensures $CACHE/raylib-mingw/libraylib.a exists, built from raylib's own
# source with mingw-w64 at the tag in $RAYLIB_TAG. Cached because building
# raylib from source takes a couple minutes and the result doesn't change
# unless the raylib version does — no reason to redo it on every zip.
ensure_raylib_mingw() {
	local out="$CACHE/raylib-mingw"
	if [ -f "$out/libraylib.a" ] && [ "$(cat "$out/VERSION" 2>/dev/null || true)" = "$RAYLIB_TAG" ]; then
		echo "==> [windows] Using cached raylib $RAYLIB_TAG (mingw) at $out/libraylib.a"
		return
	fi

	echo "==> [windows] Building raylib $RAYLIB_TAG for mingw (not cached, one-time cost)"
	rm -rf "$out"
	mkdir -p "$CACHE"
	local src="$CACHE/raylib-src"
	rm -rf "$src"
	git clone --quiet --depth 1 --branch "$RAYLIB_TAG" https://github.com/raysan5/raylib.git "$src"
	make -C "$src/src" -j"$(nproc)" \
		PLATFORM=PLATFORM_DESKTOP OS=Windows_NT \
		CC=x86_64-w64-mingw32-gcc AR=x86_64-w64-mingw32-ar \
		RAYLIB_LIBTYPE=STATIC
	mkdir -p "$out"
	cp "$src/src/libraylib.a" "$out/libraylib.a"
	echo "$RAYLIB_TAG" > "$out/VERSION"
	rm -rf "$src"
}

build_windows() {
	if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
		echo "==> [windows] SKIPPED: x86_64-w64-mingw32-gcc not installed"
		echo "    (Debian/Ubuntu: apt install gcc-mingw-w64-x86-64)"
		return
	fi

	ensure_raylib_mingw

	local stage="$DIST/windows/$NAME"
	echo "==> [windows] Cleaning $stage"
	rm -rf "$stage"
	mkdir -p "$stage"

	# odin build itself refuses to cross-link for windows_amd64 from Linux
	# ("Linking for cross compilation for this platform is not yet
	# supported") — so this builds a plain object file and links it by hand
	# with mingw. -build-mode:obj skips codegen for an entry point wrapper,
	# so the object still expects a normal C main, which mingw's own CRT
	# startup (pulled in automatically by the gcc driver below) provides.
	echo "==> [windows] Compiling to object (release)"
	local obj="$CACHE/towerdef_win.obj"
	odin build . -target:windows_amd64 -build-mode:obj -out:"$obj" -o:speed

	# Odin's windows_amd64 codegen emits calls to MSVC's stack-probe
	# convention (__chkstk, two leading underscores) for large stack
	# frames. mingw only ships its own internal variant under a different
	# name (___chkstk_ms, three underscores, same x64 ABI: size in RAX,
	# doesn't touch RSP itself) — alias one to the other with a one-line
	# tail jump. Without this the link fails with "undefined reference to
	# __chkstk" the moment any function's locals cross a page (4KB).
	local chkstk_obj="$CACHE/chkstk_stub.o"
	cat > "$CACHE/chkstk_stub.c" <<-'EOF'
		extern void ___chkstk_ms(void);
		__asm__(
		    ".global __chkstk\n"
		    "__chkstk:\n"
		    "\tjmp ___chkstk_ms\n"
		);
	EOF
	x86_64-w64-mingw32-gcc -c "$CACHE/chkstk_stub.c" -o "$chkstk_obj"

	echo "==> [windows] Linking"
	# NOTE: this step used to fail entirely when linking against the
	# vendored, MSVC-built windows/raylib.lib — that lib references
	# MSVC/UCRT-only runtime internals (__security_cookie, __GSHandlerCheck,
	# __isa_available, raymath functions compiled as non-inlined externals)
	# that plain mingw has no equivalent for, and patching around all of
	# that individually isn't practical. Linking against our OWN raylib,
	# built from source with mingw itself (ensure_raylib_mingw above),
	# sidesteps the whole problem: it's a mingw-native static lib with
	# mingw-native symbol expectations throughout.
	x86_64-w64-mingw32-gcc "$obj" "$chkstk_obj" \
		-o "$stage/towerdef.exe" \
		-L"$CACHE/raylib-mingw" -lraylib \
		-lwinmm -lgdi32 -luser32 -lshell32 -lole32 -lbcrypt \
		-Wl,--allow-multiple-definition \
		2>&1 | grep -v "corrupt .drectve" || true

	if [ ! -f "$stage/towerdef.exe" ]; then
		echo "==> [windows] FAILED: no .exe produced, see linker output above"
		return 1
	fi

	copy_assets "$stage"

	local zip_path="$DIST/${NAME}-windows-${VERSION}.zip"
	echo "==> [windows] Zipping"
	rm -f "$zip_path"
	( cd "$DIST/windows" && zip -rq "../../$zip_path" "$NAME" )
	echo "==> [windows] Done: $zip_path"
	echo
	echo "    This .exe is cross-compiled and linked entirely on Linux. It's"
	echo "    been smoke-tested under Wine (opens the real GLFW/OpenGL window,"
	echo "    loads audio, compiles every shader in the project, no errors) —"
	echo "    see 'wine towerdef.exe' if you want to repeat that. Wine isn't"
	echo "    real Windows though, so still worth trying it on an actual"
	echo "    Windows machine before trusting it for a release."
}

case "$TARGET" in
	linux) build_linux ;;
	windows) build_windows ;;
	all) build_linux; build_windows ;;
	*) echo "Unknown target '$TARGET' (expected: linux, windows, all)"; exit 1 ;;
esac
