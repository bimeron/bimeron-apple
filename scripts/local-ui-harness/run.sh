#!/bin/zsh
set -eu
cd "${0:A:h}/../.."
REAL_HOME="$HOME"
FORBIDDEN="/private/tmp/bimeron-forbidden-$(uuidgen)"
ROOT=$(mktemp -d /tmp/bimeron-isolated-ui.XXXXXX)
ROOT=$(cd "$ROOT" && pwd -P)
mkdir -p "$ROOT/package/Sources" "$ROOT/evidence" "$ROOT/home" "$ROOT/tmp"
cp Package.swift "$ROOT/package/"
cp -R Sources/. "$ROOT/package/Sources/"
rm "$ROOT/package/Sources/BimeronApp/BimeronApp.swift"
/Users/wrk/.local/bin/git diff --exit-code HEAD -- Sources Package.swift
/Users/wrk/.local/bin/git rev-parse HEAD > "$ROOT/evidence/source-commit.txt"
python3 - "$PWD/Sources" "$ROOT/package/Sources" "$ROOT/evidence/source-hashes.txt" <<'PYHASH'
import hashlib,pathlib,sys
source,copy,out=map(pathlib.Path,sys.argv[1:])
rows=[]
for path in sorted(source.rglob('*')):
    if not path.is_file() or path.name == 'BimeronApp.swift': continue
    relative=path.relative_to(source)
    original=path.read_bytes()
    assert original == (copy/relative).read_bytes(), relative
    rows.append(f'{hashlib.sha256(original).hexdigest()}  {relative}')
assert not (copy/'BimeronApp/BimeronApp.swift').exists()
out.write_text('\n'.join(rows)+'\n')
PYHASH
cp scripts/local-ui-harness/run.sh "$ROOT/evidence/runner.sh"
cp scripts/local-ui-harness/Harness.swift "$ROOT/evidence/Harness.swift"
cp scripts/local-ui-harness/EditorInteractions.swift "$ROOT/evidence/"
cp scripts/local-ui-harness/{Harness,EditorInteractions}.swift "$ROOT/package/Sources/BimeronApp/"
# The temporary package has no test targets or dependency resolution.
python3 - "$ROOT/package/Package.swift" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read(); s='\n'.join(l for l in s.splitlines() if '.testTarget(' not in l)
open(p,'w').write(s+'\n')
PY
swift build --package-path "$ROOT/package" --scratch-path "$ROOT/build" --disable-automatic-resolution > "$ROOT/evidence/build.log" 2>&1
# Compile unchanged copied views without launching AppKit or requiring AX trust.
if [[ "${HARNESS_BUILD_ONLY:-0}" = 1 ]]; then
  printf 'Build-only evidence: %s/evidence\n' "$ROOT"
  exit 0
fi
cat > "$ROOT/mock-validate" <<'MOCK'
#!/bin/sh
[ "$1" = validate ] || exit 92
case "$2" in "$HARNESS_ROOT"/*) ;; *) exit 93 ;; esac
printf 'mock validate\n' >> "$HARNESS_ROOT/evidence/mock-calls.log"
if [ -e "$HARNESS_ROOT/reject" ]; then
 echo 'MOCK rejection: synthetic configuration rejected; no real Core was invoked.' >&2
 exit 1
fi
exit 0
MOCK
chmod 700 "$ROOT/mock-validate"
cat > "$ROOT/isolation.sb" <<EOF2
(version 1)
(allow default)
(deny network*)
(deny file-read* (subpath "$REAL_HOME/Library/Application Support/Bimeron") (subpath "$REAL_HOME/.ssh") (regex #"^$REAL_HOME/Library/Preferences/.*[Bb]imeron.*"))
(deny file-write*)
(allow file-write* (subpath "$ROOT") (literal "/dev/null"))
EOF2
# Fail closed: both outside writes and networking must be denied before UI launch.
if ! HARNESS_ROOT="$ROOT" HARNESS_FORBIDDEN="$FORBIDDEN" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" /bin/sh -c '
set -eu
touch "$HARNESS_ROOT/probe" || exit 81
[ -f "$HARNESS_ROOT/probe" ] || exit 82
if touch "$HARNESS_FORBIDDEN"; then exit 83; fi
# Socket creation must fail with EPERM, rather than merely a refused connection.
/usr/bin/python3 -c "import socket,errno; s=socket.socket(); r=s.connect_ex((\"127.0.0.1\",9)); print(\"socket result\",r); assert r == errno.EPERM"
' > "$ROOT/evidence/sandbox-preflight.log" 2>&1; then
  [[ ! -e "$FORBIDDEN" ]] || rm "$FORBIDDEN"
  cat "$ROOT/evidence/sandbox-preflight.log"
  exit 1
fi
[[ ! -e "$FORBIDDEN" ]] || { rm "$FORBIDDEN"; exit 1; }
if [[ "${HARNESS_MODE:-integrated}" != editor ]]; then
  printf '%s\n' "$ROOT" > docs/workstreams/integrated-ui-audit/latest-run.txt
fi
NSUnbufferedIO=YES HOME="$ROOT/home" TMPDIR="$ROOT/tmp/" HARNESS_ROOT="$ROOT" /usr/bin/sandbox-exec -f "$ROOT/isolation.sb" "$ROOT/build/debug/Bimeron" > "$ROOT/evidence/interactions.log" 2>&1
grep -q "^COMPLETE:" "$ROOT/evidence/interactions.log"
cat "$ROOT/evidence/interactions.log"
printf 'Evidence: %s/evidence\n' "$ROOT"
