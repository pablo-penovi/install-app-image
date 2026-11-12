import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// Watches $XDG_STATE_HOME/installappimage/progress/*.json (one file per app,
// written by installappimage) and publishes them as the "apps" global var.
// Also publishes the script's path ("script") from its config file.
PluginComponent {
    id: root

    property var popoutService: null
    readonly property string progressDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/installappimage/progress"
    readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/installappimage/config"
    property var apps: ({})

    FileView {
        path: root.configFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/^SCRIPT=(.*)$/m);
            PluginService.setGlobalVar(root.pluginId, "script", m ? m[1].trim() : "");
        }
        onLoadFailed: PluginService.setGlobalVar(root.pluginId, "script", "")
    }

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

    // Deletes the progress files of the given apps (see the FileViews below
    // for why they stop watching first).
    function retire(keys) {
        const files = [];
        for (const key of keys) {
            const view = root.views[key];
            if (view) {
                view.watchChanges = false;
                files.push(view.path);
            }
        }
        if (files.length > 0)
            Quickshell.execDetached(["rm", "-f"].concat(files));
    }

    // Once every update has finished successfully, clear them after a moment;
    // the widget then closes its panel and hides the pill. A running or
    // failed update keeps everything on screen.
    Timer {
        id: autoClear
        interval: 3000
        onTriggered: {
            if (root.allSucceeded())
                root.retire(Object.keys(root.apps));
        }
    }

    // The widget's "Clear finished" bumps clearSeq; the files are deleted
    // here, where their FileViews live.
    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "clearSeq")
                root.retire(Object.keys(root.apps).filter(k => !!root.apps[k].result));
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

    // One FileView per progress file, keyed by app id. Quickshell aborts,
    // taking DMS down, if a FileView is destroyed while its background read
    // fails. Such a read starts when a watched file is deleted, or when the
    // folder model lags and reports a file that is already gone. So the folder
    // model's delegates don't hold FileViews: they create one, and on release
    // it stops watching and is destroyed seconds later, after any read ends.
    property var views: ({})

    Instantiator {
        model: folder
        delegate: QtObject {
            required property string filePath
            required property string fileName
            // Not the model's fileBaseName: that stops at the first dot, so
            // "knossos.net.json" would become "knossos" and clearing would
            // remove a file that doesn't exist.
            readonly property string key: fileName.replace(/\.json$/, "")
            property var view: null
            Component.onCompleted: {
                view = progressView.createObject(root, {
                    "key": key,
                    "path": filePath
                });
                root.views[key] = view;
            }
            Component.onDestruction: {
                view.released = true;
                view.watchChanges = false;
                view.destroy(5000);
                // A new FileView for the same file may already have taken over.
                if (root.views[key] !== view)
                    return;
                delete root.views[key];
                const next = Object.assign({}, root.apps);
                delete next[key];
                root.apps = next;
                root.publish();
            }
        }
    }

    Component {
        id: progressView
        FileView {
            property string key: ""
            property bool released: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                if (released)
                    return;
                try {
                    const next = Object.assign({}, root.apps);
                    next[key] = JSON.parse(text());
                    root.apps = next;
                    root.publish();
                } catch (e) {
                    // Partial write; the next change event brings the full file.
                }
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

        function script(): string {
            return PluginService.getGlobalVar(root.pluginId, "script", "");
        }
    }
}
