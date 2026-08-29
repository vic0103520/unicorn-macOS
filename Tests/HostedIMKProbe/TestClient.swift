import AppKit
import Foundation

private let textViewIdentifier = "unicorn-hosted-imk-probe-text-view"

private final class DiagnosticsWriter {
    private let currentURL: URL
    private let timelineURL: URL
    private var lastSignature: Data?

    init(currentPath: String, timelinePath: String) {
        self.currentURL = URL(fileURLWithPath: currentPath)
        self.timelineURL = URL(fileURLWithPath: timelinePath)
    }

    func record(textView: NSTextView, window: NSWindow?) {
        let markedRange = textView.markedRange()
        let selectedRange = textView.selectedRange()
        let scalars = textView.string.unicodeScalars.map {
            String(format: "U+%04X", $0.value)
        }
        let signature: [String: Any] = [
            "text": textView.string,
            "textScalars": scalars,
            "hasMarkedText": textView.hasMarkedText(),
            "markedRange": rangeValue(markedRange),
            "selectedRange": rangeValue(selectedRange),
            "firstResponder": window?.firstResponder === textView,
            "windowIsKey": window?.isKeyWindow ?? false,
            "applicationIsActive": NSApplication.shared.isActive,
            "accessibilityIdentifier": textViewIdentifier,
        ]

        guard JSONSerialization.isValidJSONObject(signature),
            let signatureData = try? JSONSerialization.data(
                withJSONObject: signature, options: [.sortedKeys]
            )
        else {
            return
        }

        var snapshot = signature
        snapshot["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard let snapshotData = try? JSONSerialization.data(
            withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: currentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? snapshotData.write(to: currentURL, options: .atomic)

        guard signatureData != lastSignature else { return }
        lastSignature = signatureData
        appendTimeline(snapshot)
    }

    private func appendTimeline(_ snapshot: [String: Any]) {
        guard var data = try? JSONSerialization.data(
            withJSONObject: snapshot, options: [.sortedKeys]
        ) else {
            return
        }
        data.append(0x0A)

        if !FileManager.default.fileExists(atPath: timelineURL.path) {
            FileManager.default.createFile(atPath: timelineURL.path, contents: data)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: timelineURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rangeValue(_ range: NSRange) -> [String: Int] {
        let location = range.location == NSNotFound ? -1 : range.location
        return ["location": location, "length": range.length]
    }
}

private final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?
    private var diagnostics: DiagnosticsWriter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let currentPath = environment["UNICORN_PROBE_DIAGNOSTICS"]
            ?? NSTemporaryDirectory() + "/unicorn-hosted-imk-probe-current.json"
        let timelinePath = environment["UNICORN_PROBE_TIMELINE"]
            ?? NSTemporaryDirectory() + "/unicorn-hosted-imk-probe-timeline.jsonl"
        let diagnostics = DiagnosticsWriter(
            currentPath: currentPath,
            timelinePath: timelinePath
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Unicorn Hosted InputMethodKit Probe"
        window.center()

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]

        let instruction = NSTextField(labelWithString: "Focus the text view, then type backslash, l, and Enter")
        instruction.frame = NSRect(x: 24, y: 356, width: 672, height: 28)
        instruction.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        instruction.setAccessibilityIdentifier("unicorn-hosted-imk-probe-instruction")
        contentView.addSubview(instruction)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 28, width: 672, height: 312))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 30)
        textView.string = ""
        textView.setAccessibilityIdentifier(textViewIdentifier)
        textView.setAccessibilityLabel("Unicorn hosted InputMethodKit probe text view")
        scrollView.documentView = textView
        contentView.addSubview(scrollView)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
        self.textView = textView
        self.diagnostics = diagnostics
        diagnostics.record(textView: textView, window: window)

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let textView = self.textView else { return }
            self.diagnostics?.record(textView: textView, window: self.window)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let textView {
            diagnostics?.record(textView: textView, window: window)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
private enum ProbeClientMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = ProbeAppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
