#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="Sources/MagSafeDark/main.swift"

[[ -f "$SOURCE" ]] || {
  print -u2 "Missing GUI source: $SOURCE"
  exit 66
}

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
original = text

text = text.replace(
    '    private enum IconStyle: String { case monochrome, actualColor }\n',
    '    private enum IconStyle: String { case monochrome, actualColor }\n'
    '    private enum StatusGlyphStyle: String { case battery, lightbulb }\n',
    1,
)

text = text.replace(
    '    private let iconStyleKey = "statusIconStyle"\n',
    '    private let iconStyleKey = "statusIconStyle"\n'
    '    private let statusGlyphStyleKey = "statusGlyphStyle"\n',
    1,
)

text = text.replace(
    '            restoreModeKey: false,\n',
    '            restoreModeKey: false,\n'
    '            statusGlyphStyleKey: StatusGlyphStyle.battery.rawValue,\n',
    1,
)

icon_style_block = '''    private var iconStyle: IconStyle {
        get { IconStyle(rawValue: defaults.string(forKey: iconStyleKey) ?? "") ?? .monochrome }
        set { defaults.set(newValue.rawValue, forKey: iconStyleKey) }
    }
'''
status_style_block = icon_style_block + '''
    private var statusGlyphStyle: StatusGlyphStyle {
        get { StatusGlyphStyle(rawValue: defaults.string(forKey: statusGlyphStyleKey) ?? "") ?? .battery }
        set { defaults.set(newValue.rawValue, forKey: statusGlyphStyleKey) }
    }
'''
if 'private var statusGlyphStyle: StatusGlyphStyle' not in text:
    if icon_style_block not in text:
        raise SystemExit('Could not find iconStyle property')
    text = text.replace(icon_style_block, status_style_block, 1)

appearance_anchor = '        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))\n'
glyph_menu = '''        settings.addItem(submenu(text("Вид значка", "Icon appearance"), appearance))

        let glyphs = NSMenu()
        let batteryGlyph = item(text("Батарея", "Battery"), #selector(useBatteryStatusGlyph))
        batteryGlyph.state = statusGlyphStyle == .battery ? .on : .off
        glyphs.addItem(batteryGlyph)
        let lightbulbGlyph = item(text("Лампочка MagSafe", "MagSafe lightbulb"), #selector(useLightbulbStatusGlyph))
        lightbulbGlyph.state = statusGlyphStyle == .lightbulb ? .on : .off
        glyphs.addItem(lightbulbGlyph)
        settings.addItem(submenu(text("Значок состояния", "Status icon"), glyphs))
'''
if '#selector(useBatteryStatusGlyph)' not in text:
    if appearance_anchor not in text:
        raise SystemExit('Could not find icon appearance menu anchor')
    text = text.replace(appearance_anchor, glyph_menu, 1)

plug_method_anchor = '''    private func configuredPlugSymbol() -> NSImage? {
'''
lightbulb_method = '''    private func makeLightbulbStatusIcon(mode: UInt8?) -> NSImage {
        let symbolName = "lightbulb.led.fill"
        let base = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let indicatorColor: NSColor
        switch mode {
        case 1:
            indicatorColor = .tertiaryLabelColor
        case 3:
            indicatorColor = .systemGreen
        case 4, 5, 6, 7, 19:
            indicatorColor = .systemOrange
        default:
            indicatorColor = .labelColor
        }
        let palette = NSImage.SymbolConfiguration(
            paletteColors: [indicatorColor, NSColor.secondaryLabelColor]
        )
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: text("Состояние индикатора MagSafe: \\(modeName(mode))", "MagSafe LED state: \\(modeName(mode))")
        )?.withSymbolConfiguration(base.applying(palette)) ?? NSImage(size: NSSize(width: 19, height: 18))
        image.isTemplate = false
        return image
    }

'''
if 'private func makeLightbulbStatusIcon' not in text:
    if plug_method_anchor not in text:
        raise SystemExit('Could not find plug symbol method anchor')
    text = text.replace(plug_method_anchor, lightbulb_method + plug_method_anchor, 1)

old_image = '        statusBatteryImageView?.image = makeBatteryStatusIcon(kind: kind, mode: mode)\n'
new_image = '''        if statusGlyphStyle == .lightbulb {
            statusBatteryImageView?.image = makeLightbulbStatusIcon(mode: mode)
        } else {
            statusBatteryImageView?.image = makeBatteryStatusIcon(kind: kind, mode: mode)
        }
'''
if old_image in text:
    text = text.replace(old_image, new_image, 1)
elif 'statusGlyphStyle == .lightbulb' not in text:
    raise SystemExit('Could not find status battery image assignment')

text = text.replace(
    '        let showPlug = kind == .plugged\n',
    '        let showPlug = statusGlyphStyle == .battery && kind == .plugged\n',
    1,
)

method_anchor = '''    @objc private func useMonochromeIcon() {
'''
glyph_actions = '''    @objc private func useBatteryStatusGlyph() {
        statusGlyphStyle = .battery
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

    @objc private func useLightbulbStatusGlyph() {
        statusGlyphStyle = .lightbulb
        updateStatusIcon(mode: cachedMode, remaining: cachedTimerRemaining)
        rebuildMenu()
    }

'''
if 'private func useBatteryStatusGlyph()' not in text:
    if method_anchor not in text:
        raise SystemExit('Could not find icon action anchor')
    text = text.replace(method_anchor, glyph_actions + method_anchor, 1)

for marker in [
    'private enum StatusGlyphStyle: String { case battery, lightbulb }',
    'private let statusGlyphStyleKey = "statusGlyphStyle"',
    'private var statusGlyphStyle: StatusGlyphStyle',
    'systemSymbolName: symbolName',
    'let symbolName = "lightbulb.led.fill"',
    'text("Значок состояния", "Status icon")',
    '#selector(useBatteryStatusGlyph)',
    '#selector(useLightbulbStatusGlyph)',
    'statusGlyphStyle == .battery && kind == .plugged',
]:
    if marker not in text:
        raise SystemExit(f'Missing status glyph marker: {marker}')

if text != original:
    path.write_text(text)
    print('Prepared selectable battery and MagSafe lightbulb status icons')
else:
    print('Selectable status icon style already prepared')
PY
