import Cocoa
import InputMethodKit
import os

@objc(InputController) public class InputController: IMKInputController {

    private let logger = Logger(
        subsystem: "Vic-Shih.inputmethod.unicorn", category: "InputController")

    public required override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
    }

    lazy var engine: Engine? = {
        guard let path = Bundle.main.path(forResource: "keymap", ofType: "json") else {
            logger.error("Unicorn Error: keymap.json not found in bundle.")
            return nil
        }
        do {
            return try Engine.newFromPath(path: path)
        } catch {
            logger.error("Unicorn Error: Failed to load engine: \(error.localizedDescription)")
            return nil
        }
    }()

    // MARK: - Lifecycle

    public override func deactivateServer(_ sender: Any!) {
        engine?.deactivate()
        candidatesWindow?.hide()
        super.deactivateServer(sender)
    }

    // MARK: - Event Handling
    @objc(handleEvent:client:)
    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }
        guard let engine = self.engine else { return false }

        // 1. Convert to KeyCode
        guard let keyCode = KeyCode(event: event) else {
            return false  // Let system handle (Shortcuts, etc)
        }

        // 2. Process Key
        // The engine now handles implicit commits internally.
        // It returns [.commit(text), .reject] if an active sequence is interrupted.
        let actions = engine.processKey(keyCode: keyCode)

        if actions.isEmpty {
            return false
        }

        guard let client = sender as? IMKTextInput else { return true }

        // 3. Process Actions
        var shouldConsumeEvent = true

        for action in actions {
            switch action {
            case .reject:
                // If the engine rejects the key, we should let the system handle it.
                // This happens in two cases:
                // a) Inactive + Key (e.g. typing 'a') -> .reject -> System inserts 'a'.
                // b) Active + Invalid Key (e.g. '\lamb' + 'x') -> [.commit('λ'), .reject] -> System inserts 'x' after commit.
                shouldConsumeEvent = false

            case .updateComposition(let text):
                handleUpdate(text, showCandidates: false, client: client)

            case .showCandidates(let text):
                handleUpdate(text, showCandidates: true, client: client)

            case .commit(let text):
                commitText(text, client: client, shouldDeactivate: false)

            case .navigate(let direction):
                switch direction {
                case .up: candidatesWindow?.moveUp(nil)
                case .down: candidatesWindow?.moveDown(nil)
                case .pageUp: candidatesWindow?.moveLeft(nil)
                case .pageDown: candidatesWindow?.moveRight(nil)
                }
            }
        }

        return shouldConsumeEvent
    }

    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        return false
    }

    private func handleActions(_ actions: [EngineAction], client: IMKTextInput) {
        for action in actions {
            switch action {
            case .reject:
                break  // Should be handled by caller if needed
            case .updateComposition(let text):
                handleUpdate(text, showCandidates: false, client: client)
            case .showCandidates(let text):
                handleUpdate(text, showCandidates: true, client: client)
            case .commit(let text):
                commitText(text, client: client, shouldDeactivate: false)
            case .navigate(let direction):
                // Engine state already updated. Just sync UI.
                switch direction {
                case .up: candidatesWindow?.moveUp(nil)
                case .down: candidatesWindow?.moveDown(nil)
                case .pageUp: candidatesWindow?.moveLeft(nil)  // Left is PageUp in this UI
                case .pageDown: candidatesWindow?.moveRight(nil)
                }
            }
        }
    }

    private func handleUpdate(_ text: String, showCandidates: Bool, client: IMKTextInput) {
        client.setMarkedText(
            text,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

        if showCandidates {
            candidatesWindow?.update()
            candidatesWindow?.show()
        } else {
            candidatesWindow?.hide()
        }
    }

    private func commitText(_ text: String, client: IMKTextInput?, shouldDeactivate: Bool = true) {
        client?.insertText(
            text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        candidatesWindow?.hide()
        if shouldDeactivate {
            engine?.deactivate()
        }
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        return engine?.getCandidates() ?? []
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client() else { return }
        commitText(candidateString.string, client: client)
    }
}
