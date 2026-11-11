#!/bin/zsh -f

# Exercise pam-duo-macos-updater's decisions and failure paths with faked
# commands.
#
# - Runs copies whose root-owned paths point into a sandbox, so nothing real
#   changes, and the live module is only read.
#
# - Builds a stand-in module from test/fixtures/module, so it runs without a
#   module installed, as on CI. Where one is installed, it also checks that the
#   real module passes verify_module, which only runs locally.
#
# - Can't prove anything that takes real root or real Duo: the playbook's real
#   install and rollback test is still needed after any change.
#
# Usage: zsh -f test/pam-duo-macos-updater.test.zsh
#
# scripts/test.zsh runs it with the other test files.

# A fresh sandbox for each run, so two runs at once can't clear each other's.
SANDBOX=$(mktemp -d "${${TMPDIR:-/tmp}%/}/pam-duo-macos-updater-test.XXXXXX") || exit 1
trap 'rm -rf -- "$SANDBOX"' EXIT
SOURCE=${0:A:h:h}/bin/pam-duo-macos-updater
HELPER_FILE=${0:A:h:h}/libexec/pam-duo-macos-updater-root
FIXTURE_MODULE=$SANDBOX/fixture-module.so
FIXTURE_SOURCE=${0:A:h}/fixtures/module/pam_duo_fixture.c
INSTALLED_MODULE=/usr/local/lib/pam/pam_duo.so
pass=0
failures=0

# Print the time N days ago in the format GitHub uses.
days_ago() { date -u -v "-${1}d" +%FT%TZ; }

# Write the fake releases: one "tag date draft prerelease" per line.
releases_json() {
  local line first=1
  print -n '['
  for line in "$@"; do
    local -a f=(${=line})
    ((first)) || print -n ','
    first=0
    print -n "{\"tag_name\":\"$f[1]\",\"published_at\":\"$f[2]\",\"draft\":${f[3]:-false},\"prerelease\":${f[4]:-false}}"
  done
  print ']'
}

# Reset the sandbox, with the module present and Duo configured.
reset() {
  rm -rf "$SANDBOX/home" "$SANDBOX/fake"
  mkdir -p "$SANDBOX/home/.config/pam-duo-macos-updater" "$SANDBOX/home/.local/bin" \
    "$SANDBOX/fake/lib" "$SANDBOX/fake/run" "$SANDBOX/fake/etc"
  print test-topic > "$SANDBOX/home/.config/pam-duo-macos-updater/ntfy-topic"
  cp "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"
  print 'failmode = secure' > "$SANDBOX/fake/etc/pam_duo.conf"
  print "auth sufficient $SANDBOX/fake/lib/pam_duo.so" > "$SANDBOX/fake/etc/sudo_local"
  cp -p "$SANDBOX/pam-duo-macos-updater-root" "$SANDBOX/libexec/pam-duo-macos-updater-root"
  : > "$SANDBOX/ntfy.log"
  print 0 > "$SANDBOX/curl-fail-api"
  print 0 > "$SANDBOX/curl-fail-ntfy"
  print 0 > "$SANDBOX/sudo-deny"
  setopt local_options null_glob
  rm -f $SANDBOX/fake/run/*
  OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)")
  DUO_JSON=$(releases_json "duo_unix-2.3.0 $(days_ago 85)")
  write_data
}

write_data() {
  print -r -- "$OPENSSL_JSON" > "$SANDBOX/openssl.json"
  print -r -- "$DUO_JSON" > "$SANDBOX/duo.json"
}

# Say whether a condition held.
expect() {
  local name=$1
  shift
  if "$@"; then
    ((pass += 1))
    print -r -- "ok    $name"
  else
    ((failures += 1))
    print -r -- "FAIL  $name"
    print -r -- "      output: ${output:0:400}"
    print -r -- "      status: $code; ntfy: $(< "$SANDBOX/ntfy.log")"
  fi
}

# Run the copy with faked commands first on PATH.
run() {
  output=$(env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" \
    SANDBOX="$SANDBOX" /bin/zsh -f "$SANDBOX/pam-duo-macos-updater" "$@" 2>&1 < /dev/null)
  code=$?
}

has() { [[ $output == *"$1"* ]]; }
lacks() { [[ $output != *"$1"* ]]; }
status_is() { ((code == $1)); }
ntfy_count() { (($(grep -c . "$SANDBOX/ntfy.log") == $1)); }
ntfy_has() { grep -qF -- "$1" "$SANDBOX/ntfy.log"; }

# Build the sandbox copy and the faked commands.
setup() {
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/shims"
  mkdir -p "$SANDBOX/libexec"
  if ! cc -bundle -o "$FIXTURE_MODULE" "$FIXTURE_SOURCE"; then
    print -r -- "couldn't build the stand-in module" >&2
    exit 1
  fi
  sed -E \
    -e "s#^readonly MODULE_PATH=.*#readonly MODULE_PATH=$SANDBOX/fake/lib/pam_duo.so#" \
    -e "s#^readonly CONFIRMED_FLAG=.*#readonly CONFIRMED_FLAG=$SANDBOX/fake/run/confirmed#" \
    -e "s#^readonly SWAPPED_FLAG=.*#readonly SWAPPED_FLAG=$SANDBOX/fake/run/swapped#" \
    -e "s#^readonly HELPER_PATH=.*#readonly HELPER_PATH=$SANDBOX/libexec/pam-duo-macos-updater-root#" \
    -e "s#^readonly HELPER_SOURCE=.*#readonly HELPER_SOURCE=$SANDBOX/pam-duo-macos-updater-root#" \
    -e 's#^path=.*#path=($path /usr/bin /bin /usr/sbin /sbin)#' \
    -e "s#!= root:755#!= \$(id -un):755#" \
    -e 's#\[\[ ! -t 0 \]\]#[[ -n ${FORCE_NO_TTY:-} ]]#' \
    "$SOURCE" > "$SANDBOX/pam-duo-macos-updater"
  sed -E \
    -e "s#^readonly MODULE_PATH=.*#readonly MODULE_PATH=$SANDBOX/fake/lib/pam_duo.so#" \
    -e "s#^readonly CONFIRMED_FLAG=.*#readonly CONFIRMED_FLAG=$SANDBOX/fake/run/confirmed#" \
    -e "s#^readonly SWAPPED_FLAG=.*#readonly SWAPPED_FLAG=$SANDBOX/fake/run/swapped#" \
    -e "s#^readonly DUO_CONFIG=.*#readonly DUO_CONFIG=$SANDBOX/fake/etc/pam_duo.conf#" \
    -e "s#^readonly PAM_CONFIG=.*#readonly PAM_CONFIG=$SANDBOX/fake/etc/sudo_local#" \
    -e "s#^readonly LOCK_FILE=.*#readonly LOCK_FILE=$SANDBOX/fake/run/lock#" \
    -e "s#^readonly CONFIRM_TIMEOUT_SECONDS=.*#readonly CONFIRM_TIMEOUT_SECONDS=3#" \
    -e 's#\(\(EUID != 0\)\)#false#' \
    -e "s#!= root:wheel:600#!= \$(id -un):\$(id -gn):600#" \
    -e 's#install -o root -g wheel -m 755#install -m 755#' \
    "$HELPER_FILE" > "$SANDBOX/pam-duo-macos-updater-root"
  chmod +x "$SANDBOX/pam-duo-macos-updater-root"
  chmod 755 "$SANDBOX/libexec"
  cp -p "$SANDBOX/pam-duo-macos-updater-root" "$SANDBOX/libexec/pam-duo-macos-updater-root"

  cat > "$SANDBOX/shims/curl" << 'EOF'
#!/bin/zsh -f
args=("$@")
url=${args[-1]}
case $url in
  https://ntfy.sh/*)
    (($(< $SANDBOX/curl-fail-ntfy))) && exit 22
    for ((i = 1; i <= $#args; i++)); do
      [[ ${args[i]} == -d ]] && print -r -- "${args[i+1]}" >> $SANDBOX/ntfy.log
    done
    ;;
  *api.github.com/repos/openssl/openssl/releases/tags/*)
    (($(< $SANDBOX/curl-fail-api))) && exit 22
    cat $SANDBOX/openssl-tag.json
    ;;
  *api.github.com/repos/openssl/openssl/releases*)
    (($(< $SANDBOX/curl-fail-api))) && exit 22
    cat $SANDBOX/openssl.json
    ;;
  *api.github.com/repos/duosecurity/*)
    (($(< $SANDBOX/curl-fail-api))) && exit 22
    cat $SANDBOX/duo.json
    ;;
  *duo.com/docs/checksums)
    cat $SANDBOX/duo-page.html
    ;;
  *)
    for ((i = 1; i <= $#args; i++)); do
      [[ ${args[i]} == -o ]] && cp $SANDBOX/fake-tarball "${args[i+1]}"
    done
    ;;
esac
exit 0
EOF

  cat > "$SANDBOX/shims/brew" << 'EOF'
#!/bin/zsh -f
cat $SANDBOX/brew.json
EOF

  cat > "$SANDBOX/shims/launchctl" << 'EOF'
#!/bin/zsh -f
[[ -e $SANDBOX/agent-missing ]] && exit 113
[[ $1 == print ]] && print "\tstate = waiting"
exit 0
EOF

  # A faked sudo: -v and touch honor the deny switch; others run the command.
  cat > "$SANDBOX/shims/sudo" << 'EOF'
#!/bin/zsh -f
while [[ ${1:-} == -* ]]; do
  case $1 in
    -k) exit 0 ;;
    -v) exit 0 ;;
    -n | -A) shift ;;
    *) shift ;;
  esac
done
[[ ${1:-} == /usr/bin/touch ]] && (($(< $SANDBOX/sudo-deny))) && exit 1
exec "$@"
EOF
  chmod +x "$SANDBOX/shims/"*
  print 'fake tarball' > "$SANDBOX/fake-tarball"
  print "$(shasum -a 256 "$SANDBOX/fake-tarball" | cut -d ' ' -f 1)" > "$SANDBOX/fake-sum"
  print '{"formulae":[{"versions":{"stable":"9.9.9"},"urls":{"stable":{"checksum":"none"}}}]}' > "$SANDBOX/brew.json"
  print "<code>$(< $SANDBOX/fake-sum) duo_unix-2.3.0.tar.gz</code>" > "$SANDBOX/duo-page.html"
  print "{\"assets\":[{\"name\":\"openssl-3.5.9.tar.gz\",\"digest\":\"sha256:$(< $SANDBOX/fake-sum)\"}]}" > "$SANDBOX/openssl-tag.json"
}

setup

print -- '--- moratorium decisions'
reset
run check
expect 'up to date: succeeds' status_is 0
expect 'up to date: no alert' ntfy_count 0
expect 'up to date: records success' test -r "$SANDBOX/home/.local/state/pam-duo-macos-updater/last-check-success"

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 3)")
write_data
run check
expect '3-day-old release: no alert' ntfy_count 0
expect '3-day-old release: reported as held' has 'held by the 7-day moratorium'

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 6)")
write_data
run check
expect '6-day-old release: still held' ntfy_count 0

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 8)")
write_data
run check
expect '8-day-old release: alerts' ntfy_has 'OpenSSL 3.5.9 -> 3.5.10'
expect '8-day-old release: 3.5.10 sorts above 3.5.9' lacks 'held by'
run check
expect 'second run: does not repeat the alert' ntfy_count 1

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 9)" "openssl-3.5.11 $(days_ago 2)")
write_data
run check
expect 'older fix still installs while newer is held' ntfy_has '3.5.9 -> 3.5.10'
expect 'newer one reported as held' has 'OpenSSL 3.5.11 is held'

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-4.1.0 $(days_ago 30)" "openssl-3.6.5 $(days_ago 30)" "openssl-3.5.99 $(days_ago 30) true false" "openssl-3.5.98 $(days_ago 30) false true" "openssl-3.5.97-beta1 $(days_ago 30)")
write_data
run check
expect 'other series, drafts, prereleases ignored' ntfy_count 0

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.8 $(days_ago 80)" "openssl-3.5.9 $(days_ago 1)")
write_data
run check
expect 'never goes backward, even if installed is new' ntfy_count 0

reset
DUO_JSON=$(releases_json "duo_unix-2.3.0 $(days_ago 85)" "duo_unix-2.3.1 $(days_ago 20)")
write_data
run check
expect 'duo update alerts too' ntfy_has 'duo_unix 2.3.0 -> 2.3.1'

reset
OPENSSL_JSON=$(releases_json "openssl-3.5.8 $(days_ago 80)" "openssl-3.5.10 $(days_ago 20)")
write_data
run check
expect 'pulled release alerts' ntfy_has 'no longer listed'

print -- '--- failures are never silent'
reset
print 1 > "$SANDBOX/curl-fail-api"
run check
expect 'github down: exits non-zero' status_is 1
expect 'github down: alerts' ntfy_has 'Daily check failed'
expect 'github down: no success recorded' test ! -e "$SANDBOX/home/.local/state/pam-duo-macos-updater/last-check-success"

reset
print 'not json' > "$SANDBOX/openssl.json"
run check
expect 'malformed json: fails and alerts' ntfy_has 'Daily check failed'
expect 'malformed json: exits non-zero' status_is 1

reset
print '[]' > "$SANDBOX/openssl.json"
run check
expect 'no releases: fails, not up to date' status_is 1

reset
print '{"message":"API rate limit exceeded"}' > "$SANDBOX/openssl.json"
run check
expect 'error object from api: fails' status_is 1

reset
print 1 > "$SANDBOX/curl-fail-ntfy"
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 8)")
write_data
run check
expect 'ntfy down: exits non-zero' status_is 1
expect 'ntfy down: says so' has 'through ntfy'
expect 'ntfy down: no alert marker, so it retries' test ! -e "$SANDBOX/home/.local/state/pam-duo-macos-updater/alerted-update-ready"

reset
rm "$SANDBOX/home/.config/pam-duo-macos-updater/ntfy-topic"
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 8)")
write_data
run check
expect 'topic missing: exits non-zero' status_is 1
expect 'topic missing: says so' has 'ntfy-topic is missing'

reset
rm "$SANDBOX/fake/lib/pam_duo.so"
run check
expect 'module missing: check fails loudly' status_is 1
expect 'module missing: alerts' ntfy_has 'is missing'
run auto
expect 'module missing: auto is quiet on other Macs' status_is 0
run rebuild
expect 'module missing: rebuild refuses' status_is 1

reset
print 'garbage' > "$SANDBOX/fake/lib/pam_duo.so"
run check
expect 'unreadable versions: fails' status_is 1
expect 'unreadable versions: says so' has 'expected one OpenSSL version'

reset
touch "$SANDBOX/fake/run/swapped"
run check
expect 'interrupted install: alerts' ntfy_has "An install didn't finish"

print -- '--- commands and options'
reset
run nonsense
expect 'unknown command: exit 2' status_is 2
run build --bogus
expect 'unknown option: exit 2' status_is 2
run build
expect 'build when current: says so' has 'Already up to date'
expect 'build when current: succeeds' status_is 0

touch "$SANDBOX/agent-missing"
reset
run status
expect 'agent not loaded: status fails' status_is 1
expect 'agent not loaded: warns' has "isn't loaded"
run auto
expect 'agent not loaded: auto fails too' status_is 1
rm "$SANDBOX/agent-missing"

reset
run check
print $(($(date +%s) - 345600)) > "$SANDBOX/home/.local/state/pam-duo-macos-updater/last-check-success" # 4 days ago
run auto
expect 'stale daily check: auto warns' has 'last succeeded on'
expect 'stale daily check: auto fails' status_is 1

reset
run check
run auto
expect 'auto when current: reports it' has 'Duo module is up to date'
expect 'auto when current: succeeds' status_is 0

reset
run check
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 8)")
write_data
output=$(env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$SANDBOX" FORCE_NO_TTY=1 /bin/zsh -f "$SANDBOX/pam-duo-macos-updater" auto 2>&1)
code=$?
expect 'ready but no terminal: refuses' status_is 1
expect 'ready but no terminal: says why' has 'needs a terminal'

print -- '--- moratorium override and checksums'
reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 1)")
write_data
print "{\"assets\":[{\"name\":\"openssl-3.5.10.tar.gz\",\"digest\":\"sha256:$(printf '0%.0s' {1..64})\"}]}" > "$SANDBOX/openssl-tag.json"
run build --ignore-moratorium
expect 'override: targets the 1-day-old release' has '3.5.9 -> 3.5.10'
expect 'wrong checksum: refuses to build' has 'checksum mismatch'
expect 'wrong checksum: exits non-zero' status_is 1
print "{\"assets\":[{\"name\":\"openssl-3.5.9.tar.gz\",\"digest\":\"sha256:$(< $SANDBOX/fake-sum)\"}]}" > "$SANDBOX/openssl-tag.json"

reset
print "{\"assets\":[]}" > "$SANDBOX/openssl-tag.json"
run build --reinstall
expect 'no github checksum: refuses' has 'lists no checksum for OpenSSL'
print "{\"assets\":[{\"name\":\"openssl-3.5.9.tar.gz\",\"digest\":\"sha256:$(< $SANDBOX/fake-sum)\"}]}" > "$SANDBOX/openssl-tag.json"

reset
print '{"formulae":[{"versions":{"stable":"3.5.9"},"urls":{"stable":{"checksum":"beef"}}}]}' > "$SANDBOX/brew.json"
run build --reinstall
expect 'homebrew disagrees: refuses' has 'differ between GitHub and Homebrew'
print '{"formulae":[{"versions":{"stable":"9.9.9"},"urls":{"stable":{"checksum":"none"}}}]}' > "$SANDBOX/brew.json"

reset
print 'nothing here' > "$SANDBOX/duo-page.html"
run build --reinstall
expect 'no duo checksum: refuses' has 'lists no checksum for duo_unix'
print "<code>$(< $SANDBOX/fake-sum) duo_unix-2.3.0.tar.gz</code>" > "$SANDBOX/duo-page.html"

reset
run build --reinstall
expect 'bad tarball: build step fails, with the log' has 'build step failed'
expect 'bad tarball: exits non-zero' status_is 1
expect 'build dir cleaned up' test -z "$(print -l $SANDBOX/home/.local/state/pam-duo-macos-updater/build.*(N))"
setopt null_glob

print -- '--- lock'
reset
mkdir -p "$SANDBOX/home/.local/state/pam-duo-macos-updater"
zmodload zsh/system
touch "$SANDBOX/home/.local/state/pam-duo-macos-updater/lock"
zsystem flock -f held_lock "$SANDBOX/home/.local/state/pam-duo-macos-updater/lock"
run build --reinstall
expect 'second run: lock refused' has 'another pam-duo-macos-updater is already running'
zsystem flock -u $held_lock

print -- '--- verify_module, on real files'
sed -n "1,/^# Make sure there's somewhere to keep state/p" "$SANDBOX/pam-duo-macos-updater" | sed '$d' > "$SANDBOX/functions.zsh"

print -- '--- to_seconds'
seconds_of() {
  output=$(env -i HOME="$SANDBOX/home" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -f -c "
    source $SANDBOX/functions.zsh
    to_seconds $*
  " 2>&1)
  code=$?
}
seconds_of days=7
expect 'to_seconds: a week of days' test "$output" = 604800
seconds_of weeks=1 days=1 hours=1 minutes=1 seconds=1
expect 'to_seconds: every unit adds up' test "$output" = 694861
seconds_of day=1
expect 'to_seconds: unknown unit fails' status_is 2
expect 'to_seconds: unknown unit says which' has 'unknown unit: day=1'
seconds_of days=x
expect 'to_seconds: a non-number fails' status_is 2
seconds_of
expect 'to_seconds: no units fails' status_is 2
verify() {
  output=$(env -i HOME="$SANDBOX/home" PATH="${VERIFY_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" /bin/zsh -f -c "
    source $SANDBOX/functions.zsh
    target_openssl=$2 target_duo=$3
    mkdir -p $SANDBOX/verify
    cp '$1' $SANDBOX/verify/m.so
    verify_module $SANDBOX/verify/m.so
  " 2>&1)
  code=$?
}
verify "$FIXTURE_MODULE" 3.5.9 2.3.0
expect 'stand-in module: passes every check' status_is 0

# Local only: the installed module must pass too, at whatever versions it has.
if [[ -e $INSTALLED_MODULE ]]; then
  output=$(env -i HOME="$SANDBOX/home" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -f -c "
    source $SANDBOX/functions.zsh
    read_module_versions '$INSTALLED_MODULE' || exit 1
    target_openssl=\$module_openssl target_duo=\$module_duo
    mkdir -p $SANDBOX/verify
    cp '$INSTALLED_MODULE' $SANDBOX/verify/m.so
    verify_module $SANDBOX/verify/m.so
  " 2>&1)
  code=$?
  expect 'installed module: passes every check' status_is 0
else
  print -r -- "skip  installed module: none at $INSTALLED_MODULE, a local-only check"
fi
verify "$FIXTURE_MODULE" 3.5.10 2.3.0
expect 'wrong version built: refused' has 'not 3.5.10 and 2.3.0'
print 'int elsewhere(void) { return 1; }' > "$SANDBOX/elsewhere.c"
cc -dynamiclib -o "$SANDBOX/libelsewhere.dylib" "$SANDBOX/elsewhere.c"
print 'int elsewhere(void); int pam_sm_authenticate(void) { return elsewhere(); }' > "$SANDBOX/linked.c"
cc -bundle -o "$SANDBOX/linked.so" "$SANDBOX/linked.c" -L"$SANDBOX" -lelsewhere
verify "$SANDBOX/linked.so" 3.5.9 2.3.0
expect 'library outside /usr/lib: refused' has 'outside /usr/lib'
cat > "$SANDBOX/plain.c" << 'EOF'
const char *path = "/opt/homebrew/etc/openssl@3";
int pam_sm_authenticate(void) { return path != 0; }
EOF
cc -bundle -o "$SANDBOX/plain.so" "$SANDBOX/plain.c"
verify "$SANDBOX/plain.so" 3.5.9 2.3.0
expect 'user-writable path built in: refused' has 'user-writable paths built in'
print 'const char *note = "some text inside the module"; int pam_sm_authenticate(void) { return note != 0; }' > "$SANDBOX/plain.c"
cc -bundle -o "$SANDBOX/plain.so" "$SANDBOX/plain.c"
verify "$SANDBOX/plain.so" 3.5.9 2.3.0
expect 'no OpenSSL config path: refused' has "isn't under /etc/duo/ssl"

print -- '--- install, proof and rollback, with a faked sudo'
install_try() {
  output=$(env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$SANDBOX" /bin/zsh -f -c "
    source $SANDBOX/functions.zsh
    mkdir -p \$STATE_DIR \$LOG_DIR
    install_module $SANDBOX/new-module $SANDBOX/install.log
  " 2>&1)
  code=$?
}
new_module() { print "new module $RANDOM" > "$SANDBOX/new-module"; }
set_perms() {
  chgrp "$(id -gn)" "$SANDBOX/fake/etc/pam_duo.conf"
  chmod 600 "$SANDBOX/fake/etc/pam_duo.conf"
}

reset
set_perms
new_module
: > "$SANDBOX/install.log"
install_try
expect 'proven: succeeds' status_is 0
expect 'proven: new module in place' cmp -s "$SANDBOX/new-module" "$SANDBOX/fake/lib/pam_duo.so"
expect 'proven: old one kept as previous' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so.previous"
expect 'proven: markers cleared' test ! -e "$SANDBOX/fake/run/swapped"

reset
set_perms
new_module
print 1 > "$SANDBOX/sudo-deny"
: > "$SANDBOX/install.log"
install_try
expect 'denied: fails' status_is 1
expect 'denied: says it restored' has 'old module was restored'
expect 'denied: old module back in place' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"
expect 'denied: markers cleared' test ! -e "$SANDBOX/fake/run/swapped"

reset
new_module
print 'failmode = safe' > "$SANDBOX/fake/etc/pam_duo.conf"
set_perms
: > "$SANDBOX/install.log"
install_try
expect 'failmode safe: refused' status_is 1
expect 'failmode safe: module untouched' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"
expect 'failmode safe: reason logged' grep -q 'must set failmode = secure' "$SANDBOX/install.log"

reset
set_perms
new_module
chmod 644 "$SANDBOX/fake/etc/pam_duo.conf"
: > "$SANDBOX/install.log"
install_try
expect 'config readable by others: refused' status_is 1
expect 'config readable by others: module untouched' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"

reset
set_perms
new_module
print 'nothing' > "$SANDBOX/fake/etc/sudo_local"
: > "$SANDBOX/install.log"
install_try
expect 'duo not turned on: refused' status_is 1
expect 'duo not turned on: module untouched' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"

# Root must reject a module changed after it was verified.
reset
set_perms
new_module
: > "$SANDBOX/install.log"
output=$(env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$SANDBOX" "$SANDBOX/libexec/pam-duo-macos-updater-root" "$SANDBOX/new-module" "$(printf '0%.0s' {1..64})" run.1 2>&1)
code=$?
expect 'module changed after verifying: refused' has 'changed since it was verified'
expect 'module changed after verifying: untouched' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"

# Signals during the wait must restore the old module.
reset
set_perms
new_module
env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$SANDBOX" "$SANDBOX/libexec/pam-duo-macos-updater-root" "$SANDBOX/new-module" "$(shasum -a 256 "$SANDBOX/new-module" | cut -d ' ' -f 1)" run.2 > "$SANDBOX/signal.log" 2>&1 &
signal_pid=$!

# Wait until the marker holds this run's ID, which the helper writes only
# after its trap is set and the new module is in place.
#
# - This once waited only for the marker to exist, but the helper writes it
#   as "pending" before both, so CI sometimes compared too early and sent HUP
#   before the trap, which killed the helper with 129 rather than 4 (#15).
#
# - The deadline is generous for slow runners, and the wait stops early if
#   the helper has exited, so a broken helper fails here rather than hanging.
#
# - Verified by stalling the helper after writing "pending", which failed the
#   old wait every time and passes this one.
reached_wait=0
for ((i = 0; i < 300; i++)); do
  [[ $(< "$SANDBOX/fake/run/swapped") == run.2 ]] 2> /dev/null && {
    reached_wait=1
    break
  }
  kill -0 $signal_pid 2> /dev/null || break
  sleep 0.1
done
expect 'closing terminal: helper reached the wait' test $reached_wait = 1
expect 'closing terminal: new module was swapped in first' cmp -s "$SANDBOX/new-module" "$SANDBOX/fake/lib/pam_duo.so"
kill -HUP $signal_pid
wait $signal_pid
code=$?
expect 'closing terminal: status 4' status_is 4
expect 'closing terminal: old module restored' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"

print -- '--- review findings'
# 1 and 2: a leftover marker can't fool the wait, or poison the backup.
reset
set_perms
new_module
cp "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so.previous"
print 'unproven module' > "$SANDBOX/fake/lib/pam_duo.so"
print 'old-run' > "$SANDBOX/fake/run/swapped"
: > "$SANDBOX/install.log"
install_try
expect 'leftover marker: install still succeeds' status_is 0
expect 'leftover marker: new module in place' cmp -s "$SANDBOX/new-module" "$SANDBOX/fake/lib/pam_duo.so"
expect 'leftover marker: backup is the proven module' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so.previous"
expect 'leftover marker: restored first' grep -q "didn't finish; restoring first" "$SANDBOX/install.log"

# And denying that next install still falls back to the proven one.
reset
set_perms
new_module
cp "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so.previous"
print 'unproven module' > "$SANDBOX/fake/lib/pam_duo.so"
print 'old-run' > "$SANDBOX/fake/run/swapped"
print 1 > "$SANDBOX/sudo-deny"
: > "$SANDBOX/install.log"
install_try
expect 'leftover then denied: proven module restored' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"

# 4: a failed restore is reported as failed.
reset
set_perms
new_module
print 'old-run' > "$SANDBOX/fake/run/swapped"
: > "$SANDBOX/install.log"
install_try
expect 'restore fails: says so' has 'RESTORE FAILED'
expect 'restore fails: never claims it restored' lacks 'was restored'
expect 'restore fails: marker kept for the daily check' test -e "$SANDBOX/fake/run/swapped"

# 3: the copy root checks is the copy it installs.
reset
set_perms
new_module
: > "$SANDBOX/install.log"
output=$(env -i HOME="$SANDBOX/home" PATH="$SANDBOX/shims:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$SANDBOX" "$SANDBOX/libexec/pam-duo-macos-updater-root" "$SANDBOX/new-module" "$(printf '0%.0s' {1..64})" run.3 2>&1)
code=$?
expect 'wrong checksum: leaves no new file behind' test ! -e "$SANDBOX/fake/lib/pam_duo.so.new"
expect 'wrong checksum: status 2' status_is 2

# 6: the root-owned helper is checked before it's trusted.
reset
print '# edited' >> "$SANDBOX/libexec/pam-duo-macos-updater-root"
run check
expect 'helper differs: alerts' ntfy_has 'differs from the repo'
expect 'helper differs: check fails' status_is 0
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 8)")
write_data
run rebuild
expect 'helper differs: rebuild refuses' has 'differs from the repo'
expect 'helper differs: rebuild fails' status_is 1
expect 'helper differs: nothing built' lacks 'Downloading'
reset
rm "$SANDBOX/libexec/pam-duo-macos-updater-root"
run status
expect 'helper missing: status fails' status_is 1
expect 'helper missing: says what to do' has 'install-helper'
reset
chmod 775 "$SANDBOX/libexec/pam-duo-macos-updater-root"
run status
expect 'helper group-writable: refused' has 'must be owned by root'
chmod 755 "$SANDBOX/libexec/pam-duo-macos-updater-root"
reset
output=$("$SANDBOX/libexec/pam-duo-macos-updater-root" only-one-arg 2>&1)
code=$?
expect 'helper bad arguments: status 2' status_is 2
output=$("$SANDBOX/libexec/pam-duo-macos-updater-root" /x nothex run.1 2>&1)
code=$?
expect 'helper bad checksum format: status 2' status_is 2

# Config safety that the first version missed.
reset
set_perms
new_module
printf 'failmode = secure\nfailmode = safe\n' > "$SANDBOX/fake/etc/pam_duo.conf"
: > "$SANDBOX/install.log"
install_try
expect 'two failmode lines: refused' status_is 1
expect 'two failmode lines: module untouched' cmp -s "$FIXTURE_MODULE" "$SANDBOX/fake/lib/pam_duo.so"
reset
set_perms
new_module
print "# auth sufficient $SANDBOX/fake/lib/pam_duo.so" > "$SANDBOX/fake/etc/sudo_local"
: > "$SANDBOX/install.log"
install_try
expect 'commented-out duo line: refused' status_is 1

# 5: a failed tool isn't a clean result.
mkdir -p "$SANDBOX/badtools"
print '#!/bin/sh\nexit 1' > "$SANDBOX/badtools/otool"
chmod +x "$SANDBOX/badtools/otool"
VERIFY_PATH="$SANDBOX/badtools:/usr/bin:/bin:/usr/sbin:/sbin" verify "$FIXTURE_MODULE" 3.5.9 2.3.0
expect 'otool fails: refused' has "couldn't list the libraries"
rm "$SANDBOX/badtools/otool"
print '#!/bin/sh\nexit 1' > "$SANDBOX/badtools/strings"
chmod +x "$SANDBOX/badtools/strings"
VERIFY_PATH="$SANDBOX/badtools:/usr/bin:/bin:/usr/sbin:/sbin" verify "$FIXTURE_MODULE" 3.5.9 2.3.0
expect 'strings fails: refused' has "couldn't read the text"
rm "$SANDBOX/badtools/strings"

# 7: a job that has never succeeded can't stay quiet forever.
reset
mkdir -p "$SANDBOX/home/Library/LaunchAgents"
P="$SANDBOX/home/Library/LaunchAgents/io.github.jjloneman.pam-duo-macos-updater-check.plist"
: > "$P"
run status
expect 'never succeeded, just installed: only a note' has "hasn't succeeded yet"
expect 'never succeeded, just installed: passes' status_is 0
touch -t 202601010000 "$P"
run status
expect 'never succeeded, old install: warns' has 'has never succeeded'
expect 'never succeeded, old install: fails' status_is 1

# 9: a newer ready release alerts immediately.
reset
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 9)")
write_data
run check
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)" "openssl-3.5.10 $(days_ago 9)" "openssl-3.5.11 $(days_ago 8)")
write_data
run check
expect 'newer ready release: alerts right away' ntfy_has '3.5.9 -> 3.5.11'
expect 'newer ready release: two alerts total' ntfy_count 2
run check
expect 'newer ready release: not repeated' ntfy_count 2
expect 'older marker removed' test ! -e "$SANDBOX/home/.local/state/pam-duo-macos-updater/alerted-update-ready-3.5.10-2.3.0"
OPENSSL_JSON=$(releases_json "openssl-3.5.9 $(days_ago 38)")
write_data
run check
expect 'back to current: alert cleared' test -z "$(print -l $SANDBOX/home/.local/state/pam-duo-macos-updater/alerted-update-ready-*(N))"

# 10: a resolved series warning clears.
reset
mkdir -p "$SANDBOX/home/.local/state/pam-duo-macos-updater"
date +%s > "$SANDBOX/home/.local/state/pam-duo-macos-updater/alerted-series-ending"
run check
expect 'series no longer ending: marker cleared' test ! -e "$SANDBOX/home/.local/state/pam-duo-macos-updater/alerted-series-ending"

# Installed newer than anything listed isn't reported as held.
reset
OPENSSL_JSON=$(releases_json "openssl-3.5.8 $(days_ago 80)")
write_data
run check
expect 'installed newer than listed: nothing held' lacks 'held by'

# The plist stays valid XML wherever the repo and home are.
mkdir -p "$SANDBOX/R&D <x>"
cp "$SANDBOX/functions.zsh" "$SANDBOX/R&D <x>/functions.zsh"
output=$(env -i HOME="$SANDBOX/R&D <x>" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -f -c "
  source '$SANDBOX/R&D <x>/functions.zsh'
  write_plist '$SANDBOX/escaped.plist'
" 2>&1)
code=$?
expect 'plist with & and < in paths: written' status_is 0
expect 'plist with & and < in paths: valid' plutil -lint -s "$SANDBOX/escaped.plist"
expect 'plist with & and < in paths: keeps the path' test "$(plutil -extract ProgramArguments.2 raw "$SANDBOX/escaped.plist")" = "${SANDBOX:A}/R&D <x>/functions.zsh"

# 8: the real script fixes its PATH, whatever it inherits.
expect 'real script ignores inherited PATH' grep -qx 'path=(/usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin)' "$SOURCE"

print
print -r -- "passed: $pass, failed: $failures"
((failures == 0))
