# Embedded in Installer scripts; tests source these pure filesystem checks only.
fail() { echo "Local DEV install refused: $*" >&2; exit 1; }
deny_only_acl() {
    # Allow ACLs need principal/rights analysis; accept only deny-only ACLs here.
    acl=$(LC_ALL=C /bin/ls -lde "$1") || fail "cannot inspect ACL $1"
    printf '%s\n' "$acl" | /usr/bin/awk '
        NR == 1 { next }
        / allow / { exit 1 }
        /^[ \t]*[0-9]+: / && / deny / { next }
        { exit 1 }
    ' || fail "unsupported allow ACL $1"
}
protected_directory() {
    [ ! -L "$1" ] && [ -d "$1" ] || fail "unsafe directory $1"
    [ "$(/usr/bin/stat -f %u:%g "$1")" = 0:0 ] || fail "directory ownership $1"
    deny_only_acl "$1"
    mode=$(/usr/bin/stat -f %Lp "$1")
    [ $((0$mode & 0022)) -eq 0 ] || fail "writable directory $1"
}
check_ancestry() {
    for directory in / /Library /Library/PrivilegedHelperTools /Library/LaunchDaemons; do
        if [ "${2:-installed}" = fresh ] && [ "$directory" != / ] && [ "$directory" != /Library ] && [ ! -e "$1$directory" ] && [ ! -L "$1$directory" ]; then
            continue
        fi
        protected_directory "$1$directory"
    done
}
check_absent() {
    for relative in /Library/PrivilegedHelperTools/org.bimeron.core /Library/PrivilegedHelperTools/org.bimeron.core.dev.json /Library/LaunchDaemons/org.bimeron.core.plist; do
        [ ! -e "$1$relative" ] && [ ! -L "$1$relative" ] || fail "existing payload; updates, repair and removal unsupported"
    done
}
check_file() {
    [ ! -L "$1" ] && [ -f "$1" ] || fail "unsafe file $1"
    [ "$(/usr/bin/stat -f %u:%g:%Lp "$1")" = "0:0:$2" ] || fail "file permissions $1"
    deny_only_acl "$1"
    [ "$(/usr/bin/shasum -a 256 "$1" | /usr/bin/cut -d ' ' -f 1)" = "$3" ] || fail "file digest $1"
}
