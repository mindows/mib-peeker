# mib-peeker

A little character that sits on the top-right corner of the active Hyprland window: a cat, a corgi or a peeking mecha head, drawn as flat illustrations with thick outlines.

It is a standalone [Quickshell](https://quickshell.org) overlay: a click-through layer surface on every output that tracks the active window over Hyprland IPC. It cannot follow a window frame by frame (only the compositor can), so it fades the sprite out whenever the window moves or resizes and fades it back in once the window has settled.

## Run

```sh
nix shell nixpkgs#quickshell -c quickshell -p ~/dev/mib-peeker/shell.qml
```

Or with `quickshell` installed, start it from Hyprland (`hyprland.lua`):

```lua
hl.exec_once("qs -p ~/dev/mib-peeker/shell.qml")
```

## Controls

Everything goes through Quickshell IPC (`qs -p ~/dev/mib-peeker ipc call peeker <fn>`):

| Function       | What it does                                              |
| -------------- | --------------------------------------------------------- |
| `left`/`right` | Move the sprite 12 px along the window's top edge         |
| `reset`        | Put it back near the corner                               |
| `use <name>`   | Switch sprite: `cat`, `corgi`, `mecha`, or any SVG here   |

Position and sprite are remembered across restarts.

Example binds:

```lua
local peeker = "qs -p ~/dev/mib-peeker ipc call peeker "
hl.bind(mainMod .. " + ALT + left",  hl.dsp.exec_cmd(peeker .. "left"),  { repeating = true })
hl.bind(mainMod .. " + ALT + right", hl.dsp.exec_cmd(peeker .. "right"), { repeating = true })
```

## Sprites

Each sprite is an SVG next to `shell.qml` on a shared 200×120 canvas, with the window's top edge at y = 70: everything above that line sits on the window border, everything below hangs over the window. Size and timing knobs (`catWidth`, per-sprite `spriteWidths`, `settleMs`, fade durations) are at the top of `shell.qml`.

## Limits

The overlay sits on the top layer, so it draws over the bar and over any window that overlaps the corner. Doing better needs a Hyprland plugin (a real window decoration).
