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
        guard let event = event, 
              let engine = self.engine,
              let keyCode = KeyCode(event: event) else { 
            return false 
        }

        let actions = engine.processKey(keyCode: keyCode)
        if actions.isEmpty { return false }

        guard let client = sender as? IMKTextInput else { return true }

        var shouldConsumeEvent = true

        for action in actions {
            switch action {
            case .reject:
                shouldConsumeEvent = false
            case .sync:
                syncUI(with: engine.state, client: client)
            case .navigate(let direction):
                handleNavigation(direction)
            case .commit(let text):
                commitText(text, client: client)
            }
        }

        return shouldConsumeEvent
    }

    /// Handles explicit navigation commands for the candidate window.
    private func handleNavigation(_ direction: CandidateNavigation) {
        switch direction {
        case .up: candidatesWindow?.moveUp(nil)
        case .down: candidatesWindow?.moveDown(nil)
        case .pageUp: candidatesWindow?.moveLeft(nil) // IMK uses Left for PageUp in vertical panels
        case .pageDown: candidatesWindow?.moveRight(nil)
        }
    }

    /// Synchronizes the macOS UI with the Engine's Presentation Model.
    private func syncUI(with state: EngineState, client: IMKTextInput) {
        // Tier 3: Framework Glue - Map presentation functions to system APIs
        client.setMarkedText(
            state.compositionText(),
            selectionRange: state.selectionRange(),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )

        if state.shouldShowCandidates() {
            candidatesWindow?.update()
            candidatesWindow?.show()
        } else {
            candidatesWindow?.hide()
        }
    }

    private func commitText(_ text: String, client: IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        candidatesWindow?.hide()
        // Note: Engine state is already reset by the Engine when it returns .commit
    }

    public override func candidates(_ sender: Any!) -> [Any]! {
        return engine?.state.candidates() ?? []
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client() else { return }
        // When a candidate is clicked, we commit it.
        // We'll let the engine state catch up on the next sync if needed, 
        // but typically IMK handles candidate selection by calling this.
        commitText(candidateString.string, client: client)
        engine?.deactivate()
    }
}
