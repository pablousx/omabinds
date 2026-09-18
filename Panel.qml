import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
    id: root
    moduleName: "pablousx.omabinds"
    ipcTarget: "pablousx.omabinds"
    manageIpc: false
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var manifest: null
    property Item anchorItem: null
    property Item hostWidget: null
    property bool previewMode: false
    property var configState: ({version: 1, mappings: []})
    property string revision: ""
    property var catalog: []
    property var applications: []
    property var commands: []
    property string message: ""
    property bool failed: false
    property var draft: null
    property string category: "All"
    property string actionTab: "Applications"
    property string selectedActionKey: ""
    property bool capturing: false
    property int capturedKey: 0
    onCapturingChanged:if(capturing)capturedKey=0
    property var pending: null
    property var conflicts: []
    property string confirmKind: ""
    property string confirmText: ""
    property var imported: null
    property var request: ({})
    property string lastOperation: ""
    readonly property bool busy: worker.running
    readonly property string backendPath: Qt.resolvedUrl("backend/omabinds.py").toString().replace(/^file:\/\//, "")
    readonly property var rows: {
        var all = configState.mappings.map(function(m) { return {managed:true, name:m.name, trigger:m.trigger, enabled:m.enabled, action:m.action, mapping:m} })
        if (category === "All" || category === "System")
            all = all.concat(catalog.map(function(r) { return {managed:false, name:r.name, trigger:r.trigger, enabled:true, source:r} }))
        return all.filter(function(r) {
            return Model.matches(r, search.text) && (category !== "Custom" || r.managed)
                && (category !== "Aliases" || (r.managed && (r.action.kind === "alias" || r.action.copiedFrom)))
                && (category !== "Disabled" || (r.managed && !r.enabled))
                && (category !== "System" || !r.managed)
        })
    }
    readonly property var actionRows: {
        var list = []
        if (actionTab === "Applications") list = applications
        else if (actionTab === "Aliases") list = catalog.concat(configState.mappings.map(function(m) {return {name:m.name,trigger:m.trigger,id:m.id,supported:true,actionCopy:m.action}}))
        else if (actionTab === "Omarchy") list = commands
        else if (actionTab === "Hyprland") list = [
            {name:"Toggle fullscreen",command:"hyprctl dispatch fullscreen 0"},
            {name:"Toggle floating window",command:"hyprctl dispatch togglefloating"},
            {name:"Close active window",command:"hyprctl dispatch killactive"},
            {name:"Center window",command:"hyprctl dispatch centerwindow"},
            {name:"Focus left",command:"hyprctl dispatch movefocus l"},
            {name:"Focus right",command:"hyprctl dispatch movefocus r"},
            {name:"Previous workspace",command:"hyprctl dispatch workspace -1"},
            {name:"Next workspace",command:"hyprctl dispatch workspace +1"}
        ]
        return list.filter(function(r) { return Model.matches(r, actionSearch.text) })
    }
    function call(op, data) {
        if (busy || previewMode) return
        request = data || {}; request.op = op; lastOperation = op
        failed = false; message = ""
        worker.running = true
    }
    function open(payload) {
        root.controller.show()
        var args = {}; try { args = JSON.parse(payload || "{}") } catch(e) {}
        previewMode = !!args.preview
        if (previewMode) {
            configState = {version:1,mappings:[
                {id:"demo1",name:"Obsidian",trigger:"F20",enabled:true,action:{kind:"app",desktop:"obsidian.desktop"}},
                {id:"demo2",name:"My command",trigger:"F21",enabled:true,action:{kind:"command",command:"notify-send 'Hello'"}},
                {id:"demo3",name:"Clipboard",trigger:"F22",enabled:true,action:{kind:"alias",source:"|SUPER + V"}},
                {id:"demo4",name:"Focus mode",trigger:"SUPER + F23",enabled:false,action:{kind:"command",command:"omarchy toggle nightlight"}}
            ]}
            catalog = [{id:"|SUPER + V",name:"Clipboard",trigger:"SUPER + V",supported:true,signature:"demo",submap:""}]
            message = "Preview · sample data; changes are disabled"
        } else call("snapshot")
        Qt.callLater(function() { search.forceActiveFocus() })
    }
    function close() { root.controller.hide(); capturing = false }
    function capturePreview(path) {
        if (previewMode) card.grabToImage(function(result) { console.log("Preview saved:", result.saveToFile(path), path) })
    }
    function dismiss() {
        if (busy) return
        if (draft) { confirmKind = "discard"; confirmText = "Discard the changes to this keybind?"; return }
        close()
    }
    function edit(mapping, duplicate) {
        draft = mapping ? Model.clone(mapping) : {id:Model.uid(),name:"",trigger:"",enabled:true,action:{kind:"command",command:""},replaces:{}}
        if (duplicate) { draft.id=Model.uid(); draft.name += " (copy)"; draft.trigger=""; draft.replaces={} }
        nameField.text=draft.name; triggerField.text=draft.trigger
        commandField.text=draft.action.command || ""
        actionTab = draft.action.kind === "app" ? "Applications" : draft.action.kind === "alias" ? "Aliases" : "Command"
        selectedActionKey = draft.action.kind === "app" ? "Applications:" + draft.action.desktop
            : draft.action.kind === "alias" ? "Aliases:" + draft.action.source
            : draft.action.selectedFrom ? draft.action.selectedFrom : ""
        conflicts=[]; message=""; Qt.callLater(function() { nameField.forceActiveFocus() })
    }
    function fromSource(source) {
        edit(null, false)
        draft.name=source.name; nameField.text=source.name
        actionTab="Aliases"
        selectAction(source, "Aliases")
    }
    function askRemove(mapping) {
        draft=Model.clone(mapping)
        confirmKind="delete"
        confirmText="Remove this keybind? Its combination will become available and any replaced system binding will be restored."
    }
    function actionKey(row, tab) { return tab + ":" + (row.id || row.command || "") }
    function clearAction() {
        var d=Model.clone(draft)
        d.action={kind:"command",command:""}
        draft=d;commandField.text="";selectedActionKey=""
    }
    function selectAction(row, tab, allowToggle) {
        var key=actionKey(row,tab)
        if (allowToggle && selectedActionKey === key) { clearAction(); return }
        var d=Model.clone(draft)
        if (tab === "Applications") d.action={kind:"app",desktop:row.id}
        else if (tab === "Aliases") {
            if (!row.supported) { failed=true; message="This action cannot be reused safely."; return }
            if(row.actionCopy) {d.action=Model.clone(row.actionCopy);d.action.copiedFrom=row.name;d.action.selectedFrom=key}
            else d.action={kind:"alias",source:row.id,signature:row.signature}
        } else {d.action={kind:"command",command:row.command,selectedFrom:key}}
        if (!nameField.text) nameField.text=row.name
        draft=d; commandField.text=d.action.command || "";selectedActionKey=key
    }
    function candidate() {
        var s=Model.clone(configState), d=Model.clone(draft)
        d.name=nameField.text; d.trigger=triggerField.text
        if (actionTab === "Command") d.action={kind:"command",command:commandField.text}
        var index=s.mappings.findIndex(function(m) { return m.id === d.id })
        if (index < 0) s.mappings.push(d); else s.mappings[index]=d
        return s
    }
    function save() { pending=candidate(); call("preview",{state:pending,revision:revision}) }
    function replaceConflicts() {
        var s=Model.clone(pending)
        for (var i=0;i<conflicts.length;i++) {
            var c=conflicts[i]
            if (c.dynamic || c.submap) { failed=true;message="This conflict must be changed in its source configuration.";return }
            if (c.managed) {
                s.mappings.forEach(function(m) { if(m.id===c.id) m.enabled=false })
            } else {
                s.mappings.forEach(function(m) { if(m.id===c.mapping) { if(!m.replaces)m.replaces={}; m.replaces[c.id]=c.signature } })
            }
        }
        conflicts=[]; pending=s; call("commit",{state:s,revision:revision})
    }
    function toggleMapping(mapping) {
        var s=Model.clone(configState)
        s.mappings.forEach(function(m) { if(m.id===mapping.id)m.enabled=!m.enabled })
        pending=s; call("preview",{state:s,revision:revision})
    }
    function confirm() {
        var kind=confirmKind; confirmKind=""
        if (kind === "discard") { draft=null;capturing=false;return }
        var s=Model.clone(configState)
        if (kind === "delete") s.mappings=s.mappings.filter(function(m){return m.id!==draft.id})
        if (kind === "reset") s.mappings=[]
        if (kind === "import") s=imported
        pending=s; call("preview",{state:s,revision:revision})
    }
    Process {
        id: worker
        command: ["python3", root.backendPath]
        stdinEnabled: true
        onStarted: { write(JSON.stringify(root.request)); stdinEnabled=false }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result=JSON.parse(text)
                    if (!result.ok) { root.failed=true;root.message=result.error;return }
                    if (result.state && result.revision) {
                        root.configState=result.state;root.revision=result.revision
                        root.catalog=result.catalog.bindings;root.applications=result.apps;root.commands=result.commands || []
                        if (root.lastOperation === "commit") {root.draft=null;root.conflicts=[]}
                        if (!result.installed) root.message="Install the integration with scripts/install.sh to save keybinds."
                        if (result.catalog.warnings.length) {root.failed=true;root.message=result.catalog.warnings.join("\n")}
                    }
                    if (result.message) root.message=result.message
                    if (result.imported) {root.imported=result.imported;root.confirmKind="import";root.confirmText="Importing " + result.imported.mappings.length + " keybinds will replace the current managed configuration. Imported commands will run when their keys are used."}
                    if (result.conflicts && result.conflicts.length) {root.conflicts=result.conflicts;root.pending=result.state || root.pending}
                    else if (root.lastOperation === "preview") Qt.callLater(function(){root.call("commit",{state:result.state,revision:root.revision})})
                } catch(e) {root.failed=true;root.message="Invalid controller response: " + e}
            }
        }
        stderr: StdioCollector { onStreamFinished: if(text.trim()) {root.failed=true;root.message=text.trim()} }
        onRunningChanged: if (!running) stdinEnabled=true
    }
    Ui.KeyboardPanel {
        id: window
        anchorItem:root.anchorItem
        owner:root.hostWidget || root
        bar:root.bar
        open:root.opened
        focusTarget:card
        contentWidth:fittedContentWidth(Style.space(570))
        contentHeight:cappedContentHeight(Style.space(760))
        FocusScope {
            id: card
            anchors.fill:parent
            focus:true
            Keys.onEscapePressed: {
                if(root.capturing) {root.capturing=false;return}
                if(root.confirmKind) {root.confirmKind="";return}
                if(root.conflicts.length) {root.conflicts=[];return}
                root.dismiss()
            }
            Keys.onPressed: function(event) {
                if(event.key===Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {search.forceActiveFocus();event.accepted=true}
            }
            ColumnLayout {
                anchors.fill:parent;anchors.bottomMargin:28;spacing:16
                enabled: !root.busy && root.conflicts.length===0 && root.confirmKind===""
                RowLayout {
                    Layout.fillWidth:true
                    Item {
                        Layout.preferredWidth:32;Layout.preferredHeight:32
                        Image {
                            id:titleIcon
                            anchors.fill:parent;source:Qt.resolvedUrl("assets/keycap-3d.png")
                            fillMode:Image.PreserveAspectFit;smooth:true;mipmap:true;visible:false
                        }
                        MultiEffect {anchors.fill:titleIcon;source:titleIcon;colorization:1;colorizationColor:Color.foreground}
                    }
                    Text {Layout.fillWidth:true;text:"omabinds";color:Color.foreground;font.family:Style.font.family;font.pixelSize:26;font.bold:true}
                    Ui.Button {text:root.busy?"Validating…":"Refresh";focusable:true;enabled:!root.busy && !root.draft;onClicked:root.call("snapshot")}
                    Ui.Button {text:"Close";focusable:true;onClicked:root.dismiss()}
                }
                Rectangle {Layout.fillWidth:true;height:1;color:Color.muted;opacity:0.35}
                RowLayout {
                    visible:!root.draft;Layout.fillWidth:true
                    Item {
                        Layout.fillWidth:true;Layout.preferredHeight:search.implicitHeight
                        Ui.TextField {id:search;anchors.fill:parent;rightPadding:clearSearch.visible?42:horizontalPadding;placeholderText:"Search by name, key, or action…  Ctrl+F"}
                        Ui.Button {id:clearSearch;visible:search.text!=="";anchors.right:parent.right;anchors.rightMargin:4;anchors.verticalCenter:parent.verticalCenter;text:"×";focusable:true;onClicked:{search.clear();search.forceActiveFocus()}}
                    }
                    Ui.Button {text:"＋ New keybind";focusable:true;bordered:true;enabled:!root.busy;onClicked:root.edit(null,false)}
                }
                RowLayout {
                    visible:!root.draft;spacing:6
                    Repeater {
                        model:["All","Custom","Aliases","Disabled","System"]
                        Ui.Button {required property string modelData;text:modelData;focusable:true;selected:root.category===modelData;onClicked:root.category=modelData}
                    }
                }
                ListView {
                    id: bindings
                    visible:!root.draft;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
                    model:root.rows;spacing:4;reuseItems:true
                    activeFocusOnTab:true
                    keyNavigationEnabled:true
                    highlight:Rectangle {color:Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,0.08)}
                    Keys.onReturnPressed: {
                        if(currentIndex>=0 && currentIndex<count) {
                            var row=root.rows[currentIndex]
                            row.managed?root.edit(row.mapping,false):root.fromSource(row.source)
                        }
                    }
                    Controls.ScrollBar.vertical:Controls.ScrollBar {}
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width:bindings.width;height:68
                        color:index % 2 ? Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.025):"transparent"
                        RowLayout {
                            anchors.fill:parent;anchors.margins:10;spacing:14
                            Rectangle {
                                Layout.preferredWidth:180;Layout.preferredHeight:34;radius:Style.cornerRadius
                                color:Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,0.1)
                                Text {anchors.centerIn:parent;width:parent.width-10;horizontalAlignment:Text.AlignHCenter;elide:Text.ElideRight;text:modelData.trigger;color:Color.accent;font.family:Style.font.family;font.pixelSize:13}
                            }
                            ColumnLayout {
                                Layout.fillWidth:true;spacing:4
                                Text {Layout.fillWidth:true;text:modelData.name;textFormat:Text.PlainText;elide:Text.ElideRight;color:Color.foreground;font.family:Style.font.family;font.pixelSize:14}
                                Text {text:!modelData.managed?"SYSTEM · reusable action":!modelData.enabled?"DISABLED":(modelData.action.kind==="alias" || modelData.action.copiedFrom)?"ALIAS · shared action":"CUSTOM";color:!modelData.enabled?Color.muted:Color.accent;font.family:Style.font.family;font.pixelSize:10;font.letterSpacing:1}
                            }
                            Ui.Button {visible:modelData.managed;text:modelData.enabled?"Disable":"Enable";focusable:true;enabled:!root.busy;onClicked:root.toggleMapping(modelData.mapping)}
                            Ui.Button {
                                text:!modelData.managed?"Create alias":modelData.enabled?"Edit":"Remove"
                                focusable:true;enabled:!root.busy && (modelData.managed || modelData.source.supported)
                                onClicked:!modelData.managed?root.fromSource(modelData.source):modelData.enabled?root.edit(modelData.mapping,false):root.askRemove(modelData.mapping)
                            }
                        }
                    }
                    Text {
                        anchors.centerIn:parent;width:Math.max(0,parent.width-32)
                        visible:bindings.count===0;text:search.text?"No results. Try another search.":"Create your first keybind. Your current shortcuts will be preserved."
                        horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;textFormat:Text.PlainText
                        color:Color.muted;font.family:Style.font.family
                    }
                }
                ColumnLayout {
                    visible:!!root.draft;Layout.fillWidth:true;Layout.fillHeight:true;spacing:12
                    RowLayout {
                        Ui.TextField {id:nameField;Layout.fillWidth:true;placeholderText:"Keybind name"}
                        Ui.Button {visible:!!root.draft && root.configState.mappings.some(function(m){return m.id===root.draft.id});text:"Duplicate";focusable:true;enabled:!root.busy;onClicked:root.edit(root.candidate().mappings.find(function(m){return m.id===root.draft.id}),true)}
                        Ui.Button {visible:!!root.draft && root.configState.mappings.some(function(m){return m.id===root.draft.id});text:"Delete";focusable:true;enabled:!root.busy;onClicked:{root.confirmKind="delete";root.confirmText="Delete this keybind? Its key combination will become available and any replaced binding will be restored."}}
                    }
                    RowLayout {
                        Ui.TextField {id:triggerField;Layout.fillWidth:true;placeholderText:"F20, SUPER + V, XF86AudioPlay…"}
                        Ui.Button {text:root.capturing?"Cancel capture":"Capture combination";focusable:true;bordered:true;onClicked:{root.capturing=!root.capturing;if(root.capturing)captureFocus.forceActiveFocus()}}
                    }
                    Rectangle {
                        visible:root.capturing;Layout.fillWidth:true;Layout.preferredHeight:70
                        color:Qt.rgba(Color.accent.r,Color.accent.g,Color.accent.b,0.12);border.color:Color.accent;radius:Style.cornerRadius
                        Text {anchors.centerIn:parent;text:"Press the combination · Escape cancels";color:Color.accent;font.family:Style.font.family}
                        Item {
                            id:captureFocus;anchors.fill:parent
                            Keys.onPressed:function(event) {
                                event.accepted=true
                                if(event.key===Qt.Key_Escape && event.modifiers===Qt.NoModifier){root.capturing=false;return}
                                if(root.capturedKey)return
                                var key=Model.capture(event)
                                if(key) {triggerField.text=key;root.capturedKey=event.key}
                            }
                            Keys.onReleased:function(event) {
                                event.accepted=true
                                if(event.key===root.capturedKey && !event.isAutoRepeat) {
                                    root.capturing=false;root.capturedKey=0;triggerField.forceActiveFocus()
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth:true;wrapMode:Text.Wrap;color:Color.accent;font.family:Style.font.family;font.pixelSize:12
                        text:"Choose what the key combination triggers"
                    }
                    RowLayout {
                        Repeater {
                            model:["Applications","Command","Omarchy","Hyprland","Aliases"]
                            Ui.Button {
                                required property string modelData
                                text:modelData;focusable:true;selected:root.actionTab===modelData
                                onActiveFocusChanged:if(activeFocus){root.actionTab=modelData;actionSearch.text=""}
                                onClicked:{root.actionTab=modelData;actionSearch.text=""}
                            }
                        }
                    }
                    Ui.TextField {id:commandField;visible:root.actionTab==="Command";Layout.fillWidth:true;placeholderText:"Shell command, for example: notify-send 'Hello'"}
                    Item {
                        visible:root.actionTab!=="Command";Layout.fillWidth:true;Layout.preferredHeight:actionSearch.implicitHeight
                        Ui.TextField {id:actionSearch;anchors.fill:parent;rightPadding:clearActionSearch.visible?42:horizontalPadding;placeholderText:"Search actions or applications…"}
                        Ui.Button {id:clearActionSearch;visible:actionSearch.text!=="";anchors.right:parent.right;anchors.rightMargin:4;anchors.verticalCenter:parent.verticalCenter;text:"×";focusable:true;onClicked:{actionSearch.clear();actionSearch.forceActiveFocus()}}
                    }
                    ListView {
                        id:actions;visible:root.actionTab!=="Command";Layout.fillWidth:true;Layout.fillHeight:true;clip:true;reuseItems:true
                        property bool mouseSelecting:false
                        model:root.actionRows
                        activeFocusOnTab:true
                        keyNavigationEnabled:true
                        highlight:null
                        onCurrentIndexChanged:if(!mouseSelecting && activeFocus && currentIndex>=0 && currentIndex<count)root.selectAction(root.actionRows[currentIndex],root.actionTab,false)
                        Keys.onReturnPressed:if(currentIndex>=0 && currentIndex<count)root.selectAction(root.actionRows[currentIndex],root.actionTab,true)
                        Controls.ScrollBar.vertical:Controls.ScrollBar {}
                        delegate: Ui.Button {
                            required property var modelData
                            required property int index
                            width:actions.width;height:42;focusable:true;leftAlign:true
                            selected:root.selectedActionKey===root.actionKey(modelData,root.actionTab)
                            text:(modelData.trigger?modelData.trigger + "   →   ":"") + modelData.name
                            leftPadding:root.actionTab==="Applications"?42:12
                            Image {visible:root.actionTab==="Applications";anchors.left:parent.left;anchors.leftMargin:10;anchors.verticalCenter:parent.verticalCenter;width:24;height:24;source:visible?Quickshell.iconPath(modelData.icon || "application-x-executable",true):""}
                            onClicked:{actions.mouseSelecting=true;actions.currentIndex=index;actions.mouseSelecting=false;root.selectAction(modelData,root.actionTab,true)}
                        }
                        Text {anchors.centerIn:parent;width:Math.max(0,parent.width-32);visible:actions.count===0;text:"No matching actions.";horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;color:Color.muted;font.family:Style.font.family}
                    }
                    Item {visible:root.actionTab==="Command";Layout.fillHeight:true}
                    RowLayout {
                        Layout.alignment:Qt.AlignRight
                        Ui.Button {text:"Cancel";focusable:true;enabled:!root.busy;onClicked:{root.confirmKind="discard";root.confirmText="Discard the current edit?"}}
                        Ui.Button {text:"Validate and save";focusable:true;bordered:true;enabled:!root.busy && !root.capturing && !root.previewMode;onClicked:root.save()}
                    }
                }
                RowLayout {
                    visible:!root.draft;Layout.fillWidth:true
                    Ui.TextField {id:filePath;Layout.fillWidth:true;placeholderText:"~/omabinds-backup.json"}
                    Ui.Button {text:"Export";focusable:true;enabled:!root.busy;onClicked:root.call("export",{path:filePath.text || "~/omabinds-backup.json"})}
                    Ui.Button {text:"Import";focusable:true;enabled:!root.busy;onClicked:root.call("import",{path:filePath.text || "~/omabinds-backup.json"})}
                    Ui.Button {text:"Reset";focusable:true;enabled:!root.busy;onClicked:{root.confirmKind="reset";root.confirmText="Remove all custom omabinds keybinds? System bindings will be restored."}}
                }
            }
            Text {
                anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom
                height:18;visible:root.message!=="";text:root.message;textFormat:Text.PlainText
                verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight
                color:root.failed?Color.urgent:Color.accent;font.family:Style.font.family;font.pixelSize:12
            }
            Rectangle {
                anchors.fill:parent;visible:root.conflicts.length>0 || root.confirmKind!=="";color:Qt.rgba(0,0,0,0.85)
                onVisibleChanged:if(visible)Qt.callLater(function(){cancelDialog.forceActiveFocus()})
                MouseArea {anchors.fill:parent}
                ColumnLayout {
                    anchors.centerIn:parent;width:Math.min(parent.width-60,650);spacing:18
                    Text {text:root.conflicts.length?"Combination in use":"Confirm change";color:Color.foreground;font.family:Style.font.family;font.pixelSize:22;font.bold:true}
                    Text {
                        Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText
                        text:root.conflicts.length?root.conflicts.map(function(c){return c.trigger + " → " + c.name}).join("\n") + "\n\nNo bindings have been changed yet.":root.confirmText
                        color:Color.foreground;font.family:Style.font.family;font.pixelSize:14
                    }
                    RowLayout {
                        Ui.Button {id:cancelDialog;text:"Cancel";focusable:true;KeyNavigation.right:alternateDialog.visible?alternateDialog:confirmDialog;onClicked:{root.conflicts=[];root.confirmKind=""}}
                        Ui.Button {id:alternateDialog;visible:root.conflicts.length>0;text:"Use another combination";focusable:true;KeyNavigation.left:cancelDialog;KeyNavigation.right:confirmDialog;onClicked:{root.conflicts=[];triggerField.forceActiveFocus()}}
                        Ui.Button {id:confirmDialog;text:root.conflicts.length?"Replace explicitly":"Confirm";focusable:true;bordered:true;enabled:!root.busy;KeyNavigation.left:alternateDialog.visible?alternateDialog:cancelDialog;onClicked:root.conflicts.length?root.replaceConflicts():root.confirm()}
                    }
                }
            }
        }
    }
}
