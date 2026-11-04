import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Watches $XDG_STATE_HOME/installappimage/progress/*.json (one file per app,
// written by installappimage.sh) and publishes them as the "apps" global var.
PluginComponent {
    id: root

    property var popoutService: null
    readonly property string progressDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/installappimage/progress"
    property var apps: ({})

    function publish() {
        PluginService.setGlobalVar(root.pluginId, "apps", Object.assign({}, root.apps));
        if (root.allSucceeded())
            autoClear.restart();
        else
            autoClear.stop();
    }

    function allSucceeded() {
        const keys = Object.keys(root.apps);
        return keys.length > 0 && keys.every(k => root.apps[k].result === "ok");
    }

    // Once every update has finished successfully, clear them after a moment;
    // the widget then closes its panel and hides the pill. A running or
    // failed update keeps everything on screen.
    Timer {
        id: autoClear
        interval: 3000
        onTriggered: {
            if (!root.allSucceeded())
                return;
            const files = Object.keys(root.apps).map(k => root.progressDir + "/" + k + ".json");
            Quickshell.execDetached(["rm", "-f"].concat(files));
        }
    }

    // FolderListModel only watches a folder that exists when it is set.
    Process {
        running: true
        command: ["mkdir", "-p", root.progressDir]
        onExited: folder.folder = "file://" + root.progressDir
    }

    FolderListModel {
        id: folder
        nameFilters: ["*.json"]
        showDirs: false
        showHidden: false
    }

    Instantiator {
        model: folder
        delegate: FileView {
            required property string filePath
            required property string fileBaseName
            path: filePath
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    const next = Object.assign({}, root.apps);
                    next[fileBaseName] = JSON.parse(text());
                    root.apps = next;
                    root.publish();
                } catch (e) {
                    // Partial write; the next change event brings the full file.
                }
            }
            Component.onDestruction: {
                const next = Object.assign({}, root.apps);
                delete next[fileBaseName];
                root.apps = next;
                root.publish();
            }
        }
    }

    IpcHandler {
        target: "installappimage"

        function ping(): string {
            return "ok";
        }

        function toggle(): string {
            PluginService.setGlobalVar(root.pluginId, "toggleSeq", PluginService.getGlobalVar(root.pluginId, "toggleSeq", 0) + 1);
            return "ok";
        }

        function status(): string {
            return JSON.stringify(root.apps);
        }
    }
}
