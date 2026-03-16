import SwiftUI
import MarkdownUI

// MARK: - ChatView

/// Phase 3 & 4: Chat UI with streaming support.
struct ChatView: View {
    var viewModel: ChatViewModel
    var gatewayViewModel: GatewayViewModel

    @Environment(GatewayStore.self) private var store
    @FocusState private var isInputFocused: Bool
    @State private var showingGatewayPicker = false

    var body: some View {
        NavigationStack {
            messageList
                .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Gateway picker in the title position
                ToolbarItem(placement: .principal) {
                    gatewayPickerButton
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
                        Task {
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

    @ViewBuilder private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                        if viewModel.isSending ||
                           (viewModel.isStreaming && viewModel.messages.last?.role != "assistant") {
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("Start a conversation")
                .font(.title3.weight(.medium))
                .foregroundStyle(.tertiary)
            Text("Type a message below to get started")
                .font(.subheadline)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
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

    @ViewBuilder private var inputBar: some View {
        VStack(spacing: 0) {
            // Hair-line separator
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message…", text: Bindable(viewModel).inputText, axis: .vertical)
                    .lineLimit(1...6)
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
                        let canSend = !viewModel.inputText
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    }

    private func sendAction() {
        isInputFocused = false
        viewModel.beginStream()
    }

    // MARK: - Avatar helper

    @ViewBuilder func agentAvatar(size: CGFloat) -> some View {
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

// MARK: - Chat Markdown Theme
// A clean, minimal theme that inherits foreground color from its context
// (white on user bubbles, primary on agent bubbles). No background colors
// on text, no dividers under headings.

@MainActor
extension Theme {
    static var chat: Theme {
        Theme()
            .text {
                FontSize(15)
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.875))
            }
            .heading1 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.1))
                    .markdownMargin(top: 16, bottom: 8)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.4))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.1))
                    .markdownMargin(top: 14, bottom: 6)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.2))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.1))
                    .markdownMargin(top: 12, bottom: 4)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.05))
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 0, bottom: 10)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.5))
                        .relativeFrame(width: .em(0.2))
                    configuration.label
                        .markdownTextStyle { ForegroundColor(.secondary) }
                        .relativePadding(.horizontal, length: .em(0.75))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.2))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.85))
                        }
                        .padding(12)
                }
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .markdownMargin(top: 0, bottom: 10)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.15))
            }
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let isLastInGroup: Bool
    @Environment(AppModel.self) private var appModel

    private var accentColor: Color {
        appModel.agentCard?.accentColor.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var isUser: Bool { message.role == "user" }

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
        .accessibilityLabel("\(isUser ? "You" : "Agent"): \(message.text)")
    }

    @ViewBuilder private var bubbleContent: some View {
        Group {
            if isUser {
                Text(message.text)
                    .textSelection(.enabled)
                    .foregroundStyle(accentColor.contrastingForeground)
            } else if message.text.isEmpty && message.isStreaming {
                // Waiting for first token — invisible placeholder keeps layout stable
                Text(" ")
            } else {
                Markdown(message.text)
                    .markdownTheme(.chat)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isUser
                ? AnyShapeStyle(accentColor)
                : AnyShapeStyle(.regularMaterial),
            in: BubbleShape(role: message.role, isLast: isLastInGroup)
        )
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

        let tl = r; let tr = r; var bl = r; var br = r
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
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
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
