// peeker: a cat that lies on the top-right corner of the active Hyprland window.
//
// Run:  quickshell -p /path/to/peeker/shell.qml
//
// The overlay is a click-through, full-output layer surface. It cannot follow a
// window frame-by-frame (only the compositor can), so instead it hides the cat
// whenever the active window's geometry changes and fades it back in once the
// geometry has stayed put for `settleMs`.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ── tunables ────────────────────────────────────────────────────────────
    property int catWidth: 65           // default sprite width in logical px; height follows the SVG aspect
    // per-sprite overrides: mecha only fills the right half of its frame, so it needs more
    property var spriteWidths: ({ mecha: 98 })
    property int defaultInset: 6        // initial gap between the cat's right end and the window's right edge
    property int nudgeStep: 12          // px per `peeker left/right` IPC call
    property int settleMs: 550          // geometry must be unchanged this long before showing
    property int fadeInMs: 1400
    property int fadeOutMs: 140
    property int dropPx: 4              // the cat settles down onto the edge by this much while fading in
    property int fastPollMs: 60         // while waiting for a window to settle
    property int idlePollMs: 400        // while shown; catches resizes, which emit no IPC event
    property bool hideOnFloating: false

    // Sprite geometry (cat.svg, corgi.svg): 200x120 viewBox, window top edge at y = 70.
    readonly property real svgW: 200
    readonly property real svgH: 120
    readonly property real svgLedgeY: 70
    readonly property real spriteWidth: spriteWidths[saved.sprite] || catWidth
    readonly property real catScale: spriteWidth / svgW
    readonly property real catHeight: svgH * catScale

    // ── tracked state ───────────────────────────────────────────────────────
    property int borderSize: 0
    property var target: null           // { x, y, w, h } in global layout coords, or null
    property string lastKey: ""
    property real stableSince: 0
    property bool shown: false
    // where the cat is drawn (global layout coords of the window corner it sits on)
    property real anchorRight: 0
    property real anchorTop: 0
    property real anchorWidth: 0
    // saved.rightInset clamped so the cat stays on the window's top edge
    readonly property real rightInset: Math.max(0, Math.min(saved.rightInset, anchorWidth - spriteWidth))

    function now() { return Date.now(); }

    // Positive dx moves the cat right. The stored inset is clamped to the current
    // window so every key press visibly moves it.
    function nudge(dx) {
        saved.rightInset = Math.round(Math.max(0, Math.min(rightInset - dx, anchorWidth - spriteWidth)));
        glide.restart();
    }

    function poke() {
        // Something happened: look again soon, and keep looking fast until it settles.
        pollTimer.interval = fastPollMs;
        if (!activeProc.running) activeProc.running = true;
    }

    function onActiveWindow(win) {
        let next = null;
        if (win && win.address && win.mapped && !win.hidden
                && win.fullscreen === 0
                && !(hideOnFloating && win.floating)) {
            next = { x: win.at[0], y: win.at[1], w: win.size[0], h: win.size[1] };
        }
        const key = next
            ? `${win.address}|${win.workspace.id}|${next.x},${next.y},${next.w},${next.h}`
            : "";

        if (key !== lastKey) {
            lastKey = key;
            stableSince = now();
            target = next;
            shown = false;                      // fast fade-out at the old spot
            pollTimer.interval = fastPollMs;
            return;
        }

        if (!target) {
            pollTimer.interval = idlePollMs;
            return;
        }

        if (!shown && now() - stableSince >= settleMs) {
            anchorRight = target.x + target.w + borderSize;
            anchorTop = target.y - borderSize;
            anchorWidth = target.w + 2 * borderSize;
            shown = true;
            pollTimer.interval = idlePollMs;
        }
    }

    // Remembered position, in ~/.local/state/quickshell/by-shell/<id>/peeker.json
    FileView {
        path: Quickshell.statePath("peeker.json")
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: saved
            property int rightInset: root.defaultInset
            property string sprite: "corgi"     // basename of an SVG next to shell.qml
        }
    }

    // Bind these in Hyprland, e.g. `qs -p ~/dev/mib-peeker ipc call peeker left`.
    IpcHandler {
        target: "peeker"
        function left(): void { root.nudge(-root.nudgeStep); }
        function right(): void { root.nudge(root.nudgeStep); }
        function reset(): void { saved.rightInset = root.defaultInset; }
        function use(sprite: string): void { saved.sprite = sprite; }
    }

    // While nudging, x changes glide instead of jumping.
    Timer { id: glide; interval: 250 }

    Process {
        id: borderProc
        command: ["hyprctl", "-j", "getoption", "general:border_size"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.borderSize = JSON.parse(text).int || 0; } catch (e) {}
            }
        }
    }

    Process {
        id: activeProc
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                let win = null;
                try { win = JSON.parse(text); } catch (e) {}   // "{}" or "Invalid" when nothing is focused
                root.onActiveWindow(win);
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.fastPollMs
        running: true
        repeat: true
        onTriggered: if (!activeProc.running) activeProc.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "activewindowv2":
            case "movewindowv2":
            case "openwindow":
            case "closewindow":
            case "workspacev2":
            case "focusedmonv2":
            case "fullscreen":
            case "changefloatingmode":
            case "activespecialv2":
            case "configreloaded":
                root.poke();
                break;
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property ShellScreen modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "peeker"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}                     // empty input region: every click passes through

            // Is the cat's corner on this output?
            readonly property bool here: root.anchorRight > modelData.x
                && root.anchorRight <= modelData.x + modelData.width
                && root.anchorTop >= modelData.y
                && root.anchorTop < modelData.y + modelData.height

            Image {
                id: cat
                source: Qt.resolvedUrl(saved.sprite + ".svg")
                cache: false                        // so edited SVGs show up on reload
                width: root.spriteWidth
                height: root.catHeight
                sourceSize.width: root.spriteWidth * 2
                sourceSize.height: root.catHeight * 2
                smooth: true
                mipmap: true

                x: root.anchorRight - overlay.modelData.x - root.rightInset - width
                Behavior on x {
                    enabled: glide.running
                    NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                }
                y: root.anchorTop - overlay.modelData.y - root.svgLedgeY * root.catScale

                readonly property bool visibleHere: root.shown && overlay.here
                opacity: visibleHere ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: cat.visibleHere ? root.fadeInMs : root.fadeOutMs
                        easing.type: Easing.InOutQuad
                    }
                }

                transform: Translate {
                    y: cat.visibleHere ? 0 : -root.dropPx
                    Behavior on y {
                        enabled: cat.visibleHere          // drop in gently, snap back up while hidden
                        NumberAnimation { duration: root.fadeInMs; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
