.pragma library

function clone(value) { return JSON.parse(JSON.stringify(value)) }
function uid() { return 'm' + Date.now().toString(36) + Math.random().toString(36).slice(2, 9) }
function matches(row, query) { return JSON.stringify(row).toLowerCase().indexOf(query.toLowerCase()) >= 0 }
function keyName(event) {
    var k = event.key
    if (k >= 0x01000030 && k <= 0x01000052) return 'F' + (k - 0x01000030 + 1)
    var names = {16777216:'Escape',16777217:'Tab',16777218:'ISO_Left_Tab',16777219:'BackSpace',16777220:'Return',16777221:'KP_Enter',16777222:'Insert',16777223:'Delete',16777224:'Pause',16777225:'Print',16777232:'Home',16777233:'End',16777234:'Left',16777235:'Up',16777236:'Right',16777237:'Down',16777238:'Prior',16777239:'Next',32:'space',43:'plus',44:'comma',45:'minus',46:'period',47:'slash',59:'semicolon',61:'equal',91:'bracketleft',92:'backslash',93:'bracketright',96:'grave',39:'apostrophe',16777328:'XF86AudioLowerVolume',16777329:'XF86AudioMute',16777330:'XF86AudioRaiseVolume',16777344:'XF86AudioPlay',16777345:'XF86AudioStop',16777346:'XF86AudioPrev',16777347:'XF86AudioNext',16777349:'XF86AudioPause',16777394:'XF86MonBrightnessUp',16777395:'XF86MonBrightnessDown'}
    if (names[k]) return names[k]
    if (k === 0x01000024) return 'Caps_Lock'
    if (k === 0x01000025) return 'Num_Lock'
    if (k === 0x01000026) return 'Scroll_Lock'
    if (k >= 48 && k <= 90) return String.fromCharCode(k)
    if (event.nativeScanCode > 0) return 'code:' + event.nativeScanCode
    return ''
}
function capture(event) {
    if (event.isAutoRepeat || (event.key >= 0x01000020 && event.key <= 0x01000023) || event.key === 0x01001103) return ''
    var key = keyName(event)
    if (event.modifiers & 0x20000000) {
        if(event.key >= 48 && event.key <= 57) key='KP_' + String.fromCharCode(event.key)
        else {
            var keypad={43:'KP_Add',45:'KP_Subtract',42:'KP_Multiply',47:'KP_Divide',46:'KP_Decimal',44:'KP_Separator'}
            if(keypad[event.key])key=keypad[event.key]
        }
    }
    if (!key) return ''
    var mods = []
    if (event.modifiers & 0x10000000) mods.push('SUPER')
    if (event.modifiers & 0x04000000) mods.push('CTRL')
    if (event.modifiers & 0x08000000) mods.push('ALT')
    if (event.modifiers & 0x02000000) mods.push('SHIFT')
    if (event.modifiers & 0x40000000) mods.push('MOD5')
    return mods.concat([key]).join(' + ')
}
