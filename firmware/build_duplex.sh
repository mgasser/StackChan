#!/usr/bin/env bash
# Build the full-duplex test firmware for ONE StackChan (see DUPLEX.md).
#
#   . "$IDF_PATH/export.sh"          # ESP-IDF v5.5.4
#   ./build_duplex.sh                # build → dist/duplex-<version>/
#   ./build_duplex.sh --flash PORT   # build, then flash over USB (keeps Wi-Fi and NVS)
#   ./build_duplex.sh --fresh        # rebuild the sdkconfig from the defaults files
#
# Environment (optional):
#   STACKCHAN_OTA_URL     baked in as CONFIG_OTA_URL, the fallback when the robot's NVS
#                         has no ota_url, e.g. https://gateway.playkind.studio/xiaozhi/<secret>/ota/
#   STACKCHAN_FW_VERSION  defaults to <base>.<yymmdd>.<hhmm> (UTC), e.g. 1.6.0.261026.2215:
#                         every build is newer than the last, so the gateway can offer it
#
# The normal build (idf.py build) is not touched: this one lives in build-duplex/ with
# its own sdkconfig, from sdkconfig.defaults + sdkconfig.defaults.duplex.
set -euo pipefail
cd "$(dirname "$0")"

port=""
fresh=0
while [ $# -gt 0 ]; do
  case "$1" in
    --flash) port="${2:?--flash needs the serial port, e.g. /dev/cu.usbmodem1101}"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if ! command -v idf.py >/dev/null 2>&1; then
  echo "ESP-IDF is not active. Run: . \"\$IDF_PATH/export.sh\" (ESP-IDF v5.5.4)" >&2
  exit 1
fi

# Dependencies (xiaozhi-esp32 + components), with the Playkind patch applied.
if [ ! -d xiaozhi-esp32 ]; then
  python3 fetch_repos.py
fi
marker='"device_aec"'
if ! grep -q "$marker" xiaozhi-esp32/main/protocols/websocket_protocol.cc; then
  # fetch_repos.py skips a patch that does not apply (e.g. an older one is already in).
  echo "==> xiaozhi-esp32 lacks the current patch: re-applying patches/xiaozhi-esp32.patch"
  git -C xiaozhi-esp32 checkout -q -- .
  git -C xiaozhi-esp32 apply ../patches/xiaozhi-esp32.patch
  grep -q "$marker" xiaozhi-esp32/main/protocols/websocket_protocol.cc
fi

base="$(sed -n 's/^set(PROJECT_VER "\([0-9.]*\)")/\1/p' CMakeLists.txt | head -1)"
export STACKCHAN_FW_VERSION="${STACKCHAN_FW_VERSION:-${base}.$(date -u +%y%m%d).$(date -u +%H%M)}"
export STACKCHAN_VARIANT=duplex

build="build-duplex"
mkdir -p "$build"
extra="$PWD/$build/sdkconfig.defaults.generated"
: > "$extra"
if [ -n "${STACKCHAN_OTA_URL:-}" ]; then
  echo "CONFIG_OTA_URL=\"${STACKCHAN_OTA_URL}\"" >> "$extra"
fi
export STACKCHAN_EXTRA_DEFAULTS="$extra"

# sdkconfig defaults only apply to a new sdkconfig: start over when they changed.
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
local_defaults=/dev/null
[ -f sdkconfig.defaults.local ] && local_defaults=sdkconfig.defaults.local
stamp="$build/.defaults.sha256"
want="$(cat sdkconfig.defaults sdkconfig.defaults.duplex "$extra" "$local_defaults" | sha256 | cut -d' ' -f1)"
if [ "$fresh" = 1 ] || [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$want" ]; then
  rm -f "$build/sdkconfig"
fi

echo "==> Building the full-duplex firmware ${STACKCHAN_FW_VERSION}"
# reconfigure: the version comes from the environment, CMake must read it again.
idf.py -B "$build" -D SDKCONFIG="$PWD/$build/sdkconfig" reconfigure build
echo "$want" > "$stamp"

for opt in CONFIG_USE_DEVICE_AEC CONFIG_STACKCHAN_AEC_MAX_VOLUME; do
  grep -q "^${opt}=" "$build/sdkconfig" || { echo "the build lost ${opt}; check sdkconfig.defaults.duplex" >&2; exit 1; }
done

dist="dist/duplex-${STACKCHAN_FW_VERSION}"
rm -rf "$dist"
mkdir -p "$dist"
cp "$build/flash_args" "$dist/"
# Every file flash_args names, at the same relative path (bootloader, partition table,
# otadata, app, assets). It writes no NVS: Wi-Fi, OTA URL and calibration stay.
grep -oE '[^ ]+\.bin' "$build/flash_args" | while read -r file; do
  mkdir -p "$dist/$(dirname "$file")"
  cp "$build/$file" "$dist/$file"
done
cp "$build/sdkconfig" "$dist/sdkconfig"
app="$dist/stack-chan.bin"
size="$(wc -c < "$app" | tr -d ' ')"

cat <<DONE

Built ${STACKCHAN_FW_VERSION} → ${dist}/  (app image ${size} bytes)

First install, over USB (writes the app and its assets; Wi-Fi and NVS stay):
  cd ${dist} && python -m esptool --chip esp32s3 -p <PORT> -b 460800 write_flash @flash_args

Later updates, over the air from the gateway (app only):
  Studio → Admin → Creatures → <robot> → Device → "Listening & firmware" → upload ${app}
  or: curl -X PUT --data-binary @${app} -H "Content-Type: application/octet-stream" \\
        -H "Authorization: Bearer <admin token>" https://<gateway>/stackchan/<mac>/firmware
DONE

if [ -n "$port" ]; then
  echo "==> Flashing over $port"
  idf.py -B "$build" -D SDKCONFIG="$PWD/$build/sdkconfig" -p "$port" flash
fi
