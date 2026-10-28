#!/usr/bin/env bash
# Build hyprframes, install libhyprframes.so, and arm it for the next Hyprland login.
# ./build.sh --disable removes the installed plugin and its hyprland.conf line.
# Does not hyprctl plugin load or reload.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SO_NAME="libhyprframes.so"
BUILT="$ROOT/build/libhyprframes.so"
USER_DEST="${HOME}/.local/lib/hyprland/plugins/${SO_NAME}"
SYS_DEST="/usr/local/lib/hyprland/plugins/${SO_NAME}"
PNG_SHARE="${HOME}/.local/share/hyprframes"
SETTINGS="${HOME}/.config/hypr/hyprframes.conf"
CONF="${HOME}/.config/hypr/hyprland.conf"

disable_plugin() {
	rm -f "$USER_DEST"
	rm -f "$SYS_DEST" 2>/dev/null || sudo rm -f "$SYS_DEST" 2>/dev/null || true
	if [[ -f "$CONF" ]]; then
		python3 - "$CONF" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text()
t2 = re.sub(r"(?m)^# hyprframes at compositor start.*\n", "", t)
t2 = re.sub(r"(?m)^# Settings: ~/.config/hypr/hyprframes.conf\n", "", t2)
t2 = re.sub(r"(?m)^# Do not hyprctl plugin load / reload after hyprbars is up\.\n", "", t2)
t2 = re.sub(r"(?m)^[ \t]*plugin = .*/libhyprframes\.so[ \t]*\n", "", t2)
t2 = re.sub(r"\n    hyprframes \{.*?\n    \}\n", "\n", t2, count=1, flags=re.S)
if t2 != t:
    p.write_text(t2)
    print(f"cleaned {p}")
PY
	fi
	echo "hyprframes disabled — next Hyprland start will not load it"
}

if [[ "${1:-}" == "--disable" ]]; then
	disable_plugin
	exit 0
fi

echo "==> build hyprframes"
cmake -S "$ROOT" -B "$ROOT/build"
cmake --build "$ROOT/build" -j"$(nproc)"
[[ -f "$BUILT" ]] || { echo "build.sh: missing $BUILT" >&2; exit 1; }
echo "built $BUILT"

echo "==> install $SO_NAME"
mkdir -p "$(dirname "$USER_DEST")" "$PNG_SHARE" "$(dirname "$SETTINGS")"
cp -f "$BUILT" "$USER_DEST"
cp -f "$ROOT/example.png" "$PNG_SHARE/example.png"
if [[ ! -f "$SETTINGS" && -f "$ROOT/hyprframes.conf.example" ]]; then
	sed -E "s|^[[:space:]]*image[[:space:]]*=.*|image = ${PNG_SHARE}/example.png|" \
		"$ROOT/hyprframes.conf.example" >"$SETTINGS"
fi
PLUGIN_LINE="plugin = ${USER_DEST}"
echo "installed $USER_DEST"
if mkdir -p "$(dirname "$SYS_DEST")" 2>/dev/null && cp -f "$BUILT" "$SYS_DEST" 2>/dev/null; then
	PLUGIN_LINE="plugin = ${SYS_DEST}"
	echo "installed $SYS_DEST"
elif command -v sudo >/dev/null 2>&1 && sudo mkdir -p "$(dirname "$SYS_DEST")" && sudo cp -f "$BUILT" "$SYS_DEST"; then
	PLUGIN_LINE="plugin = ${SYS_DEST}"
	echo "installed $SYS_DEST"
fi

echo "==> enable for the next Hyprland session"
if [[ ! -f "$CONF" ]]; then
	echo "no $CONF — plugin is installed; add: $PLUGIN_LINE"
	exit 0
fi
python3 - "$CONF" "$PLUGIN_LINE" <<'PY'
from pathlib import Path
import re
import sys

conf, line = Path(sys.argv[1]), sys.argv[2]
text = conf.read_text()
text2, n = re.subn(
    r"(?m)^[ \t]*plugin = .*/libhyprframes\.so[ \t]*$",
    line,
    text,
    count=1,
)
if n:
    conf.write_text(text2)
    print(f"refreshed plugin= in {conf}")
    raise SystemExit(0)
block = (
    "# hyprframes at compositor start (before titlebar plugins).\n"
    "# Settings: ~/.config/hypr/hyprframes.conf\n"
    "# Do not hyprctl plugin load / reload after hyprbars is up.\n"
    f"{line}\n"
)
m = re.search(r"(?m)^[ \t]*plugin = .*/libhyprbars\.so[ \t]*$", text)
if not m:
    m = re.search(r"(?m)^exec-once = .*hyprbars", text)
if m:
    text = text[: m.start()] + block + text[m.start() :]
else:
    text = text.rstrip() + "\n\n" + block
conf.write_text(text)
print(f"updated {conf}")
PY
echo "armed $PLUGIN_LINE"
echo "Log out and start a new Hyprland session. Do not hyprctl plugin load / reload."
echo "If that login fails, run: $ROOT/build.sh --disable"
