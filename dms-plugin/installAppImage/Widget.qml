import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    PluginGlobalVar {
        id: appsVar
        varName: "apps"
        defaultValue: ({})
    }

    PluginGlobalVar {
        id: toggleVar
        varName: "toggleSeq"
        defaultValue: 0
    }

    readonly property var appList: Object.keys(appsVar.value || {}).sort().map(k => Object.assign({ key: k }, appsVar.value[k]))
    readonly property var running: appList.filter(a => !a.result)
    readonly property bool anyFailed: appList.some(a => a.result === "failed")
    readonly property real overall: {
        let done = 0, total = 0;
        for (const a of running) {
            done += a.done || 0;
            total += a.total || 0;
        }
        return total > 0 ? done / total : 0;
    }

    function fmtBytes(n) {
        if (!n)
            return "0 B";
        const u = ["B", "KB", "MB", "GB"];
        let i = 0;
        while (n >= 1024 && i < u.length - 1) {
            n /= 1024;
            i++;
        }
        return n.toFixed(i ? 1 : 0) + " " + u[i];
    }

    PluginGlobalVar {
        id: scriptVar
        varName: "script"
        defaultValue: ""
    }

    // Set by "installappimage --setup"; falls back to finding it on PATH.
    readonly property string updaterPath: scriptVar.value || "installappimage"

    // Starts the update as a transient user unit so it outlives the shell;
    // systemd-run refuses a second unit with the same name, which doubles as
    // the "already updating" guard.
    function retry(key, row) {
        row.retrying = true;
        const p = retryProc.createObject(root, {
            "appKey": key,
            "row": row,
            "command": ["systemd-run", "--user", "--collect", "--quiet", "--unit=installappimage-update-" + key, root.updaterPath, "--update", key, "--ui", "auto"]
        });
        p.running = true;
    }

    Component {
        id: retryProc
        Process {
            property string appKey: ""
            property var row: null
            stderr: StdioCollector {
                id: err
            }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    const msg = err.text.trim();
                    ToastService.showError("Couldn't retry " + appKey, msg.includes("already exists") ? "An update for it is already running" : msg);
                    if (row)
                        row.retrying = false;
                }
                destroy();
            }
        }
    }

    function pillText() {
        if (running.length > 0)
            return Math.round(overall * 100) + "%";
        return anyFailed ? "failed" : "done";
    }

    // Nothing left to show: close the panel (it would otherwise float over a
    // hidden pill) and hide the pill.
    onAppListChanged: {
        if (appList.length === 0)
            closePopout();
        setVisibilityOverride(appList.length > 0);
    }
    Component.onCompleted: setVisibilityOverride(appList.length > 0)

    property int _seenToggle: -1
    readonly property int toggleSeq: toggleVar.value
    onToggleSeqChanged: {
        if (_seenToggle >= 0 && appList.length > 0)
            triggerPopout();
        _seenToggle = toggleSeq;
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.anyFailed && root.running.length === 0 ? "error" : "system_update_alt"
                size: root.iconSize
                color: root.anyFailed && root.running.length === 0 ? Theme.error : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.pillText()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: "system_update_alt"
                size: root.iconSize
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.pillText()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 440
    popoutHeight: 420

    popoutContent: Component {
        PopoutComponent {
            id: pop
            headerText: "AppImage updates"
            detailsText: root.running.length > 0 ? root.running.length + " in progress" : "All finished"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    model: root.appList

                    StyledRect {
                        id: row
                        required property var modelData
                        property bool retrying: false
                        readonly property bool failed: modelData.result === "failed"
                        readonly property bool ok: modelData.result === "ok"
                        width: parent.width
                        height: inner.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            id: inner
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS
                                DankIcon {
                                    name: failed ? "error" : ok ? "check_circle" : "downloading"
                                    color: failed ? Theme.error : ok ? Theme.primary : Theme.surfaceText
                                    size: Theme.iconSize
                                }
                                StyledText {
                                    text: (modelData.name || modelData.key) + (modelData.to ? "  →  " + modelData.to : "")
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }
                            }

                            Rectangle {
                                visible: !modelData.result
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Theme.surfaceContainerHighest
                                Rectangle {
                                    width: parent.width * (modelData.total ? Math.min(1, modelData.done / modelData.total) : 0)
                                    height: parent.height
                                    radius: 3
                                    color: Theme.primary
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }

                            StyledText {
                                width: parent.width
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeSmall
                                color: failed ? Theme.error : Theme.surfaceVariantText
                                text: failed ? "Failed: " + (modelData.reason || "unknown error")
                                    : ok ? (modelData.reason || "Updated")
                                    : (modelData.phase || "") + (modelData.total ? "  ·  " + root.fmtBytes(modelData.done) + " / " + root.fmtBytes(modelData.total) : "")
                            }

                            StyledText {
                                visible: !!(modelData.log && modelData.log.length)
                                width: parent.width
                                wrapMode: Text.Wrap
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                text: (modelData.log || []).slice(-3).join("\n")
                            }

                            StyledRect {
                                visible: failed
                                width: retryRow.implicitWidth + Theme.spacingL * 2
                                height: retryRow.implicitHeight + Theme.spacingS * 2
                                radius: Theme.cornerRadius
                                opacity: row.retrying ? 0.5 : 1
                                color: retryArea.containsMouse && !row.retrying ? Theme.surfaceContainerHighest : Theme.surfaceContainer
                                Row {
                                    id: retryRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    DankIcon {
                                        name: "refresh"
                                        size: Theme.iconSizeSmall
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: row.retrying ? "Starting…" : "Retry"
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    id: retryArea
                                    anchors.fill: parent
                                    enabled: !row.retrying
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.retry(row.modelData.key, row)
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    visible: root.appList.some(a => !!a.result)
                    width: clearLabel.implicitWidth + Theme.spacingL * 2
                    height: clearLabel.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: clearArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    StyledText {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Clear finished"
                        color: Theme.primary
                    }
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const dir = (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/installappimage/progress/";
                            const files = root.appList.filter(a => !!a.result).map(a => dir + a.key + ".json");
                            pop.closePopout();
                            Quickshell.execDetached(["rm", "-f"].concat(files));
                        }
                    }
                }
            }
        }
    }
}
