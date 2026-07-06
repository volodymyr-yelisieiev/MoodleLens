//
//  AskController.swift
//  MoodleLens
//

import AppKit
import SwiftUI

final class AskController {
    static let shared = AskController()
    static let autoHideSeconds: TimeInterval = 10
    static let historyDidChange = Notification.Name("AskHistoryDidChange")
    static let source = "ask"

    private let openAIClient: OpenAIClientProtocol
    private let screenshotService: ScreenshotServiceProtocol
    private let permissionManager: PermissionManagerProtocol
    private let notificationService: NotificationServiceProtocol
    private let browserContextProvider: ([String: Any]?) -> [String: Any]?

    private var observers: [NSObjectProtocol] = []
    private var history: [Message] = []
    private var isRunning = false
    private var bubbleWindow: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var pendingRequestID: String?
    private var lastBubbleText: String?
    private static let bubbleSize = NSSize(width: 420, height: 280)

    init(
        openAIClient: OpenAIClientProtocol = DIContainer.shared.resolve(OpenAIClientProtocol.self) ?? OpenAIClient.shared,
        screenshotService: ScreenshotServiceProtocol = DIContainer.shared.resolve(ScreenshotServiceProtocol.self) ?? ScreenshotService.shared,
        permissionManager: PermissionManagerProtocol = DIContainer.shared.resolve(PermissionManagerProtocol.self) ?? PermissionManager.shared,
        notificationService: NotificationServiceProtocol = DIContainer.shared.resolve(NotificationServiceProtocol.self) ?? DefaultNotificationService(),
        browserContextProvider: @escaping ([String: Any]?) -> [String: Any]? = BrowserContextProvider.addCurrentContext(to:)
    ) {
        self.openAIClient = openAIClient
        self.screenshotService = screenshotService
        self.permissionManager = permissionManager
        self.notificationService = notificationService
        self.browserContextProvider = browserContextProvider
        observeScreenshotEvents()
    }

    func ask() {
        guard !isRunning else { return }

        guard openAIClient.isConfigured() else {
            showBubble("AI provider is not configured.", autoHide: true)
            return
        }

        permissionManager.screenCapturePermissionStatus { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.finishRequest()
                    self.showBubble("Screen Recording permission is required.", autoHide: true)
                    return
                }

                let requestID = UUID().uuidString
                self.pendingRequestID = requestID
                self.isRunning = true
                var contextInfo: [String: Any] = [
                    "source": Self.source,
                    "requestID": requestID,
                    "deferAnalysis": true
                ]
                contextInfo = self.browserContextProvider(contextInfo) ?? contextInfo
                if let browserFailure = contextInfo[BrowserContextProvider.failureMessageKey] as? String {
                    self.finishRequest()
                    self.showBubble(browserFailure, autoHide: true)
                    return
                }

                if self.screenshotService.captureScreenshot(contextInfo: contextInfo) == false {
                    self.finishRequest()
                    self.showBubble("Could not start screenshot capture.", autoHide: true)
                }
            }
        }
    }

    func toggleBubble() {
        if bubbleWindow?.isVisible == true {
            hideBubble()
        } else if lastBubbleText != nil || !history.isEmpty {
            showBubble(lastBubbleText ?? "")
        }
    }

    func clearHistory() {
        hideBubble()
        history.removeAll()
        lastBubbleText = nil
        pendingRequestID = nil
        isRunning = false
        notifyHistoryChanged()
        _ = TempFileManager.shared.cleanupAllTempFiles()
    }

    var historyCount: Int {
        history.count
    }

    func sessionHistorySnapshot() -> [Message] {
        history
    }

    var lastBubbleTextForTesting: String? {
        lastBubbleText
    }

    var isAutoHideScheduledForTesting: Bool {
        hideWorkItem != nil
    }

    var isBubbleVisibleForTesting: Bool {
        bubbleWindow?.isVisible == true
    }

    private func observeScreenshotEvents() {
        let captured = notificationService.addObserverForName(.screenshotCaptured, object: nil, queue: .main) { [weak self] notification in
            DispatchQueue.main.async {
                self?.handleScreenshotCaptured(notification)
            }
        }
        observers.append(captured)

        let error = notificationService.addObserverForName(.screenshotError, object: nil, queue: .main) { [weak self] notification in
            DispatchQueue.main.async {
                self?.handleScreenshotError(notification)
            }
        }
        observers.append(error)
    }

    private func handleScreenshotCaptured(_ notification: Notification) {
        guard let payload = notification.object as? [String: Any],
              payload["source"] as? String == Self.source,
              payload["requestID"] as? String == pendingRequestID,
              let path = payload["path"] as? String else {
            return
        }

        let imageURL = URL(fileURLWithPath: path)
        guard let browserContext = payload[BrowserContextProvider.contextInfoKey] as? String,
              !browserContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            TempFileManager.shared.deleteTempFile(imageURL)
            finishRequest()
            showBubble(BrowserContextProvider.FailureReason.noExtractableMoodleTask.userMessage, autoHide: true)
            return
        }

        sendAskImage(
            imageURL,
            browserContext: browserContext,
            screenshotScope: payload[ScreenshotService.screenshotScopeKey] as? String ?? ScreenshotService.screenshotScopeDisplayViewport,
            userLabel: "Screenshot"
        )
    }

    private func sendAskImage(_ imageURL: URL, browserContext: String, screenshotScope: String, userLabel: String) {
        let prompt = buildPrompt(browserContext: browserContext, screenshotScope: screenshotScope)
        Task {
            defer {
                TempFileManager.shared.deleteTempFile(imageURL)
            }

            do {
                let response = try await openAIClient.sendImageRequest(
                    imageURL: imageURL,
                    prompt: prompt,
                    contextInfo: ["source": Self.source]
                )
                await MainActor.run {
                    self.history.append(Message(text: userLabel, type: .user))
                    self.history.append(Message(text: response, type: .assistant))
                    self.notifyHistoryChanged()
                    self.showBubble(response, autoHide: true)
                    self.finishRequest()
                }
            } catch {
                await MainActor.run {
                    self.showBubble(AIServiceError.from(error).localizedDescription, autoHide: true)
                    self.finishRequest()
                }
            }
        }
    }

    private func handleScreenshotError(_ notification: Notification) {
        guard let payload = notification.object as? [String: Any],
              payload["source"] as? String == Self.source,
              payload["requestID"] as? String == pendingRequestID else {
            return
        }

        let error = payload["error"] as? String ?? "Could not capture screenshot."
        finishRequest()
        showBubble(error, autoHide: true)
    }

    private func buildPrompt(browserContext: String, screenshotScope: String) -> String {
        let basePrompt = SettingsManager.shared.screenshotContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let screenshotScopeText = screenshotScope == ScreenshotService.screenshotScopeDisplayViewport
            ? "Current display/viewport screenshot. This is not a guaranteed full-page browser capture."
            : screenshotScope
        let evidenceBlock = """

        Screenshot evidence: \(screenshotScopeText)

        Browser snapshot from the current active webpage. This is parsed Moodle evidence. Use it with the screenshot; do not answer beyond these evidence blocks:
        \(browserContext)

        Evidence rules:
        - Answer only from the screenshot and parsed Moodle tasks above.
        - If the screenshot or parsed task evidence is missing, ambiguous, or insufficient, say that explicitly instead of guessing.
        - If multiple Moodle tasks/questions are present, answer them as numbered sections or a compact numbered list.
        """
        guard !history.isEmpty else {
            return "\(basePrompt)\(evidenceBlock)\n\nRespond concisely."
        }

        let context = history.suffix(12).map { message -> String in
            let role = message.type == .user ? "User" : "Assistant"
            let text = message.contents.map(\.content).joined(separator: "\n")
            return "\(role): \(text)"
        }.joined(separator: "\n\n")

        return """
        \(basePrompt)\(evidenceBlock)

        Ask history:
        \(context)

        Analyze the new screenshot and parsed Moodle evidence, then respond concisely.
        """
    }

    private func finishRequest() {
        isRunning = false
        pendingRequestID = nil
    }

    private func notifyHistoryChanged() {
        notificationService.post(name: Self.historyDidChange, object: nil)
    }

    private func showBubble(_ text: String, autoHide: Bool = false) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        lastBubbleText = text

        let window = bubbleWindow ?? AskBubblePanel(
            contentRect: NSRect(origin: .zero, size: Self.bubbleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        bubbleWindow = window
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.sharingType = .none
        window.isExcludedFromWindowsMenu = true
        ArrowCursorLock.install()
        window.contentView = NSHostingView(
            rootView: AskBubbleView(messages: history, fallbackText: text) { [weak self] in
                self?.hideBubble()
            }
        )
        ArrowCursorLock.apply(to: window)
        window.setFrame(positionedFrame(for: Self.bubbleSize), display: true)
        window.orderFrontRegardless()

        guard autoHide else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideBubble()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoHideSeconds, execute: workItem)
    }

    private func hideBubble() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        bubbleWindow?.orderOut(nil)
    }

    private func positionedFrame(for size: NSSize) -> NSRect {
        let screen = NSScreen.screenContainingMouse ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 24
        let width = min(size.width, frame.width - margin * 2)
        let height = min(size.height, frame.height - margin * 2)

        let x: CGFloat
        let y: CGFloat
        switch SettingsManager.shared.askCorner {
        case .topLeft:
            x = frame.minX + margin
            y = frame.maxY - height - margin
        case .topRight:
            x = frame.maxX - width - margin
            y = frame.maxY - height - margin
        case .bottomLeft:
            x = frame.minX + margin
            y = frame.minY + margin
        case .bottomRight:
            x = frame.maxX - width - margin
            y = frame.minY + margin
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class AskBubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AskBubbleView: View {
    let messages: [Message]
    let fallbackText: String
    let onClose: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        messageView(text: fallbackText, title: "MoodleLens")
                            .id("fallback")
                    } else {
                        ForEach(messages) { message in
                            messageView(
                                text: message.contents.map(\.content).joined(separator: "\n"),
                                title: message.type == .user ? "You" : "MoodleLens"
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(14)
            }
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(SettingsManager.shared.askOpacity))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture(perform: onClose)
            .frame(width: 420, height: 280)
            .onAppear {
                DispatchQueue.main.async {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: messages) { _, _ in
                DispatchQueue.main.async {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let latestMessage = messages.last {
            proxy.scrollTo(latestMessage.id, anchor: .bottom)
        } else {
            proxy.scrollTo("fallback", anchor: .bottom)
        }
    }

    private func messageView(text: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.black.opacity(0.55))

            Text(MarkdownParser.parse(text: text))
                .font(.system(size: 13))
                .foregroundStyle(.black)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
