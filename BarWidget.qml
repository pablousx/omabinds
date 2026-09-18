import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui as Ui

Ui.BarWidget {
    id:root
    moduleName:"pablousx.omabinds"

    readonly property bool opened:panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing:panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function injectPanel() {
        var target=panelLoader.item
        if(!target)return
        if("bar" in target)target.bar=root.bar
        if("settings" in target)target.settings=root.settings
        if("anchorItem" in target)target.anchorItem=button
        if("hostWidget" in target)target.hostWidget=root
    }
    function open(){if(panelLoader.item&&panelLoader.item.open)panelLoader.item.open("{}")}
    function close(){if(panelLoader.item&&panelLoader.item.close)panelLoader.item.close()}
    function togglePanel(){if(panelLoader.item&&panelLoader.item.toggle)panelLoader.item.toggle()}
    function closeForPopoutSwitch(){if(panelLoader.item)panelLoader.item.closeForPopoutSwitch()}

    implicitWidth:button.implicitWidth
    implicitHeight:button.implicitHeight
    onBarChanged:injectPanel()
    onSettingsChanged:injectPanel()

    Loader {
        id:panelLoader
        active:true
        source:Qt.resolvedUrl("Panel.qml")
        visible:false
        onLoaded:{root.injectPanel();Qt.callLater(root.injectPanel)}
    }

    Ui.BarIconButton {
        id:button
        anchors.fill:parent
        bar:root.bar
        text:""
        tooltipText:"omabinds"
        opticalSize:Style.bar.iconCanvas * 0.84
        iconComponent:Component {
            Item {
                Image {
                    id:keycapIcon
                    anchors.fill:parent
                    source:Qt.resolvedUrl("assets/keycap-3d.png")
                    fillMode:Image.PreserveAspectFit
                    smooth:true;mipmap:true
                    visible:false
                }
                MultiEffect {
                    anchors.fill:keycapIcon
                    source:keycapIcon
                    colorization:1
                    colorizationColor:button.foreground
                }
            }
        }
        onPressed:function(mouseButton){if(mouseButton===Qt.LeftButton)root.togglePanel()}
    }
}
