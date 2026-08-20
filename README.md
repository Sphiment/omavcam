# omavcam

Use an Android phone as a virtual webcam on Linux — as a first-class
[Omarchy](https://omarchy.org) shell plugin.

`scrcpy` can already pipe a phone's camera or screen into a `v4l2loopback`
node, which Meet, Zoom, OBS, and Discord then see as an ordinary webcam.
omavcam wraps that in a bar widget: one click to start, a keyboard-driven panel
to pick the device, camera, and resolution, and a movable floating preview of
exactly what the other side sees.

> **Status: in development.** See [ROADMAP.md](ROADMAP.md) for what is built and
> what is coming.

## Install

```bash
omarchy plugin add https://github.com/Sphiment/omavcam.git --enable
```

Then place it on the bar:

```bash
omarchy bar move sphiment.omavcam
```

## Requirements

| Package | Why |
|---|---|
| `scrcpy` | Captures the phone's camera or screen |
| `android-tools` | `adb`, for talking to the phone |
| `v4l2loopback-dkms` | The kernel module backing the virtual camera node |

You do not have to install these by hand — omavcam detects what is missing and
offers to install it from the panel, using Omarchy's own package installer.
`v4l2loopback-dkms` is built by DKMS, so the headers for your running kernel
(`linux-headers`, or the matching package for `linux-lts`, `linux-zen`, and so
on) are installed alongside it.

`mpv` and `jq` are also used, and ship with Omarchy.

To do it from a terminal instead:

```bash
bin/omavcam doctor    # what is missing, and whether it blocks capture
bin/omavcam setup     # install dependencies and configure the virtual camera
```

`setup` writes two files, both marked as managed by omavcam:

| File | Contents |
|---|---|
| `/etc/modprobe.d/omavcam.conf` | `video_nr=42 card_label="omavcam" exclusive_caps=1 max_openers=10` |
| `/etc/modules-load.d/omavcam.conf` | `v4l2loopback`, so the node returns after a reboot |

`exclusive_caps=1` means the node only advertises capture capability while
something is writing to it, so "omavcam" appears in camera pickers exactly when
you are streaming rather than sitting in every dropdown. Set `OMAVCAM_VIDEO_NR`
if `/dev/video42` is already taken on your machine.

## License

MIT — see [LICENSE](LICENSE).

## Using it

Click the bar icon to open the panel; right-click the icon to start or stop
capture without opening anything. Inside the panel:

| Key | Does |
|---|---|
| `s` | Start or stop the virtual camera |
| `f` / `b` | Switch to the front or back camera |
| `p` | Show or hide the preview window |
| `+` / `-` | Step the preview through small, medium, large, original |
| `r` | Re-read the phone, its cameras, and the system state |
| `esc` | Close |

### The preview window

The preview is an ordinary floating window: pinned above everything, movable
and resizable like any other, and it takes no focus when it appears. Three size
presets scale from your monitor's height, so the same preset looks the same on
a 1080p screen and a 4K one, and the window always keeps the stream's aspect
ratio.

Sizes are `small`, `medium`, `large`, and `original`. The first three scale from
your monitor's height. **`original` is the stream's real pixel size, and is not
scaled down** — a phone that out-resolves your monitor gives a window larger
than the screen, on purpose. It is placed at the top-left corner so you can drag
it from there.

There are two things it can show:

| Source | Shows | Trade-off |
|---|---|---|
| **Virtual cam** (default) | The `/dev/video42` node itself | Exactly the frames the other side receives — same crop, same orientation, same lag. Independent of the capture, so it opens and closes freely. |
| **scrcpy window** | scrcpy's own window | No second process, and you can tap the phone from your desktop. It is part of the capture, so turning it on or off restarts the stream. |

omavcam applies its Hyprland rules at runtime with `hyprctl`, so installing it
never writes into your Hyprland config.

Changes apply to a running stream. scrcpy fixes the camera, resolution and
frame rate when it launches, so none of them can be altered on a live stream —
omavcam re-establishes the capture with the new setting instead of making you
stop and start by hand. Expect a couple of seconds during which the virtual
camera goes away and comes back; a meeting app will usually pick it straight
back up, but it is a visible blip, not a seamless switch.

Resolutions belong to a camera, not to the phone, so switching cameras drops a
resolution the new one does not offer and falls back to its default.

Your camera and resolution choices are saved on the widget's entry in
`~/.config/omarchy/shell.json`, so they survive a restart. Everything the panel
exposes is also available from `omavcam` on the command line.

## Development

```bash
git clone https://github.com/Sphiment/omavcam.git
cd omavcam
omarchy plugin validate .          # same checks the shell enforces at load

# The shell refuses symlinks inside a plugin folder, so sync rather than link:
rsync -a --delete --exclude '.git' --exclude '.github' ./ \
  ~/.config/omarchy/plugins/sphiment.omavcam/
```

Saving a file under `~/.config/omarchy/plugins/` hot-reloads the plugin's code.
**Adding a bar widget for the first time needs a full `omarchy-restart-shell`** —
hot reload picks up code changes to plugins the bar already knows about, not a
newly registered widget.

QML errors and plugin reloads show up in `journalctl --user -f`.
