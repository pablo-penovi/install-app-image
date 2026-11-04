#!/usr/bin/env bash
#
# install.sh: install, upgrade or uninstall installappimage and its DMS bar
# plugin. Supports Niri with DankMaterialShell only.
#
#   ./install.sh              install, or upgrade an existing install
#   ./install.sh --uninstall  remove the script, plugin, login check and config;
#                             installed apps keep working from the menu

set -Eeuo pipefail
shopt -s nullglob

REPO_DIR=$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")
readonly REPO_DIR
readonly NAME=installappimage
readonly PLUGIN_ID=installAppImage
readonly SRC_SCRIPT=$REPO_DIR/$NAME
readonly SRC_PLUGIN=$REPO_DIR/dms-plugin/$PLUGIN_ID

: "${HOME:?HOME is not set}"
readonly CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
readonly CONFIG_FILE=$CONFIG_HOME/installappimage/config
readonly PLUGINS_DIR=$CONFIG_HOME/DankMaterialShell/plugins
readonly PLUGIN_DEST=$PLUGINS_DIR/$PLUGIN_ID
readonly DMS_SETTINGS=$CONFIG_HOME/DankMaterialShell/settings.json
readonly UNIT_NAME=installappimage-check.service
readonly UNIT_FILE=$CONFIG_HOME/systemd/user/$UNIT_NAME
readonly LEGACY_SCRIPT=$HOME/.local/bin/installappimage.sh
readonly DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/installappimage
readonly STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/installappimage

if [[ -t 1 ]]; then
    B=$'\e[1m' R=$'\e[31m' Y=$'\e[33m' G=$'\e[32m' D=$'\e[2m' Z=$'\e[0m'
else
    B='' R='' Y='' G='' D='' Z=''
fi
info() { printf '%s==>%s %s\n' "$B" "$Z" "$*"; }
note() { printf '    %s\n' "$*"; }
ok() { printf '    %s✓%s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%swarning:%s %s\n' "$Y" "$Z" "$*" >&2; }
die() {
    printf '%serror:%s %s\n' "$R" "$Z" "$*" >&2
    exit 1
}

# Shows ~ for the home directory.
tildify() { if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi; }
expand() { realpath -m -- "${1/#\~/$HOME}"; }

# Same reason as in installappimage: a parent AppImage's libraries break
# system tools (notify-send, dms) started from here.
sanitize_env() {
    local var part out
    local -a parts
    for var in LD_LIBRARY_PATH LD_PRELOAD PATH; do
        [[ -n ${!var-} ]] || continue
        out=''
        IFS=': ' read -ra parts <<<"${!var}"
        for part in "${parts[@]}"; do
            if [[ -n $part && $part != */.mount_* ]]; then out+=${out:+:}$part; fi
        done
        if [[ -n $out ]]; then export "$var=$out"; else unset "$var"; fi
    done
}

config_get() {
    [[ -f $CONFIG_FILE ]] || return 0
    sed -n "s/^$1=//p" "$CONFIG_FILE" | tail -n1
}

# Where the script is installed now, if anywhere.
current_script() {
    local s
    s=$(config_get SCRIPT)
    if [[ -n $s && -e $s ]]; then printf '%s' "$s"; return; fi
    s=$(command -v "$NAME" 2>/dev/null || true)
    if [[ -n $s ]]; then printf '%s' "$s"; return; fi
    if [[ -e $LEGACY_SCRIPT ]]; then printf '%s' "$LEGACY_SCRIPT"; fi
}

dms_ipc() { timeout 5 dms ipc call "$@" 2>/dev/null; }

# --- checks ------------------------------------------------------------------

check_requirements() {
    local -a missing_pkgs=() problems=()
    local entry cmds pkg c

    info "Checking the session"
    if [[ -n ${NIRI_SOCKET-} || ${XDG_CURRENT_DESKTOP-} == *niri* ]]; then
        ok "Niri"
    else
        problems+=("Niri isn't running (only Niri with DankMaterialShell is supported)")
    fi
    if ! command -v dms >/dev/null; then
        problems+=("DankMaterialShell isn't installed (no 'dms' command)")
    elif ! dms_ipc plugins list >/dev/null; then
        problems+=("DankMaterialShell isn't running (dms ipc doesn't answer)")
    else
        local version
        version=$(dms version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
        version=${version#v}
        if [[ -n $version ]] && ! printf '1.5\n%s\n' "$version" | sort -VC; then
            problems+=("DankMaterialShell $version is too old; the plugin needs 1.5 or newer")
        else
            ok "DankMaterialShell ${version:-(version unknown)}"
        fi
    fi
    if systemctl --user show-environment >/dev/null 2>&1; then
        ok "systemd user session"
    else
        problems+=("no systemd user session (systemctl --user doesn't work)")
    fi
    if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1))); then
        ok "bash $BASH_VERSION"
    else
        problems+=("bash $BASH_VERSION is too old; 5.1 or newer is needed")
        missing_pkgs+=(bash)
    fi

    info "Checking dependencies"
    local -a deps=(
        "jq:jq" "curl:curl" "readelf:binutils" "file:file" "openssl:openssl"
        "notify-send:libnotify" "gdbus:glib2" "systemd-run systemctl:systemd"
        "flock setsid column:util-linux" "pgrep:procps-ng"
        "update-desktop-database:desktop-file-utils"
        "sha1sum sha256sum base64 od dd timeout realpath stat:coreutils"
        "awk:gawk" "sed:sed" "grep:grep"
    )
    local found=0
    for entry in "${deps[@]}"; do
        cmds=${entry%%:*} pkg=${entry#*:}
        local -a absent=()
        for c in $cmds; do
            if command -v "$c" >/dev/null; then found=$((found + 1)); else absent+=("$c"); fi
        done
        if ((${#absent[@]})); then
            printf '    %s✗%s %s %s(package %s)%s\n' "$R" "$Z" "${absent[*]}" "$D" "$pkg" "$Z"
            missing_pkgs+=("$pkg")
        fi
    done
    if ((${#missing_pkgs[@]} == 0)); then ok "all $found required commands"; fi
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
        ok "gh (logged in: GitHub checks get a higher rate limit)"
    else
        note "${D}optional: gh, logged in, raises the GitHub rate limit for update checks${Z}"
    fi

    if ((${#problems[@]} == 0 && ${#missing_pkgs[@]} == 0)); then
        return 0
    fi
    echo
    for c in "${problems[@]}"; do printf '%s✗%s %s\n' "$R" "$Z" "$c" >&2; done
    if ((${#missing_pkgs[@]})); then
        local pkgs
        pkgs=$(printf '%s\n' "${missing_pkgs[@]}" | sort -u | tr '\n' ' ')
        printf '%sMissing packages:%s %s\n' "$B" "$Z" "$pkgs" >&2
        if command -v pacman >/dev/null; then
            printf 'Install them with:\n  sudo pacman -S --needed %s\n' "$pkgs" >&2
        fi
    fi
    die "fix the above and run install.sh again; nothing was changed"
}

# --- questions ---------------------------------------------------------------

# Readline needs non-printing sequences in a prompt wrapped in \001...\002.
prompt_mark() { printf '\001%s\002?\001%s\002' "$B" "$Z"; }

# ask VAR "Question" default validator
ask() {
    local __var=$1 question=$2 default=$3 validator=$4 answer
    while :; do
        if ! read -e -r -p "$(prompt_mark) $question [$default]: " answer; then
            echo
            die "cancelled"
        fi
        answer=${answer:-$default}
        if "$validator" "$answer"; then
            printf -v "$__var" '%s' "$answer"
            return
        fi
    done
}

# The source files in this checkout; never install over or delete them.
is_source() {
    [[ -e $1 && ! -L $1 ]] || return 1
    local r
    r=$(realpath -- "$1")
    [[ $r == "$(realpath -- "$SRC_SCRIPT")" || $r == "$(realpath -- "$SRC_PLUGIN")" ]]
}

valid_bin_dir() {
    if [[ $(expand "$1") == "$REPO_DIR" ]]; then
        warn "that's this checkout; pick another directory (link mode links from here)"
        return 1
    fi
    valid_dir "$1"
}

valid_dir() {
    local d
    d=$(expand "$1")
    if [[ -e $d && ! -d $d ]]; then
        warn "$d exists and isn't a directory"
        return 1
    fi
    if [[ $d == / || $d == "$HOME" ]]; then
        warn "pick a dedicated directory, not $d"
        return 1
    fi
}

valid_terminal() {
    if command -v "$1" >/dev/null; then return 0; fi
    warn "'$1' isn't an installed command"
    return 1
}

valid_mode() {
    case $1 in copy | link) return 0 ;; esac
    warn "answer copy or link"
    return 1
}

valid_yn() {
    case ${1,,} in y | yes | n | no) return 0 ;; esac
    warn "answer y or n"
    return 1
}

# --- install -----------------------------------------------------------------

do_install() {
    [[ -f $SRC_SCRIPT && -f $SRC_PLUGIN/plugin.json ]] || die "run install.sh from a complete checkout of the repository"
    check_requirements
    echo

    local old_script def_bin def_apps def_term def_mode def_login
    old_script=$(current_script)
    if [[ -n $old_script ]] && is_source "$old_script"; then old_script=''; fi
    def_bin=$HOME/.local/bin
    if [[ -n $old_script ]]; then def_bin=$(dirname -- "$old_script"); fi
    def_apps=$(config_get INSTALL_DIR)
    def_apps=${def_apps:-$HOME/Applications}
    def_term=$(config_get TERMINAL)
    if [[ -z $def_term ]]; then
        local t
        for t in "${TERMINAL-}" ghostty foot kitty alacritty wezterm; do
            if [[ -n $t ]] && command -v "$t" >/dev/null; then def_term=$t; break; fi
        done
    fi
    def_mode=copy
    if [[ -n $old_script && -L $old_script ]]; then def_mode="link"; fi
    def_login=y
    if [[ -n $old_script && -e $UNIT_FILE ]] && ! systemctl --user is-enabled --quiet "$UNIT_NAME" 2>/dev/null; then
        def_login=n
    elif [[ -n $old_script && ! -e $UNIT_FILE ]]; then
        def_login=n
    fi

    if [[ -n $old_script ]]; then
        info "Found an existing install at $(tildify "$old_script"); its settings are the defaults"
    fi
    info "Press Enter to accept the default in brackets"
    local bin_dir apps_dir terminal mode login
    ask bin_dir "Where should the $NAME command go?" "$(tildify "$def_bin")" valid_bin_dir
    bin_dir=$(expand "$bin_dir")
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) warn "$(tildify "$bin_dir") is not on your PATH; add it to run '$NAME' by name" ;;
    esac
    ask apps_dir "Where should AppImages be installed?" "$(tildify "$def_apps")" valid_dir
    apps_dir=$(expand "$apps_dir")
    ask terminal "Terminal for update progress (without the bar plugin) and logs?" "${def_term:-ghostty}" valid_terminal
    ask mode "Copy the files, or link them to this checkout? (copy/link)" "$def_mode" valid_mode
    ask login "Check for updates when you log in? (y/n)" "$def_login" valid_yn
    login=${login,,}
    login=${login:0:1}

    local dest=$bin_dir/$NAME how
    if [[ $mode == link ]]; then how="symlink to $(tildify "$REPO_DIR")"; else how=copy; fi
    local -a stale=()
    local s
    for s in "$old_script" "$LEGACY_SCRIPT"; do
        if [[ -n $s && -e $s && $s != "$dest" ]] && ! is_source "$s"; then
            if [[ ! " ${stale[*]-} " == *" $s "* ]]; then stale+=("$s"); fi
        fi
    done

    echo
    info "Summary"
    printf '    %-13s %s (%s)\n' "Command:" "$(tildify "$dest")" "$how"
    printf '    %-13s %s\n' "Apps:" "$(tildify "$apps_dir")/<id>/"
    printf '    %-13s %s\n' "Terminal:" "$terminal"
    printf '    %-13s %s\n' "Login check:" "$([[ $login == y ]] && echo "yes ($UNIT_NAME)" || echo no)"
    printf '    %-13s %s (%s)\n' "DMS plugin:" "$(tildify "$PLUGIN_DEST")" "$how"
    printf '    %-13s %s\n' "Config:" "$(tildify "$CONFIG_FILE")"
    for s in "${stale[@]}"; do printf '    %-13s %s\n' "Removes:" "$(tildify "$s") (previous install)"; done
    printf '    %sApp data, menu entries and state stay in ~/.local/share and ~/.local/state.%s\n' "$D" "$Z"
    local go
    read -e -r -p "$(prompt_mark) Proceed? [Y/n]: " go || die "cancelled"
    [[ -z $go || ${go,,} == y* ]] || die "cancelled; nothing was changed"

    echo
    info "Installing $NAME"
    mkdir -p -- "$bin_dir"
    if is_source "$dest" || is_source "$PLUGIN_DEST"; then die "refusing to replace the checkout's own files"; fi
    rm -f -- "$dest"
    if [[ $mode == link ]]; then
        chmod +x -- "$SRC_SCRIPT"
        ln -s -- "$SRC_SCRIPT" "$dest"
    else
        install -m755 -- "$SRC_SCRIPT" "$dest"
    fi
    ok "$(tildify "$dest")"
    for s in "${stale[@]}"; do
        rm -f -- "$s"
        ok "removed $(tildify "$s")"
    done

    mkdir -p -- "$PLUGINS_DIR"
    rm -rf -- "$PLUGIN_DEST"
    if [[ $mode == link ]]; then ln -s -- "$SRC_PLUGIN" "$PLUGIN_DEST"; else cp -r -- "$SRC_PLUGIN" "$PLUGIN_DEST"; fi
    ok "$(tildify "$PLUGIN_DEST")"

    mkdir -p -- "$apps_dir"
    "$dest" --config install_dir "$apps_dir" >/dev/null 2>&1 || die "couldn't save the apps directory"
    "$dest" --config terminal "$terminal" >/dev/null 2>&1 || die "couldn't save the terminal"
    ok "config: apps in $(tildify "$apps_dir"), terminal $terminal"

    # Records the script path, points menu entries at it, sets up the login check.
    local -a setup_args=(--setup)
    if [[ $login != y ]]; then setup_args+=(--no-login-check); fi
    "$dest" "${setup_args[@]}" >/dev/null || die "'$NAME --setup' failed"
    ok "menu entries point at $(tildify "$dest")"
    if [[ $login == y ]]; then ok "login update check enabled"; else ok "login update check off"; fi

    enable_plugin
    echo
    info "Done. Try: $NAME --help"
}

enable_plugin() {
    local status=''
    dms_ipc plugin-scan scan >/dev/null || true
    for _ in {1..10}; do
        status=$(dms_ipc plugin-scan list | awk -v id="$PLUGIN_ID" '$1 == id { print $2 }' || true)
        if [[ -n $status ]]; then break; fi
        sleep 0.5
    done
    if [[ -z $status ]]; then
        warn "DMS didn't find the plugin; enable 'AppImage Updates' in DMS Settings → Plugins"
        return 0
    fi
    if [[ $status != loaded ]]; then dms_ipc plugins enable "$PLUGIN_ID" >/dev/null || true; fi
    # Enabling can reuse DMS's cached copy of the plugin; reload reads the new files.
    dms_ipc plugins reload "$PLUGIN_ID" >/dev/null || true
    for _ in {1..10}; do
        if [[ $(dms_ipc "$NAME" ping) == ok ]]; then break; fi
        sleep 0.5
    done
    if [[ $(dms_ipc "$NAME" ping) == ok ]]; then
        ok "DMS plugin loaded"
    else
        warn "the DMS plugin didn't start; check DMS Settings → Plugins"
        return 0
    fi
    if [[ -f $DMS_SETTINGS ]] && jq -e --arg id "$PLUGIN_ID" '
            [.barConfigs[]? | (.leftWidgets, .centerWidgets, .rightWidgets)[]?
             | if type == "object" then .id else . end] | index($id) != null' "$DMS_SETTINGS" >/dev/null 2>&1; then
        ok "the bar already has the AppImage Updates widget"
    else
        echo
        info "One manual step: add ${B}AppImage Updates${Z} to the bar in DMS Settings → Dank Bar"
        note "(the pill only shows while updates run or have finished)"
    fi
}

# --- uninstall ---------------------------------------------------------------

do_uninstall() {
    local script s
    script=$(current_script)
    info "This removes:"
    for s in "$script" "$LEGACY_SCRIPT"; do
        if [[ -n $s && -e $s ]]; then note "$(tildify "$s")"; fi
    done
    if [[ -e $PLUGIN_DEST ]]; then note "$(tildify "$PLUGIN_DEST") (DMS plugin)"; fi
    if [[ -e $UNIT_FILE ]]; then note "$(tildify "$UNIT_FILE") (login update check)"; fi
    if [[ -e $CONFIG_FILE ]]; then note "$(tildify "$CONFIG_FILE")"; fi
    info "and keeps:"
    note "your installed AppImages ($(tildify "$(config_get INSTALL_DIR || true)")); their menu entries will start them directly"
    note "$(tildify "$DATA_DIR") and $(tildify "$STATE_DIR"), so reinstalling picks them up again"
    local go
    read -e -r -p "$(prompt_mark) Uninstall? [y/N]: " go || die "cancelled"
    [[ ${go,,} == y* ]] || die "cancelled; nothing was changed"

    if [[ -n $script && -x $script ]]; then
        if "$script" --_detach-menu >/dev/null 2>&1; then
            ok "menu entries now start the AppImages directly"
        else
            warn "couldn't update the menu entries; they still point at $(tildify "$script")"
        fi
    fi
    systemctl --user stop 'installappimage-*' >/dev/null 2>&1 || true
    if [[ -e $UNIT_FILE ]]; then
        systemctl --user disable --quiet "$UNIT_NAME" 2>/dev/null || true
        rm -f -- "$UNIT_FILE"
        systemctl --user daemon-reload
        ok "login update check removed"
    fi
    if [[ -e $PLUGIN_DEST || -L $PLUGIN_DEST ]]; then
        if command -v dms >/dev/null; then dms_ipc plugins disable "$PLUGIN_ID" >/dev/null || true; fi
        rm -rf -- "$PLUGIN_DEST"
        ok "DMS plugin removed (remove its widget from the bar in DMS Settings if you added it)"
    fi
    for s in "$script" "$LEGACY_SCRIPT"; do
        if [[ -n $s && ( -e $s || -L $s ) ]] && ! is_source "$s"; then
            rm -f -- "$s"
            ok "removed $(tildify "$s")"
        fi
    done
    if [[ -e $CONFIG_FILE ]]; then
        rm -f -- "$CONFIG_FILE"
        rmdir -- "${CONFIG_FILE%/*}" 2>/dev/null || true
        ok "removed $(tildify "$CONFIG_FILE")"
    fi
    info "Uninstalled"
}

main() {
    sanitize_env
    case ${1-} in
        '') do_install ;;
        --uninstall) do_uninstall ;;
        -h | --help) sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
        *) die "unknown option: $1 (use --uninstall, or no option to install)" ;;
    esac
}

main "$@"
