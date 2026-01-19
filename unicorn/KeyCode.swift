import Cocoa

public enum KeyCode: Equatable {
    case up
    case down
    case left
    case right
    case backspace
    case enter
    case chars(String)

    public init?(event: NSEvent) {
        // Only handle keyDown
        guard event.type == .keyDown else { return nil }

        // Standard macOS text handling:
        // Command and Control are reserved for system shortcuts (Copy, Paste, Save).
        // Shift is for capitalization (Text).
        // Option is for special characters (Text) (e.g. Option+e -> ´).
        // We only filter out Command and Control.
        let modifiers = event.modifierFlags.intersection([.command, .control])
        if !modifiers.isEmpty {
            return nil
        }

        switch event.keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 51: self = .backspace
        case 36, 76: self = .enter
        default:
            if let chars = event.characters {
                self = .chars(chars)
            } else {
                return nil
            }
        }
    }
}