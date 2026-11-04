# install-app-image

`installappimage.sh` installs AppImages with a menu entry, keeps track of them, and keeps them up to date. It can list and remove the apps it installed, and it checks for updates at login. When an app with an update is launched, a notification offers to update it, and the update's progress shows in the DankMaterialShell (DMS) bar.

## What it does

- **Install:** moves the AppImage to `~/Applications/<id>/<id>.AppImage` (the base directory can be changed) and extracts its menu entry and icon. The menu entry starts the app through `installappimage.sh --run <id>`.
- **Update info:** reads the update information embedded in the AppImage. If there is none, it asks where updates are published: a GitHub repository, an Electron update feed (`latest-linux.yml`) or a `.zsync` URL.
- **Login check:** a systemd user service checks every app for updates when you log in.
- **Launch:** if an update is available, launching the app shows a notification with **Update now** and **Dismiss**. Clicking **Update now**, or the notification itself, starts the update.
- **Progress:** a DMS bar plugin shows each update's progress, current step and log lines, with **Retry** on failures. Without the plugin, updates open in a Ghostty window instead.
- **When it ends:** a notification reports the result. A failure includes the reason, with **Show log** and **Retry** buttons. Once every update has succeeded, the bar pill disappears after 3 seconds.

## Requirements

- **Required:** bash, coreutils, util-linux (`flock`, `setsid`), `jq`, `curl`, binutils (`readelf`), `file`, `openssl`, desktop-file-utils, libnotify (`notify-send`), glib2 (`gdbus`), and systemd (user session).
- **Optional:**
  - `gh`: GitHub API calls use it when logged in, which allows more requests per hour.
  - DankMaterialShell 1.5 or later: needed for the bar plugin.
  - `ghostty`: used for updates when the plugin isn't available, and for **Show log**.

## Setup

```sh
install -Dm755 installappimage.sh ~/.local/bin/installappimage.sh

# DMS plugin
mkdir -p ~/.config/DankMaterialShell/plugins
cp -r dms-plugin/installAppImage ~/.config/DankMaterialShell/plugins/
dms ipc call plugin-scan scan
dms ipc call plugins enable installAppImage

# login update check (also done automatically by the first install)
installappimage.sh --setup
```

Then add **AppImage Updates** to the bar in DMS Settings → Dank Bar. The pill stays hidden while no update is running or waiting to be cleared.

## Usage

```sh
installappimage.sh ~/Downloads/Foo-1.2.3-x86_64.AppImage   # install
installappimage.sh Foo.AppImage --repo owner/repo           # updates from GitHub releases
installappimage.sh Foo.AppImage --update-url https://example.com/linux/latest-linux.yml
installappimage.sh --list
installappimage.sh --update foo bar                         # or: --update all
installappimage.sh --remove foo [--purge] [-y]
installappimage.sh --check
installappimage.sh --config install_dir ~/Apps
installappimage.sh --help
```

**Install options:**

| Option | Effect |
|---|---|
| `--name ID` | Choose the id. The default is the app's name, lowercased. |
| `--dir DIR` | Install under `DIR` instead of the configured directory. |
| `--repo OWNER/REPO` | Get updates from this GitHub repository's releases. Also accepts a github.com URL. |
| `--update-url URL` | Get updates from an Electron feed or a `.zsync` URL. |
| `--no-update-info` | Don't ask for an update source. |
| `-y` | Don't ask before replacing menu entries that weren't made by this script. They are backed up first. |

**Update options:** `--ui auto` (the default) shows progress in the terminal when run from one. Otherwise it uses the DMS plugin if it's loaded, then a Ghostty window. `--ui tty` and `--ui none` force a mode.

`--remove --purge` also offers to delete the app's data directories (`~/.config/<Name>` and similar), asking about each one.

## Update sources

| Kind | Where it comes from | How a new version is detected |
|---|---|---|
| `gh-releases-zsync\|owner\|repo\|latest\|pattern.zsync` | Embedded in the AppImage, or built from a GitHub repo that publishes `.zsync` files | SHA-1 in the `.zsync` header |
| `gh-releases-direct\|owner\|repo\|latest\|pattern` | Built from a GitHub repo without `.zsync` files | SHA-256 digest of the GitHub asset, or the release tag |
| `zsync\|URL` | Embedded, or `--update-url …/file.zsync` | SHA-1 in the `.zsync` header |
| `electron-updater\|URL` | `--update-url …/latest-linux.yml` | SHA-512 in the feed |

**GitHub sources:** when you give a GitHub repository, the script picks the latest release's x86_64 AppImage and turns its file name into a pattern for future releases. For example, `foo-1.2.3-linux-x86_64.AppImage` becomes `foo-*-linux-x86_64.AppImage`, and you can edit the pattern before it's saved. The installed release is identified by matching the file's SHA-256 against the release assets.

**Verification:** every download is checked against the size and checksums the source provides before it replaces the installed file.

## Files

| Path | Contents |
|---|---|
| `~/.config/installappimage/config` | `INSTALL_DIR=…` |
| `~/.local/share/installappimage/apps/<id>.json` | Registry: paths, update source, installed version and hashes |
| `~/.local/share/applications/<name>.desktop` | Menu entry, marked with `X-InstallAppImage-Id=<id>` |
| `~/.local/share/icons/installappimage/<id>.*` | Icon |
| `~/.local/state/installappimage/updates/<id>` | An update is available (written by `--check`) |
| `~/.local/state/installappimage/progress/<id>.json` | Update progress, read by the DMS plugin |
| `~/.local/state/installappimage/logs/<id>.log` | Log of the last update |
| `~/.local/state/installappimage/backup/` | Menu entries replaced at install |
| `~/.config/systemd/user/installappimage-check.service` | Login update check |

**Systemd units:** updates run as the transient unit `installappimage-update-<id>`. Notifications that wait for a click run as `installappimage-notify-update-<id>` and `installappimage-notify-result-<id>`.

## DMS plugin

`dms-plugin/installAppImage` is a composite plugin with two parts:

- **Daemon:** watches `~/.local/state/installappimage/progress/` and shares its contents with the bar widget. It also registers `dms ipc call installappimage ping|toggle|status`.
- **Bar widget:** a pill showing the overall percentage. Its panel lists each update with a progress bar, the current step, bytes downloaded and the last log lines. Failed updates get **Retry**, and **Clear finished** removes finished entries.

`toggle` opens or closes the panel, so it can be bound to a key.

## Limitations

- **Updates always download the whole file.** Arch's `zsync` (0.6) only supports HTTP, and GitHub serves HTTPS only. `.zsync` files are still used to detect new versions and verify downloads.
- **Type 1 AppImages are not supported.**
- **Launching the `.AppImage` directly** (not through the menu entry) skips the update notification.
- **Running the script from inside another AppImage** (for example, a terminal packaged as one) passes that AppImage's libraries on. The script strips `/.mount_*` entries from `LD_LIBRARY_PATH`, `LD_PRELOAD` and `PATH` before running anything.
