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
    property var setupStatus: ({lua:false, launcher:false, ready:false})
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
    property string backupPath: "~/omabinds-backup.json"
    readonly property bool busy: worker.running
    readonly property bool setupRequired: !previewMode && !setupStatus.ready
    onSetupRequiredChanged:if(!setupRequired && opened)Qt.callLater(function(){search.forceActiveFocus()})
    readonly property string backendPath: Qt.resolvedUrl("backend/omabinds.py").toString().replace(/^file:\/\//, "")
    readonly property string setupScriptPath: Qt.resolvedUrl("scripts/install.sh").toString().replace(/^file:\/\//, "")
    readonly property string setupTerminalCommand: "bash " + JSON.stringify(setupScriptPath) + "; setup_status=$?; printf '\\nSetup finished with status %s.\\n' \"$setup_status\"; read -r -p 'Press Enter to return to omabinds...' _; exit \"$setup_status\""
    readonly property var rows: {
        var items = configState.mappings.map(function(m) {
            return {managed:true, name:m.name, trigger:m.trigger, enabled:m.enabled, action:m.action, mapping:m};
        });
        if (category === "All" || category === "System") {
            items = items.concat(catalog.map(function(r) {
                return {managed:false, name:r.name, trigger:r.trigger, enabled:true, source:r};
            }));
        }
        return items.filter(function(r) {
            return Model.matches(r, search.text) && (category !== "Custom" || r.managed)
                && (category !== "Aliases" || (r.managed && (r.action.kind === "alias" || r.action.copiedFrom)))
                && (category !== "Disabled" || (r.managed && !r.enabled))
                && (category !== "System" || !r.managed);
        });
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
    function setup() {
        if (setupTerminal.running) return
        failed=false
        message="Setup opened in an Omarchy terminal. Return here and press Refresh status when it finishes."
        setupTerminal.running=true
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
        Qt.callLater(function() { root.setupRequired ? setupButton.forceActiveFocus() : search.forceActiveFocus() })
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
                        if (result.setup) root.setupStatus=result.setup
                        if (root.lastOperation === "commit") {root.draft=null;root.conflicts=[]}
                        if (!result.installed && !root.setupRequired) root.message="Install the integration with scripts/install.sh to save keybinds."
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
    Process {
        id: setupTerminal
        command: ["omarchy", "launch", "terminal", "bash", "-lc", root.setupTerminalCommand]
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.failed=true
                root.message="Could not open the Omarchy setup terminal (exit code " + exitCode + ")."
            }
        }
    }
    Ui.KeyboardPanel {
        id: window
        anchorItem:root.anchorItem
        owner:root.hostWidget || root
        bar:root.bar
        open:root.opened
        focusTarget:card
        contentWidth:fittedContentWidth(Style.space(440))
        contentHeight:cappedContentHeight(Style.space(root.draft ? 650 : 620))

        FocusScope {
            id:card
            anchors.fill:parent
            focus:true
            Keys.onEscapePressed: {
                if(root.capturing) {root.capturing=false;return}
                if(root.confirmKind) {root.confirmKind="";return}
                if(root.conflicts.length) {root.conflicts=[];return}
                root.dismiss()
            }
            Keys.onPressed:function(event) {
                if(event.key===Qt.Key_F && (event.modifiers & Qt.ControlModifier) && !root.draft) {
                    search.forceActiveFocus();event.accepted=true
                }
            }

            ColumnLayout {
                id:mainContent
                anchors.fill:parent
                visible:!root.setupRequired
                enabled:!root.busy && root.conflicts.length===0 && root.confirmKind===""
                spacing:Style.space(12)

                Ui.PanelHero {
                    Layout.fillWidth:true
                    title:"OmaBinds"
                    meta:root.draft
                        ? (root.configState.mappings.some(function(m){return m.id===root.draft.id}) ? "EDIT KEYBIND" : "NEW KEYBIND")
                        : root.configState.mappings.length + (root.configState.mappings.length===1 ? " CUSTOM KEYBIND" : " CUSTOM KEYBINDS")
                    foreground:Color.foreground
                    iconComponent:Component {
                        Text {
                            text:"󰌌";textFormat:Text.PlainText;color:Color.foreground
                            font.family:Style.font.family;font.pixelSize:Style.font.display
                        }
                    }
                    trailingControl:root.draft ? null : refreshControl
                }
                Component {
                    id:refreshControl
                    Ui.PanelActionButton {
                        iconText:root.busy?"󰑓":"󰑐"
                        tooltipText:"Refresh"
                        foreground:Color.foreground
                        focusable:true
                        enabled:!root.busy
                        onClicked:root.call("snapshot")
                    }
                }

                Ui.PanelSeparator {Layout.fillWidth:true;foreground:Color.foreground}

                Text {
                    visible:root.message!==""
                    Layout.fillWidth:true
                    text:root.message;textFormat:Text.PlainText;wrapMode:Text.Wrap
                    color:root.failed?Color.urgent:Qt.darker(Color.foreground,1.4)
                    font.family:Style.font.family;font.pixelSize:Style.font.bodySmall
                }

                RowLayout {
                    visible:!root.draft
                    Layout.fillWidth:true
                    spacing:Style.space(8)
                    Ui.TextField {
                        id:search
                        Layout.fillWidth:true
                        placeholderText:"Search keybinds…"
                    }
                    Ui.PanelActionButton {
                        iconText:"+";tooltipText:"New keybind";bordered:true;focusable:true
                        foreground:Color.foreground;size:search.implicitHeight
                        onClicked:root.edit(null,false)
                    }
                }

                RowLayout {
                    visible:!root.draft
                    Layout.fillWidth:true
                    Ui.PanelSectionHeader {
                        Layout.fillWidth:true;text:"KEYBINDS";foreground:Color.foreground
                    }
                    Ui.Dropdown {
                        Layout.preferredWidth:Style.space(128)
                        showLabel:false
                        value:root.category
                        options:[
                            {value:"All",label:"All"},{value:"Custom",label:"Custom"},
                            {value:"Aliases",label:"Aliases"},{value:"Disabled",label:"Disabled"},
                            {value:"System",label:"System"}
                        ]
                        onChanged:function(value){root.category=value}
                    }
                }

                ListView {
                    id:bindings
                    visible:!root.draft
                    Layout.fillWidth:true;Layout.fillHeight:true
                    clip:true;model:root.rows;spacing:Style.space(4);reuseItems:true
                    activeFocusOnTab:true;keyNavigationEnabled:true
                    Keys.onReturnPressed: {
                        if(currentIndex>=0 && currentIndex<count) {
                            var row=root.rows[currentIndex]
                            row.managed?root.edit(row.mapping,false):root.fromSource(row.source)
                        }
                    }
                    Controls.ScrollBar.vertical:Controls.ScrollBar {}
                    delegate:Ui.CursorSurface {
                        id:bindingRow
                        required property var modelData
                        required property int index
                        readonly property string tagText:!modelData.managed?"SYSTEM":!modelData.enabled?"DISABLED":(modelData.action.kind==="alias" || modelData.action.copiedFrom)?"ALIAS":"CUSTOM"
                        width:bindings.width;height:Style.space(64)
                        foreground:Color.foreground
                        current:modelData.managed && !modelData.enabled
                        hasCursor:bindingHover.hovered || (bindings.activeFocus && bindings.currentIndex===index)

                        HoverHandler {id:bindingHover}
                        MouseArea {
                            anchors.fill:parent;cursorShape:Qt.PointingHandCursor
                            onClicked:{bindings.currentIndex=index;modelData.managed?root.edit(modelData.mapping,false):root.fromSource(modelData.source)}
                        }
                        RowLayout {
                            anchors.fill:parent;anchors.leftMargin:Style.space(10);anchors.rightMargin:Style.space(6)
                            spacing:Style.space(8)
                            ColumnLayout {
                                Layout.fillWidth:true;spacing:Style.space(3)
                                Text {
                                    Layout.fillWidth:true
                                    text:modelData.trigger;textFormat:Text.PlainText;elide:Text.ElideRight
                                    color:modelData.enabled?Color.accent:Qt.darker(Color.foreground,1.5)
                                    font.family:Style.font.family;font.pixelSize:Style.font.bodySmall;font.bold:true
                                }
                                Row {
                                    Layout.fillWidth:true;spacing:Style.space(7)
                                    Text {
                                        id:nameLabel
                                        width:Math.min(implicitWidth,Math.max(0,parent.width-tagPill.width-parent.spacing))
                                        text:modelData.name;textFormat:Text.PlainText;elide:Text.ElideRight
                                        color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body
                                    }
                                    Rectangle {
                                        id:tagPill
                                        width:tagLabel.implicitWidth+Style.space(10)
                                        height:tagLabel.implicitHeight+Style.space(4)
                                        anchors.verticalCenter:nameLabel.verticalCenter
                                        radius:Style.cornerRadius
                                        color:Style.selectedFillFor(Color.foreground,Color.accent)
                                        Text {
                                            id:tagLabel;anchors.centerIn:parent;text:bindingRow.tagText;textFormat:Text.PlainText
                                            color:Qt.darker(Color.foreground,1.35);font.family:Style.font.family
                                            font.pixelSize:Style.font.caption;font.bold:true;font.letterSpacing:0.8
                                        }
                                    }
                                }
                            }
                            Ui.PanelActionButton {
                                visible:modelData.managed
                                iconText:modelData.enabled?"󰈈":"󰈉"
                                tooltipText:modelData.enabled?"Disable":"Enable"
                                foreground:Color.foreground
                                onClicked:root.toggleMapping(modelData.mapping)
                            }
                            Ui.PanelActionButton {
                                iconText:!modelData.managed?"+":modelData.enabled?"󰏫":"󰆴"
                                tooltipText:!modelData.managed?"Create alias":modelData.enabled?"Edit":"Remove"
                                foreground:Color.foreground
                                enabled:modelData.managed || modelData.source.supported
                                onClicked:!modelData.managed?root.fromSource(modelData.source):modelData.enabled?root.edit(modelData.mapping,false):root.askRemove(modelData.mapping)
                            }
                        }
                    }
                    Text {
                        anchors.centerIn:parent;width:Math.max(0,parent.width-32)
                        visible:bindings.count===0
                        text:search.text?"No matching keybinds":"No keybinds here yet"
                        horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;textFormat:Text.PlainText
                        color:Qt.darker(Color.foreground,1.5);font.family:Style.font.family;font.pixelSize:Style.font.bodySmall
                    }
                }

                ColumnLayout {
                    visible:!!root.draft
                    Layout.fillWidth:true;Layout.fillHeight:true
                    spacing:Style.space(10)

                    Ui.TextField {id:nameField;Layout.fillWidth:true;placeholderText:"Name"}
                    RowLayout {
                        Layout.fillWidth:true;spacing:Style.space(8)
                        Ui.TextField {id:triggerField;Layout.fillWidth:true;placeholderText:"F20 or SUPER + V"}
                        Ui.PanelActionButton {
                            iconText:root.capturing?"×":"󰌌"
                            tooltipText:root.capturing?"Cancel capture":"Capture combination"
                            bordered:true;focusable:true;foreground:Color.foreground;size:triggerField.implicitHeight
                            onClicked:{root.capturing=!root.capturing;if(root.capturing)captureFocus.forceActiveFocus()}
                        }
                    }
                    Ui.CursorSurface {
                        visible:root.capturing
                        Layout.fillWidth:true;Layout.preferredHeight:Style.space(52)
                        current:true;foreground:Color.foreground
                        Text {
                            anchors.centerIn:parent;text:"Press a combination · Esc cancels"
                            color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.bodySmall
                        }
                        Item {
                            id:captureFocus;anchors.fill:parent
                            Keys.onPressed:function(event) {
                                event.accepted=true
                                if(event.key===Qt.Key_Escape && event.modifiers===Qt.NoModifier){root.capturing=false;return}
                                if(root.capturedKey)return
                                var key=Model.capture(event)
                                if(key){triggerField.text=key;root.capturedKey=event.key}
                            }
                            Keys.onReleased:function(event) {
                                event.accepted=true
                                if(event.key===root.capturedKey && !event.isAutoRepeat){root.capturing=false;root.capturedKey=0;triggerField.forceActiveFocus()}
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth:true
                        Ui.PanelSectionHeader {Layout.fillWidth:true;text:"ACTION";foreground:Color.foreground}
                        Ui.Dropdown {
                            Layout.preferredWidth:Style.space(154);showLabel:false
                            value:root.actionTab
                            options:["Applications","Command","Omarchy","Hyprland","Aliases"]
                            onChanged:function(value){root.actionTab=value;actionSearch.text=""}
                        }
                    }
                    Ui.TextField {
                        id:commandField;visible:root.actionTab==="Command"
                        Layout.fillWidth:true;placeholderText:"Shell command"
                    }
                    Ui.TextField {
                        id:actionSearch;visible:root.actionTab!=="Command"
                        Layout.fillWidth:true;placeholderText:"Search actions…"
                    }
                    ListView {
                        id:actions
                        visible:root.actionTab!=="Command"
                        Layout.fillWidth:true;Layout.fillHeight:true
                        clip:true;reuseItems:true;model:root.actionRows;spacing:Style.space(3)
                        property bool mouseSelecting:false
                        activeFocusOnTab:true;keyNavigationEnabled:true
                        onCurrentIndexChanged:if(!mouseSelecting && activeFocus && currentIndex>=0 && currentIndex<count)root.selectAction(root.actionRows[currentIndex],root.actionTab,false)
                        Keys.onReturnPressed:if(currentIndex>=0 && currentIndex<count)root.selectAction(root.actionRows[currentIndex],root.actionTab,true)
                        Controls.ScrollBar.vertical:Controls.ScrollBar {}
                        delegate:Ui.Button {
                            id:actionRow
                            required property var modelData
                            required property int index
                            readonly property bool keybindStyle:root.actionTab==="Omarchy" || root.actionTab==="Hyprland" || root.actionTab==="Aliases"
                            width:actions.width;height:keybindStyle?Style.space(54):Style.space(38)
                            focusable:true;leftAlign:true
                            selected:root.selectedActionKey===root.actionKey(modelData,root.actionTab)
                            text:keybindStyle?"":modelData.name
                            leftPadding:root.actionTab==="Applications"?Style.space(40):Style.space(10)
                            Image {
                                visible:root.actionTab==="Applications"
                                anchors.left:parent.left;anchors.leftMargin:Style.space(10);anchors.verticalCenter:parent.verticalCenter
                                width:Style.space(20);height:width
                                source:visible?Quickshell.iconPath(modelData.icon || "application-x-executable",true):""
                            }
                            Column {
                                visible:actionRow.keybindStyle
                                anchors.left:parent.left;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter
                                anchors.leftMargin:Style.space(10);anchors.rightMargin:Style.space(10)
                                spacing:Style.space(3)
                                Text {
                                    width:parent.width
                                    text:modelData.trigger || modelData.command || ""
                                    textFormat:Text.PlainText;elide:Text.ElideRight
                                    color:Color.accent;font.family:Style.font.family
                                    font.pixelSize:Style.font.bodySmall;font.bold:true
                                }
                                Text {
                                    width:parent.width;text:modelData.name
                                    textFormat:Text.PlainText;elide:Text.ElideRight
                                    color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body
                                }
                            }
                            onClicked:{actions.mouseSelecting=true;actions.currentIndex=index;actions.mouseSelecting=false;root.selectAction(modelData,root.actionTab,true)}
                        }
                        Text {
                            anchors.centerIn:parent;visible:actions.count===0;text:"No matching actions"
                            color:Qt.darker(Color.foreground,1.5);font.family:Style.font.family;font.pixelSize:Style.font.bodySmall
                        }
                    }
                    Item {visible:root.actionTab==="Command";Layout.fillHeight:true}

                    Ui.PanelSeparator {Layout.fillWidth:true;foreground:Color.foreground}
                    RowLayout {
                        Layout.fillWidth:true
                        Ui.Button {
                            visible:!!root.draft && root.configState.mappings.some(function(m){return m.id===root.draft.id})
                            text:"Delete";focusable:true;enabled:!root.busy
                            onClicked:{root.confirmKind="delete";root.confirmText="Delete this keybind? Its key combination will become available and any replaced binding will be restored."}
                        }
                        Item {Layout.fillWidth:true}
                        Ui.Button {text:"Cancel";focusable:true;onClicked:{root.confirmKind="discard";root.confirmText="Discard the current edit?"}}
                        Ui.Button {text:"Save";focusable:true;bordered:true;enabled:!root.busy && !root.capturing && !root.previewMode;onClicked:root.save()}
                    }
                }

                Ui.PanelSeparator {visible:!root.draft;Layout.fillWidth:true;foreground:Color.foreground}
                RowLayout {
                    visible:!root.draft
                    Layout.fillWidth:true
                    spacing:Style.space(4)
                    Ui.Button {Layout.fillWidth:true;text:"Export";focusable:true;enabled:!root.busy;onClicked:root.call("export",{path:root.backupPath})}
                    Ui.Button {Layout.fillWidth:true;text:"Import";focusable:true;enabled:!root.busy;onClicked:root.call("import",{path:root.backupPath})}
                    Ui.Button {Layout.fillWidth:true;text:"Reset";focusable:true;enabled:!root.busy;onClicked:{root.confirmKind="reset";root.confirmText="Remove all custom omabinds keybinds? System bindings will be restored."}}
                }
            }

            ColumnLayout {
                id:setupContent
                anchors.fill:parent
                visible:root.setupRequired
                spacing:Style.space(14)
                Ui.PanelHero {
                    Layout.fillWidth:true;title:"OmaBinds";meta:"SETUP REQUIRED";foreground:Color.foreground
                    iconComponent:Component {Text {text:"󰌌";color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.display}}
                }
                Ui.PanelSeparator {Layout.fillWidth:true;foreground:Color.foreground}
                Item {Layout.fillHeight:true}
                Ui.PanelSectionHeader {text:"FINISH SETUP";foreground:Color.foreground}
                Text {
                    Layout.fillWidth:true;wrapMode:Text.Wrap
                    text:"Install the Hyprland integration and launcher before managing keybinds. Your current configuration will be backed up and validated."
                    color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body
                }
                Text {Layout.fillWidth:true;text:(root.setupStatus.lua?"✓":"○")+"  Hyprland integration";color:root.setupStatus.lua?Color.accent:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.bodySmall}
                Text {Layout.fillWidth:true;text:(root.setupStatus.launcher?"✓":"○")+"  Application launcher";color:root.setupStatus.launcher?Color.accent:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.bodySmall}
                Ui.Button {id:setupButton;Layout.fillWidth:true;text:setupTerminal.running?"Opening terminal…":"Open setup terminal";focusable:true;bordered:true;onClicked:root.setup()}
                Ui.Button {Layout.fillWidth:true;text:"Refresh status";focusable:true;onClicked:root.call("snapshot")}
                Text {
                    visible:root.message!=="";Layout.fillWidth:true;wrapMode:Text.Wrap
                    text:root.message;color:root.failed?Color.urgent:Qt.darker(Color.foreground,1.4)
                    font.family:Style.font.family;font.pixelSize:Style.font.bodySmall
                }
                Item {Layout.fillHeight:true}
            }
            Rectangle {
                anchors.fill:parent
                visible:!root.setupRequired && (root.conflicts.length>0 || root.confirmKind!=="")
                color:Util.alpha(Color.background,0.72)
                onVisibleChanged:if(visible)Qt.callLater(function(){cancelDialog.forceActiveFocus()})
                MouseArea {anchors.fill:parent;onClicked:{root.conflicts=[];root.confirmKind=""}}
                Ui.BorderSurface {
                    anchors.centerIn:parent
                    width:Math.min(parent.width-Style.space(32),Style.space(400))
                    height:dialogColumn.implicitHeight+Style.space(36)
                    color:Color.background
                    borderSpec:Border.surfaceSpec("popups","border",Color.popups.border,Math.max(1,Style.normalBorderWidth))
                    radius:Style.cornerRadius
                    MouseArea {anchors.fill:parent;onClicked:{}}
                    ColumnLayout {
                        id:dialogColumn
                        anchors.fill:parent;anchors.margins:Style.space(18);spacing:Style.space(14)
                        Text {
                            Layout.fillWidth:true
                            text:root.conflicts.length?"Combination in use":"Confirm change"
                            color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.title;font.bold:true
                        }
                        Text {
                            Layout.fillWidth:true;wrapMode:Text.Wrap;textFormat:Text.PlainText
                            text:root.conflicts.length?root.conflicts.map(function(c){return c.trigger + " → " + c.name}).join("\n") + "\n\nNo bindings have been changed yet.":root.confirmText
                            color:Color.foreground;font.family:Style.font.family;font.pixelSize:Style.font.body
                        }
                        RowLayout {
                            Layout.fillWidth:true
                            Ui.Button {id:cancelDialog;text:"Cancel";focusable:true;KeyNavigation.right:alternateDialog.visible?alternateDialog:confirmDialog;onClicked:{root.conflicts=[];root.confirmKind=""}}
                            Item {Layout.fillWidth:true}
                            Ui.Button {id:alternateDialog;visible:root.conflicts.length>0;text:"Change key";focusable:true;KeyNavigation.left:cancelDialog;KeyNavigation.right:confirmDialog;onClicked:{root.conflicts=[];triggerField.forceActiveFocus()}}
                            Ui.Button {id:confirmDialog;text:root.conflicts.length?"Replace":"Confirm";focusable:true;bordered:true;enabled:!root.busy;KeyNavigation.left:alternateDialog.visible?alternateDialog:cancelDialog;onClicked:root.conflicts.length?root.replaceConflicts():root.confirm()}
                        }
                    }
                }
            }
        }
    }
}
