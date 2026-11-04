# install-app-image

`installappimage` installs AppImages with a menu entry, keeps track of them, and keeps them up to date. It can list and remove the apps it installed, and it checks for updates at login. When an app with an update is launched, a notification offers to update it, and the update's progress shows in the DankMaterialShell (DMS) bar.

It supports [Niri](https://github.com/YaLTeR/niri) with [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) only. You're welcomed to adapt it to your own setup, the repo is under MIT license.

## Why use it

- **Simple:**
  - **Everything is plain text you can inspect.** The tool is one Bash script and a small DMS plugin. Each app gets one directory, one menu entry and one small JSON record.
  - **No new package format, store or database.** The AppImages themselves aren't modified.
- **Lightweight:**
  - **Nothing runs in the background.** Updates are checked by short jobs that run at login and when an app starts.
  - **No extra processes when idle.** Progress is shown by the shell you already run.
  - **No new dependencies to speak of:** it uses tools that are normally already installed, like `curl`, `jq` and `notify-send`.
- **Easy to use:**
  - **Install:** one command, `installappimage Foo.AppImage`. It sets up the menu entry and icon, and finds where updates come from or asks you once.
  - **Updates:** every app start checks for one, you hear about it while the app opens, and one click installs it with progress in the bar.
  - **Install and remove the tool:** a guided `./install.sh` sets it up. `./install.sh --uninstall` removes it and leaves your apps working.

## What it does

- **Install:** moves the AppImage to `~/Applications/<id>/<id>.AppImage` (the base directory can be changed) and extracts its menu entry and icon. The menu entry starts the app through `installappimage --run <id>`. If menu entries that weren't made by this script would clash with it, it offers to move them to a backup and use its own. Pressing Enter accepts.
- **Update info:** reads the update information embedded in the AppImage. If there is none, it asks where updates are published: a GitHub repository, an Electron update feed (`latest-linux.yml`) or a `.zsync` URL.
- **Update checks:** each app is checked for updates every time it starts, in the background, so the app isn't slowed down. A systemd user service also checks every app when you log in.
- **Launch:** if an update is available, a notification with **Update now** and **Dismiss** appears when the app starts, or as soon as the check finds the update. Clicking **Update now**, or the notification itself, starts the update. It appears on every launch until the app is updated, but an open one isn't duplicated.
- **Progress:** a DMS bar plugin shows each update's progress, current step and log lines, with **Retry** on failures. Without the plugin, updates open in a terminal window instead.
- **When it ends:** a notification reports the result. A failure includes the reason, with **Show log** and **Retry** buttons. Once every update has succeeded, the bar pill disappears after 3 seconds.

## Requirements

- **Session:** Niri, with DankMaterialShell 1.5 or later running, and a systemd user session.
- **Packages** (Arch names): bash 5.1 or later, coreutils, util-linux, jq, curl, binutils, file, openssl, desktop-file-utils, libnotify, glib2, systemd, procps-ng, gawk, sed and grep.
- **Optional:** `gh`, logged in. GitHub API calls use it, which allows more requests per hour.
- **A terminal:** used for update progress when the bar plugin isn't loaded, and for **Show log**. Ghostty, foot, kitty, Alacritty, WezTerm, GNOME Terminal and Console are supported, and anything that takes `-e COMMAND`.

## Installing

```sh
git clone https://github.com/pablo-penovi/install-app-image.git
cd install-app-image
./install.sh
```

`install.sh` first checks the session and the dependencies. If anything is missing, it lists all of it, prints the `pacman` command to install the missing packages, and stops without changing anything.

Then it asks five questions. Press Enter to accept the default in brackets:

| Question | Default |
|---|---|
| Where should the `installappimage` command go? | `~/.local/bin` |
| Where should AppImages be installed? | `~/Applications` |
| Terminal for update progress (without the bar plugin) and logs? | `$TERMINAL`, else the first of ghostty, foot, kitty, alacritty and wezterm found |
| Copy the files, or link them to this checkout? | `copy` |
| Check for updates when you log in? | `y` |

After a summary and confirmation, it does the following:

1. Installs the command and the DMS plugin, either as copies or as symlinks to the checkout. Symlinks make edits in the checkout take effect immediately.
2. Writes the config.
3. Points existing menu entries at the command.
4. Sets up the login check.
5. Enables and reloads the plugin in DMS.

If the bar doesn't have the **AppImage Updates** widget yet, add it in DMS Settings → Dank Bar. The pill stays hidden while no update is running or waiting to be cleared.

Running `./install.sh` again upgrades in place. The current settings become the defaults.

### Uninstalling

```sh
./install.sh --uninstall
```

This removes the command, the DMS plugin, the login check and the config. It keeps your AppImages, their menu entries, and the registry and state under `~/.local/share` and `~/.local/state`. The menu entries are rewritten to start the AppImages directly, so they keep working, and reinstalling picks everything up again.

## Usage

```sh
installappimage ~/Downloads/Foo-1.2.3-x86_64.AppImage   # install
installappimage Foo.AppImage --repo owner/repo           # updates from GitHub releases
installappimage Foo.AppImage --update-url https://example.com/linux/latest-linux.yml
installappimage --list
installappimage --update foo bar                         # or: --update all
installappimage --remove foo [--purge] [-y]
installappimage --check
installappimage --config                                 # show settings
installappimage --config install_dir ~/Apps
installappimage --config terminal foot
installappimage --help
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

**Update options:** `--ui auto` (the default) shows progress in the terminal when run from one. Otherwise it uses the DMS plugin if it's loaded, then a window of the configured terminal. `--ui tty` and `--ui none` force a mode.

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
| `~/.config/installappimage/config` | `INSTALL_DIR`, `TERMINAL`, and `SCRIPT` (the command's path, which the plugin uses for **Retry**) |
| `~/.local/share/installappimage/apps/<id>.json` | Registry: paths, update source, installed version and hashes |
| `~/.local/share/applications/<name>.desktop` | Menu entry, marked with `X-InstallAppImage-Id=<id>` |
| `~/.local/share/icons/installappimage/<id>.*` | Icon |
| `~/.local/state/installappimage/updates/<id>` | An update is available (written by `--check`) |
| `~/.local/state/installappimage/progress/<id>.json` | Update progress, read by the DMS plugin |
| `~/.local/state/installappimage/logs/<id>.log` | Log of the last update |
| `~/.local/state/installappimage/backup/` | Menu entries replaced at install |
| `~/.config/systemd/user/installappimage-check.service` | Login update check |

**Systemd units:** updates run as the transient unit `installappimage-update-<id>`, and the check at app start as `installappimage-launch-check-<id>`. Notifications that wait for a click run as `installappimage-notify-update-<id>` and `installappimage-notify-result-<id>`.

## DMS plugin

`dms-plugin/installAppImage` is a composite plugin with two parts:

- **Daemon:** watches `~/.local/state/installappimage/progress/` and shares its contents with the bar widget. It also reads the command's path from the config, and registers `dms ipc call installappimage ping|toggle|status|script`.
- **Bar widget:** a pill showing the overall percentage. Its panel lists each update with a progress bar, the current step, bytes downloaded and the last log lines. Failed updates get **Retry**, and **Clear finished** removes finished entries.

`toggle` opens or closes the panel, so it can be bound to a key.

## Limitations

- **Updates always download the whole file.** Arch's `zsync` (0.6) only supports HTTP, and GitHub serves HTTPS only. `.zsync` files are still used to detect new versions and verify downloads.
- **Type 1 AppImages are not supported.**
- **Launching the `.AppImage` directly** (not through the menu entry) skips the update check and notification.
- **Running the script from inside another AppImage** (for example, a terminal packaged as one) passes that AppImage's libraries on. The script strips `/.mount_*` entries from `LD_LIBRARY_PATH`, `LD_PRELOAD` and `PATH` before running anything.

## License

MIT. See [LICENSE](LICENSE).
