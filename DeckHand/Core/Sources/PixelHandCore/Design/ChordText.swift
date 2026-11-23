//
//  ChordText.swift
//  PixelHandCore – Design
//
//  A key chord as the chip's mono chord text (`["cmd", "shift", "z"]` →
//  `⇧⌘Z`), in the Mac's modifier order: ⌃ ⌥ ⇧ ⌘.
//

import Foundation

public enum ChordText {
    public static func glyphs(_ keys: [String]) -> String {
        var control = "", option = "", shift = "", command = "", function = ""
        var literal = ""
        for raw in keys {
            switch raw.lowercased() {
            case "cmd", "command": command = "⌘"
            case "shift": shift = "⇧"
            case "option", "alt": option = "⌥"
            case "ctrl", "control": control = "⌃"
            case "fn": function = "fn"
            case "space": literal += "␣"
            case "return", "enter": literal += "↩"
            case "tab": literal += "⇥"
            case "escape", "esc": literal += "esc"
            case "delete", "backspace": literal += "⌫"
            case "up": literal += "↑"
            case "down": literal += "↓"
            case "left": literal += "←"
            case "right": literal += "→"
            default: literal += raw.uppercased()
            }
        }
        return function + control + option + shift + command + literal
    }
}
