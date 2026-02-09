import AppKit
import Carbon

struct Hotkey: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32

  static let `default` = Hotkey(
    keyCode: UInt32(kVK_ANSI_S),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  static let startRecordingDefault = Hotkey(
    keyCode: UInt32(kVK_ANSI_R),
    modifiers: UInt32(cmdKey | shiftKey)
  )

  var displayString: String {
    var parts: [String] = []
    let flags = modifierFlags
    if flags.contains(.command) { parts.append("⌘") }
    if flags.contains(.shift) { parts.append("⇧") }
    if flags.contains(.option) { parts.append("⌥") }
    if flags.contains(.control) { parts.append("⌃") }
    parts.append(keyDisplayString)
    return parts.joined()
  }

  var modifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    return flags
  }

  var menuKeyEquivalent: String {
    keyEquivalentMap[keyCode] ?? ""
  }

  private var keyDisplayString: String {
    if let mapped = keyCodeMap[keyCode] {
      return mapped
    }
    return "?"
  }
}

extension NSEvent.ModifierFlags {
  var carbonModifiers: UInt32 {
    var value: UInt32 = 0
    if contains(.command) { value |= UInt32(cmdKey) }
    if contains(.shift) { value |= UInt32(shiftKey) }
    if contains(.option) { value |= UInt32(optionKey) }
    if contains(.control) { value |= UInt32(controlKey) }
    return value
  }
}

private let keyCodeMap: [UInt32: String] = [
  UInt32(kVK_ANSI_A): "A",
  UInt32(kVK_ANSI_B): "B",
  UInt32(kVK_ANSI_C): "C",
  UInt32(kVK_ANSI_D): "D",
  UInt32(kVK_ANSI_E): "E",
  UInt32(kVK_ANSI_F): "F",
  UInt32(kVK_ANSI_G): "G",
  UInt32(kVK_ANSI_H): "H",
  UInt32(kVK_ANSI_I): "I",
  UInt32(kVK_ANSI_J): "J",
  UInt32(kVK_ANSI_K): "K",
  UInt32(kVK_ANSI_L): "L",
  UInt32(kVK_ANSI_M): "M",
  UInt32(kVK_ANSI_N): "N",
  UInt32(kVK_ANSI_O): "O",
  UInt32(kVK_ANSI_P): "P",
  UInt32(kVK_ANSI_Q): "Q",
  UInt32(kVK_ANSI_R): "R",
  UInt32(kVK_ANSI_S): "S",
  UInt32(kVK_ANSI_T): "T",
  UInt32(kVK_ANSI_U): "U",
  UInt32(kVK_ANSI_V): "V",
  UInt32(kVK_ANSI_W): "W",
  UInt32(kVK_ANSI_X): "X",
  UInt32(kVK_ANSI_Y): "Y",
  UInt32(kVK_ANSI_Z): "Z",
  UInt32(kVK_ANSI_0): "0",
  UInt32(kVK_ANSI_1): "1",
  UInt32(kVK_ANSI_2): "2",
  UInt32(kVK_ANSI_3): "3",
  UInt32(kVK_ANSI_4): "4",
  UInt32(kVK_ANSI_5): "5",
  UInt32(kVK_ANSI_6): "6",
  UInt32(kVK_ANSI_7): "7",
  UInt32(kVK_ANSI_8): "8",
  UInt32(kVK_ANSI_9): "9",
  UInt32(kVK_Return): "↩",
  UInt32(kVK_Tab): "⇥",
  UInt32(kVK_Space): "Space",
  UInt32(kVK_Delete): "⌫",
  UInt32(kVK_Escape): "⎋",
  UInt32(kVK_LeftArrow): "←",
  UInt32(kVK_RightArrow): "→",
  UInt32(kVK_UpArrow): "↑",
  UInt32(kVK_DownArrow): "↓"
]

private let keyEquivalentMap: [UInt32: String] = [
  UInt32(kVK_ANSI_A): "a",
  UInt32(kVK_ANSI_B): "b",
  UInt32(kVK_ANSI_C): "c",
  UInt32(kVK_ANSI_D): "d",
  UInt32(kVK_ANSI_E): "e",
  UInt32(kVK_ANSI_F): "f",
  UInt32(kVK_ANSI_G): "g",
  UInt32(kVK_ANSI_H): "h",
  UInt32(kVK_ANSI_I): "i",
  UInt32(kVK_ANSI_J): "j",
  UInt32(kVK_ANSI_K): "k",
  UInt32(kVK_ANSI_L): "l",
  UInt32(kVK_ANSI_M): "m",
  UInt32(kVK_ANSI_N): "n",
  UInt32(kVK_ANSI_O): "o",
  UInt32(kVK_ANSI_P): "p",
  UInt32(kVK_ANSI_Q): "q",
  UInt32(kVK_ANSI_R): "r",
  UInt32(kVK_ANSI_S): "s",
  UInt32(kVK_ANSI_T): "t",
  UInt32(kVK_ANSI_U): "u",
  UInt32(kVK_ANSI_V): "v",
  UInt32(kVK_ANSI_W): "w",
  UInt32(kVK_ANSI_X): "x",
  UInt32(kVK_ANSI_Y): "y",
  UInt32(kVK_ANSI_Z): "z",
  UInt32(kVK_ANSI_0): "0",
  UInt32(kVK_ANSI_1): "1",
  UInt32(kVK_ANSI_2): "2",
  UInt32(kVK_ANSI_3): "3",
  UInt32(kVK_ANSI_4): "4",
  UInt32(kVK_ANSI_5): "5",
  UInt32(kVK_ANSI_6): "6",
  UInt32(kVK_ANSI_7): "7",
  UInt32(kVK_ANSI_8): "8",
  UInt32(kVK_ANSI_9): "9"
]
