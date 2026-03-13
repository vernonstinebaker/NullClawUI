import SwiftUI
import MarkdownUI

/// Phase 3 & 4: Chat UI with streaming support.
struct ChatView: View {
    var viewModel: ChatViewModel
    var gatewayViewModel: GatewayViewModel

    @State private var useStreaming: Bool = true
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // MARK: Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if viewModel.isSending {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(12)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 100) // space for input bar
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // MARK: Input bar
                VStack(spacing: 0) {
                    Divider().opacity(0.4)
                    HStack(alignment: .bottom, spacing: 10) {
                        // Streaming toggle
                        Toggle("", isOn: $useStreaming)
                            .labelsHidden()
                            .toggleStyle(.button)
                            .tint(.accentColor)
                            .help("Toggle streaming")
                            .overlay(
                                Image(systemName: useStreaming ? "dot.radiowaves.left.and.right" : "arrow.down.circle")
                                    .font(.caption)
                                    .allowsHitTesting(false)
                            )
                            .accessibilityLabel(useStreaming ? "Streaming on" : "Streaming off")
                            .accessibilityHint("Toggle real-time streaming mode")

                        TextField("Message…", text: Bindable(viewModel).inputText, axis: .vertical)
                            .lineLimit(1...6)
                            .textFieldStyle(.plain)
                            .focused($isInputFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Message input")
                            .accessibilityHint("Type your message here")
                            .onSubmit { sendAction() }

                        // Abort / Send button
                        if viewModel.isStreaming {
                            Button(action: { Task { await viewModel.abort() } }) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel("Abort response")
                            .accessibilityHint("Stop the current streamed response")
                        } else {
                            Button(action: sendAction) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(viewModel.inputText.isEmpty ? .gray : .accentColor)
                            }
                            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || viewModel.isSending)
                            .accessibilityLabel("Send message")
                            .accessibilityHint("Send your message to the agent")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(gatewayViewModel.appModel.agentCard?.name ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let card = gatewayViewModel.appModel.agentCard {
                        ConnectionBadge(status: gatewayViewModel.appModel.connectionStatus)
                            .accessibilityLabel("Connected to \(card.name)")
                    }
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
        }
    }

    private func sendAction() {
        Task {
            if useStreaming {
                await viewModel.stream()
            } else {
                await viewModel.send()
            }
        }
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == "user" { Spacer(minLength: 50) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.role == "user" || (message.text.isEmpty && message.isStreaming) {
                        Text(message.text.isEmpty && message.isStreaming ? " " : message.text)
                    } else {
                        Markdown(message.text)
                            .markdownTheme(.gitHub)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                    .background(
                        message.role == "user"
                            ? Color.accentColor
                            : Color(.secondarySystemBackground),
                        in: BubbleShape(role: message.role)
                    )
                    .foregroundStyle(message.role == "user" ? .white : .primary)

                if message.isStreaming {
                    TypingIndicator()
                        .padding(.leading, 6)
                }
            }

            if message.role != "user" { Spacer(minLength: 50) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == "user" ? "You" : "Agent"): \(message.text)")
    }
}

/// Chat bubble shape with asymmetric corners.
struct BubbleShape: Shape {
    let role: String

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 6
        var path = Path()
        if role == "user" {
            // Round all corners, flat bottom-right
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r),
                                style: .continuous)
        } else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r),
                                style: .continuous)
        }
        _ = tail // reserved for Phase 6 tail rendering
        return path
    }
}

/// Animated three-dot typing indicator shown during streaming.
struct TypingIndicator: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(1 + 0.4 * sin(phase + Double(i) * .pi / 1.5))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .accessibilityLabel("Agent is typing")
    }
}
