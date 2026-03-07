import SwiftUI

// TODO: [Phase 4] Implement full auto-scrolling behavior — see agents.md Prompt 7.

struct LogOutputView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines.indices, id: \.self) { i in
                        Text(lines[i])
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .id(i)
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.85))
            .onChange(of: lines.count) { _ in
                if let last = lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}
