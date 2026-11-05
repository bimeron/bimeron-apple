#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
REAL_HOME="$HOME"
ROOT=$(mktemp -d /tmp/bimeron-ba15-ui.XXXXXX)
ROOT=$(cd "$ROOT" && pwd -P)
FORBIDDEN="${ROOT}-outside-probe"
mkdir -p "$ROOT/package/Sources" "$ROOT/evidence" "$ROOT/home" "$ROOT/tmp"
printf 'Evidence retained at %s/evidence\n' "$ROOT"
/Users/wrk/.local/bin/git diff --exit-code HEAD -- Sources Package.swift
[[ -z "$(/Users/wrk/.local/bin/git ls-files --others --exclude-standard -- Sources)" ]] || { printf 'FAIL: untracked production sources\n'; exit 1; }
/Users/wrk/.local/bin/git rev-parse HEAD > "$ROOT/evidence/source-commit.txt"
cp Package.swift "$ROOT/package/"
cp Package.swift "$ROOT/evidence/Package.original.swift"
cp -R Sources/. "$ROOT/package/Sources/"
rm "$ROOT/package/Sources/BimeronApp/BimeronApp.swift"
python3 - "$PWD" "$ROOT" <<'PY'
import hashlib, pathlib, sys
source, root = map(pathlib.Path, sys.argv[1:])
rows = []
for path in sorted((source/'Sources').rglob('*')):
    if not path.is_file(): continue
    relative = path.relative_to(source/'Sources')
    data = path.read_bytes()
    copied = root/'package/Sources'/relative
    if relative == pathlib.Path('BimeronApp/BimeronApp.swift'):
        assert not copied.exists()
        status = 'OMITTED entry point'
    else:
        assert data == copied.read_bytes(), relative
        status = 'MATCH'
    rows.append(f'{hashlib.sha256(data).hexdigest()}  {relative}  {status}')
assert (source/'Package.swift').read_bytes() == (root/'package/Package.swift').read_bytes()
(root/'evidence/source-hashes.txt').write_text('\n'.join(rows)+'\n')
p = root/'package/Package.swift'
lines = p.read_text().splitlines()
gate = '        .executableTarget(name: "SelectionFreezeGate", path: "Tests/Support/SelectionFreezeGate"),'
assert lines.count(gate) == 1, 'Review changed SelectionFreezeGate manifest declaration'
# This executable supports only the excluded app tests; do not copy or build it.
p.write_text('\n'.join(line for line in lines if '.testTarget(' not in line and line != gate)+'\n')
PY
cp "$ROOT/package/Package.swift" "$ROOT/evidence/Package.copied.swift"
cp scripts/ba15-ui-acceptance/{run.sh,Harness.swift} "$ROOT/evidence/"
cp scripts/ba15-ui-acceptance/Harness.swift "$ROOT/package/Sources/BimeronApp/"
shasum -a 256 "$ROOT/evidence/"{run.sh,Harness.swift,Package.original.swift,Package.copied.swift} > "$ROOT/evidence/harness-hashes.txt"
printf '%q ' swift build --package-path "$ROOT/package" --scratch-path "$ROOT/build" --disable-automatic-resolution > "$ROOT/evidence/commands.log"
printf '\n' >> "$ROOT/evidence/commands.log"
swift build --package-path "$ROOT/package" --scratch-path "$ROOT/build" --disable-automatic-resolution > "$ROOT/evidence/build.log" 2>&1
cat > "$ROOT/isolation.sb" <<EOF
(version 1)
(allow default)
(deny network*)
(deny file-read* (subpath "$REAL_HOME/Library/Application Support/Bimeron") (subpath "$REAL_HOME/.ssh") (regex #"^$REAL_HOME/Library/Preferences/.*[Bb]imeron.*"))
(deny file-write*)
(allow file-write* (subpath "$ROOT") (literal "/dev/null"))
EOF
cp "$ROOT/isolation.sb" "$ROOT/evidence/"
# No socket is created: policy retention is source evidence, not a network probe.
printf '%s\n' 'Network policy: deny network*. NOT dynamically probed.' > "$ROOT/evidence/isolation-review.txt"
cat > "$ROOT/evidence/preflight.sh" <<'PREFLIGHT'
set -eu
touch "$BA15_ROOT/probe"
[ -f "$BA15_ROOT/probe" ]
if touch "$BA15_FORBIDDEN"; then exit 83; fi
PREFLIGHT
printf '%q ' env BA15_ROOT="$ROOT" BA15_FORBIDDEN="$FORBIDDEN" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" /bin/sh "$ROOT/evidence/preflight.sh" >> "$ROOT/evidence/commands.log"
printf '\n' >> "$ROOT/evidence/commands.log"
if ! BA15_ROOT="$ROOT" BA15_FORBIDDEN="$FORBIDDEN" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" /bin/sh "$ROOT/evidence/preflight.sh" > "$ROOT/evidence/sandbox-preflight.log" 2>&1; then
  printf 'FAIL: filesystem isolation preflight; inspect %s/evidence\n' "$ROOT"
  exit 1
fi
[[ ! -e "$FORBIDDEN" ]] || { printf 'FAIL: outside probe exists: %s\n' "$FORBIDDEN"; exit 1; }
printf '%q ' env NSUnbufferedIO=YES HOME="$ROOT/home" TMPDIR="$ROOT/tmp/" BA15_ROOT="$ROOT" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" "$ROOT/build/debug/Bimeron" >> "$ROOT/evidence/commands.log"
printf '\n' >> "$ROOT/evidence/commands.log"
printf 'Evidence retained at %s/evidence\n' "$ROOT"
NSUnbufferedIO=YES HOME="$ROOT/home" TMPDIR="$ROOT/tmp/" BA15_ROOT="$ROOT" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" "$ROOT/build/debug/Bimeron" > "$ROOT/evidence/interactions.log" 2>&1
cat "$ROOT/evidence/interactions.log"
rg -q '^COMPLETE:' "$ROOT/evidence/interactions.log"
