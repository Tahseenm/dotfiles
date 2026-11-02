#!/usr/bin/env bash
#
# github-ssh.sh -- generate a personal SSH key and register it with GitHub.
#
# Run after install.sh, which installs the GitHub CLI. Idempotent: reuses an
# existing key and skips registration when the key is already on the account.
#
# Usage: ./github-ssh.sh [--title <title>] [--dry-run]

set -euo pipefail

GH_HOST="github.com"
GH_KEYS_URL="https://github.com/settings/keys"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
KEY_PATH="$SSH_DIR/id_github-personal"

# Sentinel comments delimiting the block this script owns in ~/.ssh/config.
CONFIG_BEGIN='# >>> github-ssh.sh >>>'
CONFIG_END='# <<< github-ssh.sh <<<'

TITLE=""
DRY_RUN=0
# Login of the account selected for this run; set once gh auth is settled.
EXPECTED_LOGIN=""

log()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--title <title>] [--dry-run]

Generates an ed25519 SSH key at $KEY_PATH (no passphrase), points
~/.ssh/config at it for $GH_HOST, and registers the public key with your
personal GitHub account using gh.

  --title <title>  GitHub key title (for example the host name). Prompted if
                   omitted.
  --dry-run        Show what would happen without changing anything.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || die '--title requires a value.'
      TITLE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# --- helpers ---------------------------------------------------------------

key_comment() {
  local email
  email="$(git config --get user.email 2>/dev/null || true)"
  if [[ -n "$email" ]]; then
    printf '%s' "$email"
  else
    printf '%s@%s' "$(id -un)" "$(hostname -s)"
  fi
}

local_fingerprint() {
  ssh-keygen -lf "$KEY_PATH.pub" 2>/dev/null | awk '{print $2}'
}

# Print the SHA256 fingerprint of every SSH key already on the account.
remote_fingerprints() {
  local key tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/github-ssh.key.XXXXXX")" || return 1
  gh api --paginate /user/keys --jq '.[].key' 2>/dev/null \
    | while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        printf '%s\n' "$key" > "$tmp"
        ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}'
      done
  rm -f "$tmp"
}

# The account the key is added to is the active gh account.
active_login() {
  gh api user --jq .login 2>/dev/null || true
}

# One login name per authenticated account on the host.
gh_logins() {
  gh auth status --hostname "$GH_HOST" 2>&1 \
    | sed -nE 's/.*Logged in to [^ ]+ account ([^ ]+).*/\1/p' || true
}

# --- steps -----------------------------------------------------------------

ensure_gh_auth() {
  if gh auth status --active --hostname "$GH_HOST" >/dev/null 2>&1; then
    return
  fi
  log "Not signed in to $GH_HOST; starting gh auth login..."
  gh auth login --hostname "$GH_HOST" --git-protocol ssh --skip-ssh-key --web --scopes admin:public_key
}

# Inspect only response headers, without printing credentials or user data.
has_key_write_scope() {
  local headers
  headers="$(gh api --hostname "$GH_HOST" --include --silent user)" \
    || die 'could not check GitHub SSH-key permissions; no local changes made.'
  printf '%s\n' "$headers" | awk '
    tolower($1) == "x-oauth-scopes:" {
      sub(/^[^:]*:[[:space:]]*/, "")
      n = split($0, scopes, /[,[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (scopes[i] == "admin:public_key" || scopes[i] == "write:public_key") found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

ensure_key_permissions() {
  if has_key_write_scope; then
    return
  fi
  log "Requesting SSH-key write permission for $EXPECTED_LOGIN..."
  gh auth refresh --hostname "$GH_HOST" --scopes admin:public_key \
    || die 'could not obtain admin:public_key; if using GH_TOKEN/GITHUB_TOKEN, update its permissions before rerunning.'
  has_key_write_scope \
    || die 'could not verify SSH-key write permission; use a classic token with admin:public_key or a gh browser login.'
  [[ "$(active_login)" == "$EXPECTED_LOGIN" ]] \
    || die 'the active GitHub account changed during authorization; rerun to confirm the account.'
}

# Refuse to guess when several accounts are authenticated: the key would go to
# whichever one is active.
confirm_account() {
  local logins count login reply
  login="$EXPECTED_LOGIN"
  [[ -n "$login" ]] || die "could not determine the active $GH_HOST account."

  logins="$(gh_logins)"
  count="$(printf '%s\n' "$logins" | grep -c . || true)"
  if [[ "$count" -le 1 ]]; then
    return
  fi

  log "Multiple $GH_HOST accounts are signed in:"
  printf '%s\n' "$logins" | sed 's/^/  /'
  printf 'Add the key to the active account "%s"? [y/N] ' "$login" >&2
  if ! IFS= read -r reply; then
    die 'account confirmation is required.'
  fi
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) die "aborted; run 'gh auth switch', then rerun this script." ;;
  esac
}

resolve_title() {
  [[ -n "$TITLE" ]] && return
  if [[ ! -t 0 ]]; then
    die 'no --title given and stdin is not a terminal.'
  fi
  printf 'GitHub key title: ' >&2
  if ! IFS= read -r TITLE; then
    die 'could not read the key title.'
  fi
  [[ -n "$TITLE" ]] || die 'the key title cannot be empty.'
}

ensure_key() {
  local public_key
  if [[ -f "$KEY_PATH" ]]; then
    if [[ ! -f "$KEY_PATH.pub" ]]; then
      log "Restoring public key: $KEY_PATH.pub"
      public_key="$(ssh-keygen -y -f "$KEY_PATH")" \
        || die "could not derive the public key from $KEY_PATH; no configuration changes made."
      printf '%s\n' "$public_key" > "$KEY_PATH.pub"
    fi
    log "Reusing existing key: $KEY_PATH"
    return
  fi
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  log "Generating ed25519 key: $KEY_PATH"
  ssh-keygen -t ed25519 -N '' -C "$(key_comment)" -f "$KEY_PATH"
}

config_block() {
  local identity="$KEY_PATH"
  identity="${identity//\\/\\\\}"
  identity="${identity//\"/\\\"}"
  cat <<EOF
$CONFIG_BEGIN
Host $GH_HOST
  IdentityFile "$identity"
  IdentitiesOnly yes
$CONFIG_END
EOF
}

# Write the config without the block this script owns, so re-runs replace it
# rather than duplicating it and the checks below see only foreign entries.
# Reject unmatched or nested markers; callers must discard the output on failure.
strip_managed_block() {
  local src="$1" dst="$2"
  if [[ -f "$src" ]]; then
    awk -v begin="$CONFIG_BEGIN" -v end="$CONFIG_END" '
      BEGIN { skip = 0 }
      $0 == begin { if (skip) invalid = 1; skip = 1; next }
      $0 == end   { if (!skip) invalid = 1; skip = 0; next }
      skip == 0   { print }
      END { if (skip || invalid) exit 1 }
    ' "$src" > "$dst"
  else
    : > "$dst"
  fi
}

# Validate the proposed config with OpenSSH so Match, Include, global options,
# and host patterns use the same semantics as a real connection. Return 0 and
# print diagnostics on conflicts or parse errors; return 1 when isolated.
ssh_config_conflicts() {
  local file="$1" probe effective line identity found_identity=0
  local -a conflicts=()

  probe="$(mktemp "${TMPDIR:-/tmp}/github-ssh.probe.XXXXXX")" \
    || { printf '%s\n' 'could not create an SSH validation file.'; return 0; }
  cat "$file" > "$probe"
  # -F skips the system config; include it explicitly after the user config,
  # starting in global context as OpenSSH does for the system file.
  if [[ -f /etc/ssh/ssh_config ]]; then
    printf '\nHost *\n  Include /etc/ssh/ssh_config\n' >> "$probe"
  fi
  if ! effective="$(ssh -G -F "$probe" "git@$GH_HOST" 2>&1)"; then
    rm -f "$probe"
    printf 'OpenSSH could not validate the proposed configuration:\n%s\n' "$effective"
    return 0
  fi
  rm -f "$probe"

  while IFS= read -r line; do
    case "$line" in
      'identitiesonly yes') ;;
      identitiesonly\ *) conflicts+=("$line") ;;
      identityfile\ *)
        identity="${line#identityfile }"
        if [[ "$identity" == "$KEY_PATH" ]]; then
          found_identity=1
        elif [[ "$identity" != none ]]; then
          conflicts+=("$line")
        fi ;;
    esac
  done <<< "$effective"
  if [[ "$found_identity" -ne 1 ]]; then
    conflicts+=("the personal IdentityFile is not effective")
  fi

  if [[ "${#conflicts[@]}" -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${conflicts[@]}"
  return 0
}

write_ssh_config() {
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  local tmp base conflicts
  tmp="$(mktemp "${TMPDIR:-/tmp}/github-ssh.config.XXXXXX")" || die 'could not create a temporary file.'
  base="$(mktemp "${TMPDIR:-/tmp}/github-ssh.base.XXXXXX")" || die 'could not create a temporary file.'

  if ! strip_managed_block "$SSH_CONFIG" "$base"; then
    rm -f "$tmp" "$base"
    die "could not safely read $SSH_CONFIG; check for unmatched or nested managed-block markers."
  fi

  # Refuse to edit a github.com entry this script does not own.
  if awk -v host="$GH_HOST" '
      /^[[:space:]]*[Hh]ost[[:space:]]/ {
        for (i = 2; i <= NF; i++) if ($i == host) found = 1
      }
      END { exit found ? 0 : 1 }
    ' "$base"; then
    rm -f "$tmp" "$base"
    die "$SSH_CONFIG already defines an unmanaged Host $GH_HOST entry; merge it by hand."
  fi

  append_config_block "$base" "$tmp"

  # Validate before replacing the existing config or uploading the key.
  if conflicts="$(ssh_config_conflicts "$tmp")"; then
    rm -f "$tmp" "$base"
    {
      printf 'error: proposed %s configuration is invalid or does not isolate the personal key for %s:\n' "$SSH_CONFIG" "$GH_HOST"
      printf '%s\n' "$conflicts" | sed 's/^/  - /'
      printf 'OpenSSH keeps the first IdentitiesOnly value and accumulates IdentityFile entries,\n'
      printf 'so another key would still be offered for %s. Restrict those settings so they no\n' "$GH_HOST"
      printf 'longer match %s, then rerun this script.\n' "$GH_HOST"
    } >&2
    exit 1
  fi

  mv -f "$tmp" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  rm -f "$base"
  log "Updated $SSH_CONFIG"
}

append_config_block() {
  local base="$1" tmp="$2"
  # Drop trailing blank lines so repeated runs do not accumulate them.
  awk '
    BEGIN { blank = 0 }
    /^[[:space:]]*$/ { blank++; next }
    { for (i = 0; i < blank; i++) print ""; blank = 0; print }
  ' "$base" > "$tmp"

  if [[ -s "$tmp" ]]; then
    printf '\n' >> "$tmp"
  fi
  config_block >> "$tmp"
}

register_key() {
  local fp
  fp="$(local_fingerprint)"
  [[ -n "$fp" ]] || die "could not read the fingerprint of $KEY_PATH.pub"

  if remote_fingerprints | grep -qxF "$fp"; then
    log "Key already registered with GitHub ($fp); skipping upload."
    return
  fi
  log "Adding key to GitHub as \"$TITLE\"..."
  gh ssh-key add "$KEY_PATH.pub" --title "$TITLE"
}

# ssh exits 1 on success here, so read the greeting instead of the status. The
# greeting names the account the offered key belongs to, which must be the
# selected account: another registered identity would authenticate as itself.
verify_connection() {
  local out greeting login want got
  out="$(ssh -T -o StrictHostKeyChecking=accept-new "git@$GH_HOST" 2>&1)" || true

  if [[ "$out" != *"successfully authenticated"* ]]; then
    die "SSH authentication to $GH_HOST failed: $out"
  fi

  greeting="$(printf '%s\n' "$out" | awk '/^Hi / { print; exit }')"
  login="$(printf '%s' "$greeting" | awk '{ sub(/^Hi /, ""); sub(/!.*/, ""); print }')"
  if [[ -z "$login" ]]; then
    die "could not read the account from GitHub's greeting: $out"
  fi

  got="$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
  want="$(printf '%s' "$EXPECTED_LOGIN" | tr '[:upper:]' '[:lower:]')"
  if [[ "$got" != "$want" ]]; then
    die "SSH authenticated to $GH_HOST as '$login', not '$EXPECTED_LOGIN': another registered key was offered first. Check the order and IdentitiesOnly in $SSH_CONFIG."
  fi

  log "Verified: $greeting"
}

print_summary() {
  printf '\n'
  log "GitHub account: $EXPECTED_LOGIN"
  log "Key:           $KEY_PATH"
  log "Fingerprint:   $(local_fingerprint)"
  printf '\nPublic key:\n'
  cat "$KEY_PATH.pub"
  printf '\nManage keys at %s\n' "$GH_KEYS_URL"
}

dry_run() {
  local title="${TITLE:-<title>}"
  log 'Dry run: no changes will be made.'
  printf '\n'
  if ! have gh; then
    log 'gh: not installed (run ./install.sh first)'
  elif gh auth status --hostname "$GH_HOST" >/dev/null 2>&1; then
    log "gh: already authenticated to $GH_HOST"
  else
    log "gh: would run: gh auth login --hostname $GH_HOST --git-protocol ssh --web --scopes admin:public_key"
  fi
  log "gh: would check SSH-key write permission and request admin:public_key if missing"
  log "gh: would run: gh config set git_protocol ssh --host $GH_HOST"
  log "key: $KEY_PATH"
  if [[ -f "$KEY_PATH" ]]; then
    if [[ -f "$KEY_PATH.pub" ]]; then
      log "key: exists; would reuse (fingerprint $(local_fingerprint))"
    else
      log "key: exists; would restore the missing public key from the private key and reuse"
    fi
  else
    log "key: would generate ed25519, no passphrase, comment \"$(key_comment)\""
  fi
  log "config: would set Host $GH_HOST -> $KEY_PATH (IdentitiesOnly yes) in $SSH_CONFIG"
  if ! strip_managed_block "$SSH_CONFIG" /dev/null; then
    log "config: warning -- a real run would refuse; could not safely read $SSH_CONFIG; check for unmatched or nested managed-block markers."
  fi
  log 'config: OpenSSH validation deferred until a real run because Match exec can execute commands.'
  log "github: would add \"$KEY_PATH.pub\" with title \"$title\""
  log "verify: would run: ssh -T git@$GH_HOST and confirm the greeting matches the selected account"
}

main() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    dry_run
    return
  fi

  have gh || die 'gh not found; run ./install.sh first, then rerun this script.'
  have ssh-keygen || die 'ssh-keygen not found.'
  have ssh || die 'ssh not found.'

  ensure_gh_auth
  EXPECTED_LOGIN="$(active_login)"
  [[ -n "$EXPECTED_LOGIN" ]] || die "could not determine the active $GH_HOST account."
  confirm_account
  ensure_key_permissions
  resolve_title
  ensure_key
  gh config set git_protocol ssh --host "$GH_HOST"
  write_ssh_config
  register_key
  verify_connection
  print_summary
}

main "$@"
