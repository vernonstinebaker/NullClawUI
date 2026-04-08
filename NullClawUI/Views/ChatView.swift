import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Navigation destination type

/// Minimal hashable value type used by NavigationLink(value:) to push
/// the ConversationHistoryView onto the ChatView's NavigationStack.
struct ConversationHistoryDestination: Hashable {}

// MARK: - ChatView

/// Phase 3 & 4: Chat UI with streaming support.
struct ChatView: View {
    var viewModel: ChatViewModel
    var gatewayViewModel: GatewayViewModel

    @Environment(GatewayStore.self) private var store
    @Environment(AppModel.self) private var appModel
    @FocusState private var isInputFocused: Bool
    @State private var showingGatewayPicker = false
    /// Tracks the in-flight gateway-switch task so rapid taps can't stack up concurrent switches.
    @State private var switchGatewayTask: Task<Void, Never>? = nil
    /// PhotosPicker selection items (images).
    @State private var photoPickerItems: [PhotosPickerItem] = []
    /// Whether the document picker sheet is showing (for non-image files).
    @State private var showingDocumentPicker = false
    /// Whether the photos picker sheet is showing (triggered from the attachment Menu).
    @State private var showingPhotosPicker = false
    /// Navigation path for the conversation history screen.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            messageList
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: ConversationHistoryDestination.self) { _ in
                    ConversationHistoryView(viewModel: viewModel, gatewayViewModel: gatewayViewModel)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        gatewayPickerButton
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: ConversationHistoryDestination()) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .fontWeight(.medium)
                        }
                        .accessibilityLabel("Previous conversations")
                        .accessibilityHint("View and search your conversation history")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                if let profile = store.activeProfile {
                                    viewModel.startNewConversation(gateway: profile)
                                } else {
                                    viewModel.clearCurrentConversation()
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .fontWeight(.medium)
                        }
                        .accessibilityLabel("New conversation")
                        .accessibilityHint("Clears the current chat to start a fresh conversation")
                        .accessibilityIdentifier("newConversationButton")
                    }
                }
                .alert("Error", isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("OK") { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .confirmationDialog(
                    "Switch Gateway",
                    isPresented: $showingGatewayPicker,
                    titleVisibility: .visible
                ) {
                    ForEach(store.profiles) { profile in
                        Button {
                            guard profile.id != store.activeProfile?.id else { return }
                            switchGatewayTask?.cancel()
                            switchGatewayTask = Task {
                                let newClient = await gatewayViewModel.switchGateway(to: profile)
                                viewModel.resetForNewGateway(client: newClient, gateway: profile)
                            }
                        } label: {
                            if profile.id == store.activeProfile?.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Choose which gateway to chat with")
                }
        }
    }

    // MARK: - Gateway picker button (title bar)

    @ViewBuilder private var gatewayPickerButton: some View {
        let agentName = gatewayViewModel.appModel.effectiveAgentCard?.name
            ?? store.activeProfile?.name
            ?? "Chat"
        let hasMultiple = store.profiles.count > 1

        Button {
            if hasMultiple { showingGatewayPicker = true }
        } label: {
            HStack(spacing: 4) {
                Text(agentName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if hasMultiple {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!hasMultiple)
        .accessibilityLabel(hasMultiple ? "Gateway: \(agentName). Tap to switch." : agentName)
        .accessibilityIdentifier("gatewayPickerButton")
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                offlineBanner

                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 2) {
                        let snapshot = viewModel.messages
                        ForEach(Array(snapshot.enumerated()), id: \.element.id) { index, msg in
                            let isLastInGroup = isLastInGroup(at: index, in: snapshot)
                            MessageBubble(message: msg, isLastInGroup: isLastInGroup)
                                .id(msg.id)
                        }
                        if
                            viewModel.isSending ||
                            (viewModel.isStreaming && viewModel.messages.last?.role != "assistant")
                        {
                            thinkingBubble
                        }
                        // Invisible anchor used as the scroll target for auto-scroll.
                        Color.clear.frame(height: 1).id("bottomAnchor")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve space for the floating input bar so content is never hidden behind it.
                // Using safeAreaInset means this adapts automatically to any device's safe area.
                inputBar
            }
            .onTapGesture { isInputFocused = false }
            // Scroll when a new message is added (count change).
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            // Scroll on every streaming token — scrollTick increments per chunk.
            .onChange(of: viewModel.scrollTick) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
            // Scroll when streaming ends (thinking bubble disappears).
            .onChange(of: viewModel.isStreaming) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            // Scroll when keyboard appears / input bar changes height.
            .onChange(of: isInputFocused) { _, focused in
                if focused { scrollToBottom(proxy: proxy, animated: true) }
            }
            // Scroll when a history record finishes loading into the chat.
            .onChange(of: viewModel.chatTabRequested) { _, _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func isLastInGroup(at index: Int, in msgs: [ChatMessage]) -> Bool {
        if index >= msgs.count { return true }
        if index == msgs.count - 1 { return true }
        return msgs[index].role != msgs[index + 1].role
    }

    // MARK: - Phase 13: Offline banner

    /// Non-intrusive banner that slides in from the top when the gateway is unreachable.
    /// It sits inside the scroll view so it doesn't overlay the input bar or toolbar.
    @ViewBuilder private var offlineBanner: some View {
        // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
        let isOffline = appModel.connectionStatus == .offline
        if isOffline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                Text("Gateway offline — reconnecting…")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.35, bounce: 0.2), value: isOffline)
            .accessibilityLabel("Gateway offline. Reconnecting automatically.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "Start a Conversation",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Type a message below to get started.")
        )
    }

    // MARK: - Thinking indicator (before first SSE token arrives)

    private var thinkingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            agentAvatar(size: 28)
            HStack(spacing: 6) {
                TypingIndicator()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: BubbleShape(role: "assistant", isLast: true))
            Spacer(minLength: 60)
        }
        .padding(.top, 4)
    }

    // MARK: - Input bar

    /// True only when the active gateway explicitly advertises multiModal capability.
    /// Nil (unknown) and false both result in the paperclip being hidden.
    private var supportsMultiModal: Bool {
        appModel.effectiveAgentCard?.capabilities?.multiModal == true
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Hair-line separator
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)

            // Pending attachment thumbnails (shown above the text field when attachments are staged)
            if !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.pendingAttachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                if let uiImage = UIImage(data: attachment.data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    // Generic file icon for non-image types
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.regularMaterial)
                                        .frame(width: 64, height: 64)
                                        .overlay(
                                            Image(systemName: "doc.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.secondary)
                                        )
                                }
                                // Remove button
                                Button {
                                    viewModel.pendingAttachments.removeAll { $0.id == attachment.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color(.systemGray3))
                                        .offset(x: 6, y: -6)
                                }
                                .accessibilityLabel("Remove attachment")
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Phase 21: Attachment menu — only shown when the gateway advertises
                // multiModal: true in its agent card. This prevents the paperclip from
                // appearing on text-only models that would reject image payloads (HTTP 413).
                if supportsMultiModal {
                    // NOTE: No unit test — pure UI interaction; covered by visual inspection.
                    Menu {
                        Button {
                            showingPhotosPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("Choose File", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Attach")
                    .accessibilityHint("Attach an image from your photo library or a file from Files")
                    .disabled(viewModel.isStreaming || viewModel.isSending)
                }

                TextField("Message…", text: Bindable(viewModel).inputText, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("Message input")
                    .accessibilityHint("Type your message here")
                    .onSubmit { sendAction() }

                Group {
                    if viewModel.isStreaming {
                        Button(action: { Task { await viewModel.abort() } }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.red)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Abort response")
                        .accessibilityHint("Stop the current streamed response")
                    } else {
                        let canSend = (!viewModel.inputText
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !viewModel.pendingAttachments.isEmpty)
                            && !viewModel.isSending
                        Button(action: sendAction) {
                            Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                                .font(.system(size: 32))
                                .foregroundStyle(canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.spring(duration: 0.25), value: canSend)
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send message")
                        .accessibilityHint("Send your message to the agent")
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.25), value: viewModel.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        // Document picker sheet (for non-image files, e.g. PDF, text)
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPickerView { urls in
                Task { await loadDocumentURLs(urls) }
            }
        }
        // Photos picker sheet (triggered from the attachment Menu)
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $photoPickerItems,
            maxSelectionCount: 5,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItems) { _, newItems in
            Task { await loadPhotoPickerItems(newItems) }
            photoPickerItems = []
        }
    }

    // MARK: - Attachment loading helpers

    /// Loads selected PhotosPickerItems and appends them to pendingAttachments.
    @MainActor private func loadPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            // Prefer HEIF/JPEG representation that vision models can consume.
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Detect JPEG vs PNG vs HEIC by magic bytes; default to jpeg.
                let mimeType = imageMIMEType(for: data)
                viewModel.pendingAttachments.append(ChatAttachment(mimeType: mimeType, data: data))
            }
        }
    }

    /// Loads document URLs from the document picker and appends them to pendingAttachments.
    @MainActor private func loadDocumentURLs(_ urls: [URL]) async {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mimeType = (UTType(
                filenameExtension: url.pathExtension
            )?.preferredMIMEType) ?? "application/octet-stream"
            viewModel.pendingAttachments.append(ChatAttachment(mimeType: mimeType, data: data))
        }
    }

    /// Infers MIME type from magic bytes.
    private func imageMIMEType(for data: Data) -> String {
        guard data.count >= 4 else { return "image/jpeg" }
        let header = data.prefix(4).map(\.self)
        if header[0] == 0xFF, header[1] == 0xD8 { return "image/jpeg" }
        if header[0] == 0x89, header[1] == 0x50 { return "image/png" }
        if header[0] == 0x47, header[1] == 0x49 { return "image/gif" }
        if header[0] == 0x52, header[1] == 0x49 { return "image/webp" }
        return "image/jpeg" // default for HEIC and unknowns
    }

    private func sendAction() {
        isInputFocused = false
        viewModel.beginStream()
    }

    // MARK: - Avatar helper

    func agentAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: size * 0.45, weight: .light))
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - Chat Markdown Theme removed

// Using MarkdownText component instead of MarkdownUI

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let isLastInGroup: Bool
    @Environment(AppModel.self) private var appModel

    private var accentColor: Color {
        appModel.agentCard?.accentColor.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var isUser: Bool {
        message.role == "user"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                // Agent avatar — only shown on the last bubble in a consecutive group
                if isLastInGroup {
                    agentAvatar
                } else {
                    Color.clear.frame(width: 28)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                bubbleContent
                if message.isStreaming {
                    TypingIndicator()
                        .padding(isUser ? .trailing : .leading, 4)
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.top, isLastInGroup ? 8 : 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let who = isUser ? "You" : "Agent"
            let attachmentNote = message.attachments.isEmpty ? "" : ", \(message.attachments.count) attachment\(message.attachments.count == 1 ? "" : "s")"
            return "\(who): \(message.text)\(attachmentNote)"
        }())
    }

    private var bubbleContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // Attachment thumbnails (images/files carried by this message)
            if !message.attachments.isEmpty {
                attachmentGrid
            }
            // Text content (may be empty if the message is attachment-only)
            if !message.text.isEmpty || message.isStreaming {
                Group {
                    if isUser {
                        Text(message.text)
                            .textSelection(.enabled)
                            .foregroundStyle(accentColor.contrastingForeground)
                    } else if message.text.isEmpty, message.isStreaming {
                        Text(" ")
                    } else {
                        MarkdownText(message.text)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(accentColor)
                        : AnyShapeStyle(.regularMaterial),
                    in: BubbleShape(role: message.role, isLast: isLastInGroup && message.attachments.isEmpty)
                )
            }
        }
    }

    /// Grid of image/file thumbnails shown inside the bubble.
    @ViewBuilder private var attachmentGrid: some View {
        let cols = min(message.attachments.count, 3)
        let size: CGFloat = cols == 1 ? 200 : 100
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(size), spacing: 4), count: cols),
            spacing: 4
        ) {
            ForEach(message.attachments) { attachment in
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(
                            BubbleShape(
                                role: message.role,
                                isLast: isLastInGroup && attachment.id == message.attachments.last?.id
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "doc.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }

    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(accentColor)
        }
    }
}

// MARK: - BubbleShape

// Rounded on most corners; the "tail" corner (bottom-right for user, bottom-left for agent)
// is squared off on the last bubble in a group, giving a classic chat look.

struct BubbleShape: Shape {
    let role: String
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tailRadius: CGFloat = isLast ? 4 : r
        let isUser = role == "user"

        let tl = r
        let tr = r
        var bl = r
        var br = r
        if isUser {
            br = tailRadius
        } else {
            bl = tailRadius
        }
        return roundedRect(rect, tl: tl, tr: tr, bl: bl, br: br)
    }

    private func roundedRect(_ rect: CGRect, tl: CGFloat, tr: CGFloat, bl: CGFloat, br: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bl),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tl, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - TypingIndicator

/// Animated three-dot typing indicator shown during streaming.
/// Uses TimelineView(.animation) so the animation fires on every display
/// frame with no trigger dependency — PhaseAnimator(trigger: true) never
/// advances because the trigger value never changes.
struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                dot(t: t, delay: 0.0)
                dot(t: t, delay: 0.3)
                dot(t: t, delay: 0.6)
            }
        }
        .accessibilityLabel("Agent is typing")
    }

    @ViewBuilder private func dot(t: Double, delay: Double) -> some View {
        let cycle = 0.9
        let raw = (t - delay).truncatingRemainder(dividingBy: cycle) / cycle
        // Triangle wave 0→1→0 over the cycle, then ease-in-out
        let tri = raw < 0.5 ? raw * 2.0 : (1.0 - raw) * 2.0
        let eased = tri < 0.5 ? 2.0 * tri * tri : 1.0 - pow(-2.0 * tri + 2.0, 2.0) / 2.0
        Circle()
            .fill(.secondary.opacity(0.6))
            .frame(width: 7, height: 7)
            .offset(y: -eased * 6)
    }
}

// MARK: - DocumentPickerView

#if canImport(UIKit)
    import UIKit

    struct DocumentPickerView: UIViewControllerRepresentable {
        let onPick: ([URL]) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onPick: onPick)
        }

        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let types: [UTType] = [.pdf, .text, .plainText, .utf8PlainText, .data]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.allowsMultipleSelection = true
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

        final class Coordinator: NSObject, UIDocumentPickerDelegate {
            let onPick: ([URL]) -> Void
            init(onPick: @escaping ([URL]) -> Void) {
                self.onPick = onPick
            }

            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                onPick(urls)
            }
        }
    }
#endif
