import AppKit
import SwiftUI
import WebKit

/// A window that tiles 2-4 game streams side by side in a grid
class MultiviewWindow: NSWindow {
    init(urls: [(url: URL, title: String)]) {
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1440, height: 900)
        let width = min(screenSize.width * 0.85, 1400)
        let height = min(screenSize.height * 0.85, 900)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Sports Multiview (\(urls.count) games)"
        self.minSize = NSSize(width: 800, height: 500)
        self.contentViewController = NSHostingController(
            rootView: MultiviewContentView(streams: urls)
        )
        self.center()
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Multiview Grid Layout

struct MultiviewContentView: View {
    let streams: [(url: URL, title: String)]
    @State private var focusedIndex: Int? = nil

    private var columns: Int {
        streams.count <= 1 ? 1 : 2
    }

    private var rows: Int {
        (streams.count + 1) / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "rectangle.split.2x2.fill")
                    .foregroundStyle(.orange)
                Text("Multiview — \(streams.count) streams")
                    .font(.headline)
                Spacer()
                if focusedIndex != nil {
                    Button {
                        withAnimation { focusedIndex = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.split.2x2")
                                .font(.caption)
                            Text("Show All")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Grid of streams
            if let focused = focusedIndex, focused < streams.count {
                // Single focused stream
                streamCell(index: focused)
            } else {
                // Grid layout
                GeometryReader { geo in
                    let cellWidth = geo.size.width / CGFloat(columns)
                    let cellHeight = geo.size.height / CGFloat(rows)

                    VStack(spacing: 1) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: 1) {
                                ForEach(0..<columns, id: \.self) { col in
                                    let index = row * columns + col
                                    if index < streams.count {
                                        streamCell(index: index)
                                            .frame(width: cellWidth - 1, height: cellHeight - 1)
                                    } else {
                                        Color.black.opacity(0.3)
                                            .frame(width: cellWidth - 1, height: cellHeight - 1)
                                            .overlay {
                                                VStack(spacing: 8) {
                                                    Image(systemName: "plus.rectangle.on.rectangle")
                                                        .font(.title2)
                                                        .foregroundStyle(.secondary)
                                                    Text("Empty slot")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.black)
                }
            }
        }
    }

    private func streamCell(index: Int) -> some View {
        let stream = streams[index]
        return ZStack(alignment: .topLeading) {
            WatchWebView(initialURL: stream.url)

            // Game label overlay
            HStack(spacing: 6) {
                Text(stream.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if focusedIndex == nil {
                    Button {
                        withAnimation { focusedIndex = index }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Focus this stream")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6))
        }
    }
}
