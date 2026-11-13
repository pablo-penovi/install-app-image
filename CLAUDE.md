# install-app-image

`installappimage` (one Bash script) installs and updates AppImages. `dms-plugin/installAppImage` shows update progress in the DankMaterialShell bar, and `install.sh` sets both up. The README documents user-facing behaviour, so keep it matching the code.

- **Changelog:** record every user-visible change in `CHANGELOG.md` under `## [Unreleased]`. There are no tagged releases, so finished entries are grouped by date.
- **Shell environment:** this agent usually runs inside an AppImage and inherits its `LD_LIBRARY_PATH`. Run `unset LD_LIBRARY_PATH LD_PRELOAD` before calling system tools like `notify-send` directly. The script cleans its own environment.
- **GIFs, screenshots and screen recordings** of the tool (for the README or anything else): follow [docs/demo/RECORDING.md](docs/demo/RECORDING.md).
