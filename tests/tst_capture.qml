import QtQuick
import QtTest
import "../Model.js" as Model

TestCase {
    name: "Capture"
    function test_keys_data() {
        return [
            {tag:"F20",key:Qt.Key_F20,mods:0,expected:"F20"},
            {tag:"F21",key:Qt.Key_F21,mods:0,expected:"F21"},
            {tag:"F22",key:Qt.Key_F22,mods:0,expected:"F22"},
            {tag:"F35",key:Qt.Key_F35,mods:0,expected:"F35"},
            {tag:"clipboard",key:Qt.Key_V,mods:Qt.MetaModifier,expected:"SUPER + V"},
            {tag:"unusual",key:Qt.Key_F22,mods:Qt.ControlModifier|Qt.AltModifier|Qt.ShiftModifier,expected:"CTRL + ALT + SHIFT + F22"},
            {tag:"media",key:Qt.Key_MediaPlay,mods:0,expected:"XF86AudioPlay"},
            {tag:"volume",key:Qt.Key_VolumeUp,mods:0,expected:"XF86AudioRaiseVolume"},
            {tag:"brightness",key:Qt.Key_MonBrightnessUp,mods:0,expected:"XF86MonBrightnessUp"},
            {tag:"caps",key:Qt.Key_CapsLock,mods:0,expected:"Caps_Lock"},
            {tag:"keypad",key:Qt.Key_1,mods:Qt.KeypadModifier,expected:"KP_1"},
            {tag:"keypad-plus",key:Qt.Key_Plus,mods:Qt.KeypadModifier,expected:"KP_Add"},
            {tag:"modifier",key:Qt.Key_Control,mods:Qt.ControlModifier,expected:""},
            {tag:"altgr",key:Qt.Key_AltGr,mods:Qt.GroupSwitchModifier,expected:""},
            {tag:"fallback",key:0,mods:0,scan:191,expected:"code:191"}
        ]
    }
    function test_keys(data) {
        compare(Model.capture({key:data.key,modifiers:data.mods,nativeScanCode:data.scan||0,isAutoRepeat:false}),data.expected)
    }
    function test_repeat() {
        compare(Model.capture({key:Qt.Key_F20,modifiers:0,isAutoRepeat:true}),"")
    }
    function test_search_normalizes_keybinds() {
        var row = {name:"Screenshot",trigger:"SUPER + CTRL + ALT + M"}
        verify(Model.matches(row,"  SUPER + CTRL + ALT + M  "))
        verify(Model.matches(row,"SUPER+CTRL+ALT+M"))
        verify(Model.matches(row,"super +ctrl+ alt +m"))
        verify(Model.matches(row,"super ctrl alt m"))
        verify(Model.matches(row," super   ctrl+alt m "))
        verify(Model.matches(row,"Screen shot"))
        verify(!Model.matches(row,"SUPER+CTRL+ALT+N"))
    }
}
