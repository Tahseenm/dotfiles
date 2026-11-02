#!/bin/bash
# Portable, curated preferences observed on this Mac on 2026-11-01.
# Source: macOS 27.0.1 (26A434), Apple Silicon.
# This is NOT an exhaustive factory-default diff.
# Run as the destination user, without sudo. Preview is the default.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: bash macos-defaults.sh [--dry-run | --apply | --check]
  --dry-run  Print planned commands; change nothing (default).
  --apply    Back up affected preference domains, then apply settings.
  --check    Compare stored values with this profile; change nothing.
Close System Settings before applying. Log out and back in afterwards.
HELP
}
mode="${1:---dry-run}"
if [[ $# -gt 1 ]]; then usage >&2; exit 2; fi
case "$mode" in
    --help|-h) usage; exit 0 ;;
    --dry-run|--apply|--check) ;;
    *) usage >&2; exit 2 ;;
esac
[[ "$(/usr/bin/uname -s)" == Darwin ]] || { echo 'This script requires macOS.' >&2; exit 1; }
[[ "$EUID" -ne 0 ]] || { echo 'Run as your regular Mac user, without sudo.' >&2; exit 1; }
major=$(/usr/bin/sw_vers -productVersion)
major=${major%%.*}
if [[ "$major" != 27 ]]; then
    echo 'Note: captured on macOS 27; preference behavior may differ on this version.' >&2
fi
if [[ "$mode" == --apply ]] && /usr/bin/pgrep -x 'System Settings' >/dev/null; then
    echo 'Close System Settings, then run --apply again.' >&2
    exit 1
fi
backup_dir=''
if [[ "$mode" == --apply ]]; then
    umask 077
    backup_root="$HOME/Library/Application Support/macos-defaults/backups"
    /bin/mkdir -p "$backup_root"
    backup_dir=$(/usr/bin/mktemp -d "$backup_root/$(/bin/date +%Y%m%d-%H%M%S).XXXXXX")
    echo "Preference backups: $backup_dir"
    # Back up ALL affected domains before the first write. Fail if an existing
    # domain cannot be exported. These backups can include private app state.
    for domain in NSGlobalDomain com.apple.dock com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
        if /usr/bin/defaults read "$domain" >/dev/null 2>&1; then
            /usr/bin/defaults export "$domain" "$backup_dir/$domain.plist"
        else
            : > "$backup_dir/$domain.absent"
        fi
    done
    if /usr/bin/defaults -currentHost read NSGlobalDomain >/dev/null 2>&1; then
        /usr/bin/defaults -currentHost export NSGlobalDomain "$backup_dir/NSGlobalDomain.currentHost.plist"
    else
        : > "$backup_dir/NSGlobalDomain.currentHost.absent"
    fi
fi
mismatches=0
settings=0
pref() {
    local scope="$1" domain="$2" key="$3" type="$4" value="$5" actual expected
    local cmd=(/usr/bin/defaults)
    if [[ "$scope" == host ]]; then cmd+=(-currentHost); fi
    settings=$((settings + 1))
    if [[ "$mode" == --dry-run ]]; then
        printf '%q ' "${cmd[@]}" write "$domain" "$key" "-$type" "$value"
        printf '\n'
    elif [[ "$mode" == --check ]]; then
        expected="$value"
        [[ "$type" != bool || "$value" != true ]] || expected=1
        [[ "$type" != bool || "$value" != false ]] || expected=0
        actual=$("${cmd[@]}" read "$domain" "$key" 2>/dev/null) || actual='<unset>'
        if [[ "$actual" != "$expected" ]]; then
            printf 'DIFF [%s] %s / %s: stored=%s expected=%s\n' "$scope" "$domain" "$key" "$actual" "$expected"
            mismatches=$((mismatches + 1))
        fi
    else
        "${cmd[@]}" write "$domain" "$key" "-$type" "$value"
        printf 'Set %s / %s = %s\n' "$domain" "$key" "$value"
    fi
}

# =============================================================================
# Appearance
# =============================================================================

# Switch automatically between Light and Dark appearance throughout the day.
# Do not force the source Mac's current (time-dependent) appearance.
pref user NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically bool true

# =============================================================================
# Keyboard
# =============================================================================

# Repeat a held key quickly. A smaller KeyRepeat value means faster repetition.
# This controls repetition speed after the initial delay.
pref user NSGlobalDomain KeyRepeat float 2

# Set the delay before a held key starts repeating to the observed value of 25.
# A smaller InitialKeyRepeat value means a shorter delay.
pref user NSGlobalDomain InitialKeyRepeat float 25

# =============================================================================
# Trackpad
# =============================================================================

# Configure both built-in and external Apple trackpad preference domains.
# Supporting gesture values keep three-finger dragging compatible with swipes.
for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    # Let a light one-finger tap act as a click without pressing the trackpad.
    pref user "$domain" Clicking bool true

    # Drag windows and other items with three fingers, without holding a click.
    pref user "$domain" TrackpadThreeFingerDrag bool true

    # Disable three-finger horizontal swipes to reserve three fingers for dragging.
    pref user "$domain" TrackpadThreeFingerHorizSwipeGesture int 0

    # Disable three-finger vertical swipes for the same reason.
    pref user "$domain" TrackpadThreeFingerVertSwipeGesture int 0

    # Disable the three-finger tap gesture alongside three-finger dragging.
    pref user "$domain" TrackpadThreeFingerTapGesture int 0

    # Retain the source Mac's four-finger horizontal swipe gesture setting.
    pref user "$domain" TrackpadFourFingerHorizSwipeGesture int 2

    # Retain the source Mac's four-finger vertical swipe gesture setting.
    pref user "$domain" TrackpadFourFingerVertSwipeGesture int 2
done

# Mirror these settings in the destination Mac's host-specific preferences.
# -currentHost targets the new Mac; no source hardware identifier is copied.

# Enable tap-to-click in the host-specific input preferences as well.
pref host NSGlobalDomain com.apple.mouse.tapBehavior int 1

# Enable three-finger dragging for this host.
pref host NSGlobalDomain com.apple.trackpad.threeFingerDragGesture bool true

# Reserve three-finger horizontal swipes for dragging on this host.
pref host NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture int 0

# Reserve three-finger vertical swipes for dragging on this host.
pref host NSGlobalDomain com.apple.trackpad.threeFingerVertSwipeGesture int 0

# Disable three-finger tapping on this host to match the trackpad domains.
pref host NSGlobalDomain com.apple.trackpad.threeFingerTapGesture int 0

# Preserve the matching four-finger horizontal swipe setting on this host.
pref host NSGlobalDomain com.apple.trackpad.fourFingerHorizSwipeGesture int 2

# Preserve the matching four-finger vertical swipe setting on this host.
pref host NSGlobalDomain com.apple.trackpad.fourFingerVertSwipeGesture int 2

# =============================================================================
# Dock
# =============================================================================

# Hide the Dock when unused; reveal it by moving the pointer to its screen edge.
pref user com.apple.dock autohide bool true

# Enlarge Dock icons when the pointer moves over them.
pref user com.apple.dock magnification bool true

# Set the normal Dock icon size to the observed value of 52.
pref user com.apple.dock tilesize float 52

# Set the enlarged Dock icon size to the observed value of 77.
pref user com.apple.dock largesize float 77

# Hide the separate section for recent applications; keep pinned apps unchanged.
pref user com.apple.dock show-recents bool false

# Displays: no resolution, scaling, brightness or monitor-layout tweaks captured.
# These hardware-dependent settings are left for setup on the destination Mac.

# =============================================================================
# Result
# =============================================================================

if [[ "$mode" == --check ]]; then
    printf '%s settings checked; %s stored-value differences.\n' "$settings" "$mismatches"
    [[ "$mismatches" == 0 ]] || exit 1
elif [[ "$mode" == --apply ]]; then
    echo 'Preferences saved. Log out and back in, then verify the UI and run --check.'
    echo 'This script does not restart apps or log you out automatically.'
else
    echo 'Preview only. Use --apply to save these settings on the destination Mac.'
fi
