# Recording the README GIFs

How `docs/notification.gif` and `docs/progress.gif` were made. Following these steps avoids the problems hit the first time.

## Setup

- **Tools:** `wf-recorder` and `ffmpeg`. `grim`, `gifski` and ImageMagick aren't installed and aren't needed: `ffmpeg` extracts still frames and builds the GIFs. There's no input tool (`ydotool`, `dotool`), so nothing can be clicked. Drive the UI with `dms ipc call installappimage toggle` (opens or closes the panel), or ask the user to install one if a GIF needs a click.
- **Clean environment first:** the agent's shell runs inside an AppImage (T3 Code) and inherits `LD_LIBRARY_PATH=/tmp/.mount_*/usr/lib`. Run `unset LD_LIBRARY_PATH LD_PRELOAD` at the start of every recording command, or `notify-send` fails with `undefined symbol: notify_notification_get_activation_app_launch_context`.
- **Screen:** one output, `DP-2`, 1920×1080 at scale 1. The DMS bar is at the top, and the plugin's pill is its rightmost widget.

## Simulating updates

Use [`fake-update.sh`](fake-update.sh) to simulate updates, never a real one. Take app ids, names and icons from `~/.local/share/installappimage/apps/<id>.json` so the GIFs show real apps:

```sh
I=~/.local/share/icons/installappimage
docs/demo/fake-update.sh paseo Paseo $I/paseo.png v0.9.4 140 Paseo-0.9.4-x86_64.AppImage 10 &
```

The last argument sets the speed in MB per 0.5 s. A finished run leaves its file until the plugin auto-clears it. After stopping a run early, delete `~/.local/state/installappimage/progress/<id>.json`, and confirm the directory is empty when done.

For the "update available" notification, send the same text and buttons as `cmd_notify_update` in `installappimage`. `-w` blocks until the notification closes, and `-p` prints its id so it can be closed:

```sh
notify-send -a "AppImage Updates" -p -w -t 0 -i $I/paseo.png \
  -A update="Update now" -A dismiss="Dismiss" -- \
  "Paseo update available" "Version v0.9.4 is ready to install." > nid.txt &
# later:
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification "$(head -1 nid.txt)"
```

DMS drops a notification identical to one shown in the last 5 seconds, so wait at least that long between takes.

## Recording

Record the whole output, run the scenario, then stop with SIGINT:

```sh
wf-recorder -D -r 20 -o DP-2 -f take.mp4 >/dev/null 2>&1 & R=$!
# ... scenario ...
kill -INT $R; wait $R
```

`-D -r 20` is required. Without it, wf-recorder records only on screen damage: a few seconds give about 9 frames, and the panel can be missing from them. Open the panel *during* the recording, about a second after the first progress file appears.

Scenarios used:

- **notification.gif:** idle bar, then the notification for about 4.5 s, then close it and start one fake update so the pill appears and counts up. About 12 s.
- **progress.gif:** two fake updates started 0.6 s apart, the panel opened at about 2 s, then left running through completion, the 3 s auto-clear and the pill disappearing. About 19 s.

## Cropping and converting

The user wants **tight crops**: the pill, the panel or notification, and as little desktop as possible. Crops that fit this screen (`w:h:x:y`):

| GIF | Crop |
|---|---|
| notification | `420:230:1500:0` |
| progress (two entries) | `456:480:1464:0` |

The panel grows with each entry, so re-measure for a different number of apps. To measure, cut a contact sheet from the recording and look at it before converting:

```sh
ffmpeg -loglevel error -i take.mp4 -vf "fps=1,crop=480:540:1440:0,scale=240:-1,tile=7x3" sheet.png
```

Convert (trim with `-ss`/`-to` to drop the start and end):

```sh
ffmpeg -y -loglevel error -ss 0.6 -to 19.5 -i take.mp4 -filter_complex \
  "fps=12,crop=456:480:1464:0,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  docs/progress.gif
```

That gives about 300 KB to 1 MB per GIF. Check every GIF with a contact sheet (`fps=0.5,tile=Nx1`) before it goes in the README. Keep recordings and sheets in the scratchpad, not the repo.
