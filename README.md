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

`mpv` and `jq` are also used, and ship with Omarchy.

## License

MIT — see [LICENSE](LICENSE).

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
