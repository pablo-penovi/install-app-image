# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The project has no tagged releases yet, so entries are grouped by date.

## [Unreleased]

### Added

- Animated GIFs in the README showing the update notification, the bar pill and the progress panel.

## 2026-11-12

### Added

- This changelog.
- `--setup` is now listed in the README's usage section.

### Fixed

- DMS no longer crashes when update progress is cleared. Quickshell aborted if a progress file's watcher was destroyed while a read was failing, which happened when the file was deleted. Clearing, automatic or through **Clear finished**, now stops watching the files before deleting them.

## 2026-11-08

### Fixed

- **Clear finished**, and the automatic clear after successful updates, now work for apps whose id contains a dot (for example `knossos.net`). Before, the bar pill never went away for them.

## 2026-11-03

### Added

- `installappimage`: installs AppImages with a menu entry and icon, lists and removes them, and updates them from GitHub releases, Electron update feeds or `.zsync` URLs, verifying every download.
- DMS bar plugin **AppImage Updates**, showing each update's progress, step and log lines, with **Retry** and **Clear finished**.
- `install.sh`: checks the session and dependencies, then installs, upgrades or uninstalls the command, the plugin and the login check.
- Every app start checks that app for updates in the background, and a notification offers **Update now** when one is available.
- MIT license.

### Changed

- The command was renamed from `installappimage.sh` to `installappimage`.
- At install, menu entries not made by the script that clash with the new one are backed up and replaced by default (Enter accepts).
