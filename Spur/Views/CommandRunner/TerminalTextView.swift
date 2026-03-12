import AppKit
import SwiftUI

/// NSViewRepresentable wrapping NSTextView for colored terminal output.
struct TerminalTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor(white: 0.85, alpha: 1)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let storage = textView.textStorage!
        // Only update if content changed (avoid expensive full-replace on every render)
        guard storage.string != attributedText.string ||
              storage.length != attributedText.length else { return }
        storage.setAttributedString(attributedText)
        // Scroll to end
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var textView: NSTextView?
    }
}
