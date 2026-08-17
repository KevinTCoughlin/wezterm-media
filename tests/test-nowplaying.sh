#!/bin/bash
set -euo pipefail

readonly ROOT="${1:-.}"
readonly WORK="$ROOT/tests/.nowplaying-test"
trap 'rm -rf "$WORK"' EXIT

rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/home"

cat >"$WORK/bin/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF

cat >"$WORK/bin/sw_vers" <<'EOF'
#!/bin/bash
echo "${TEST_MACOS_VERSION:?}"
EOF

cat >"$WORK/bin/xcrun" <<EOF
#!/bin/bash
set -euo pipefail
echo "\$1" >>"$WORK/xcrun.log"
if [[ "\$1" == "swift" ]]; then
    echo interpreted
    exit 0
fi
shift
output=""
while (( \$# )); do
    if [[ "\$1" == "-o" ]]; then
        output="\$2"
        break
    fi
    shift
done
cat >"\$output" <<'SCRIPT'
#!/bin/bash
echo compiled
SCRIPT
chmod +x "\$output"
EOF

chmod +x "$WORK/bin/"*

result="$(
  env -u XDG_CACHE_HOME TEST_MACOS_VERSION=26.0 HOME="$WORK/home" PATH="$WORK/bin:$PATH" \
    "$ROOT/helpers/nowplaying"
)"
[[ "$result" == "interpreted" ]]

: >"$WORK/xcrun.log"
result="$(
  env -u XDG_CACHE_HOME TEST_MACOS_VERSION=15.6 HOME="$WORK/home" PATH="$WORK/bin:$PATH" \
    "$ROOT/helpers/nowplaying"
)"
[[ "$result" == "compiled" ]]
grep -q '^swiftc$' "$WORK/xcrun.log"

: >"$WORK/xcrun.log"
result="$(
  env -u XDG_CACHE_HOME TEST_MACOS_VERSION=15.6 HOME="$WORK/home" PATH="$WORK/bin:$PATH" \
    "$ROOT/helpers/nowplaying"
)"
[[ "$result" == "compiled" ]]
[[ ! -s "$WORK/xcrun.log" ]]
