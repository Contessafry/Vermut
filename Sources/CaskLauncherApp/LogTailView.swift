import AppKit
import SwiftUI
import CaskLauncherCore

/// Bounded live-tail viewer. Reads off the main thread and never hosts one giant SwiftUI `Text`.
struct LogTailPane: View {
    let url: URL
    @State private var snapshot = LogTailSnapshot.empty
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: VermutSpace.s2) {
            ZStack {
                LogTextView(
                    text: displayText,
                    revision: snapshot.fileSize
                )
                .opacity(snapshot.lines.isEmpty && !isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if snapshot.lines.isEmpty {
                    Text("No log file yet. Launch the store to capture output.")
                        .font(VermutType.mono)
                        .foregroundStyle(Color.Vermut.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(VermutSpace.s3)
                }
            }
            .frame(minHeight: 280, idealHeight: 360, maxHeight: 480)
            .background(Color.Vermut.muted)
            .overlay(
                RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous)
                    .strokeBorder(Color.Vermut.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: VermutRadius.md, style: .continuous))

            if snapshot.truncated {
                Text("Showing the last \(snapshot.lines.count) lines of \(ByteFormat.string(Int64(snapshot.fileSize))).")
                    .font(VermutType.captionRegular)
                    .foregroundStyle(Color.Vermut.mutedForeground)
            }
        }
        .task(id: url.path) {
            await followLog()
        }
    }

    private var displayText: String {
        snapshot.text
    }

    @MainActor
    private func followLog() async {
        isLoading = true
        var previous = LogTailFingerprint(size: -1, modificationDate: nil)
        let url = url
        while !Task.isCancelled {
            let captured = previous
            let result = await Task.detached(priority: .utility) { () -> (LogTailFingerprint, LogTailSnapshot?) in
                let fingerprint = LogTail.fingerprint(at: url)
                guard LogTail.shouldReload(previous: captured, current: fingerprint) else {
                    return (fingerprint, nil)
                }
                return (fingerprint, LogTail.read(from: url))
            }.value
            previous = result.0
            if let snap = result.1 {
                snapshot = snap
            }
            isLoading = false
            do {
                try await Task.sleep(nanoseconds: LogTail.defaultPollIntervalNanoseconds)
            } catch {
                break
            }
        }
    }
}

/// AppKit text view so CoreText layout stays incremental. SwiftUI `Text` inside a
/// `ScrollView` measures the whole string on the main thread.
struct LogTextView: NSViewRepresentable {
    var text: String
    var revision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LogScrollContainer {
        LogScrollContainer()
    }

    func updateNSView(_ container: LogScrollContainer, context: Context) {
        guard context.coordinator.revision != revision || container.textView.string != text else {
            return
        }
        context.coordinator.revision = revision
        let stickToBottom = container.isNearBottom
        container.textView.string = text
        if stickToBottom {
            container.scrollToEnd()
        }
    }

    final class Coordinator {
        var revision = -1
    }
}

final class LogScrollContainer: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.labelColor
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.lineFragmentPadding = 4
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        scrollView.documentView = textView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 360)
    }

    var isNearBottom: Bool {
        let clip = scrollView.contentView.bounds
        let documentHeight = textView.bounds.height
        return documentHeight - clip.maxY < 32
    }

    func scrollToEnd() {
        textView.scrollToEndOfDocument(nil)
    }
}
