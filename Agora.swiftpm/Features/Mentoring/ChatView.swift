import SwiftUI

/// Confidential conversation with polling while open, report / block / end.
struct ChatView: View {
    let threadId: String
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var messages: [ChatMessage] = []
    @State private var loaded = false
    @State private var text = ""
    @State private var sending = false
    @State private var runner = ActionRunner()
    @State private var reporting = false
    @State private var reportReason = ""
    @State private var confirmBlock = false
    @State private var confirmEnd = false
    @FocusState private var inputFocused: Bool

    private var thread: MentoringThread? { store.data.thread(threadId) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !loaded {
                        ProgressView().padding(.top, 40)
                    } else if messages.isEmpty {
                        Text("Noch keine Nachrichten.").font(.system(size: 15)).foregroundStyle(Palette.textSecondary).padding(.top, 40)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || Formats.chatDay(messages[index - 1].created) != Formats.chatDay(message.created) {
                            Text(Formats.chatDay(message.created))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Palette.surface, in: Capsule())
                                .padding(.top, 6)
                        }
                        MessageBubble(message: message, partnerName: thread?.partnerName ?? "")
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: inputFocused) { _, focused in
                if focused { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle(thread?.partnerName ?? String(localized: "Gespräch"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(thread?.partnerName ?? "").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                    Text(thread?.iAmMentor == true ? "Suchender (anonym)" : "Dein Mentor").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { reportReason = ""; reporting = true } label: { Label("Gespräch melden", systemImage: "flag") }
                    if thread?.blocked != true {
                        Button(role: .destructive) { confirmBlock = true } label: { Label("Blockieren", systemImage: "nosign") }
                    }
                    if thread?.isClosed != true {
                        Button(role: .destructive) { confirmEnd = true } label: { Label("Gespräch beenden", systemImage: "xmark.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Optionen")
            }
        }
        .task(id: threadId) {
            // Poll while visible; opening the chat marks it read, so the badges are refreshed too
            var lastCount = -1
            while !Task.isCancelled {
                if let list = try? await store.repository.messages(threadId: threadId) {
                    messages = list
                    loaded = true
                    if list.count != lastCount {
                        lastCount = list.count
                        store.refreshInBackground()
                    }
                } else {
                    loaded = true
                }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
            }
        }
        .alert("Gespräch melden", isPresented: $reporting) {
            TextField("Grund (optional)", text: $reportReason)
            Button("Abbrechen", role: .cancel) {}
            Button("Melden", role: .destructive, action: report)
        } message: {
            Text("Die letzten Nachrichten deines Gegenübers werden an die Administratoren gesendet.")
        }
        .confirmationDialog("Das Gespräch wird geschlossen und nur du kannst es wieder öffnen.", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Blockieren", role: .destructive) { setStatus("blocked", success: String(localized: "Gespräch blockiert.")) }
        }
        .confirmationDialog("Gespräch beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Gespräch beenden", role: .destructive) { setStatus("closed", success: String(localized: "Gespräch beendet")) }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let thread, thread.isClosed {
            VStack(spacing: 10) {
                Label(thread.blockedByMe ? "Du hast dieses Gespräch blockiert." : (thread.blocked ? "Dieses Gespräch wurde blockiert." : "Dieses Gespräch wurde beendet."),
                      systemImage: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.amberText)
                if !thread.blocked || thread.blockedByMe {
                    Button { setStatus("active", success: String(localized: "Gespräch wieder geöffnet")) } label: {
                        Label("Wiedereröffnen", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.agoraPrimary)
                    .disabled(runner.busy)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.bar)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Vertrauliche Nachricht schreiben…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(.system(size: 16))
                    // As tall as the send button for one line, so the text sits in the middle; grows upwards
                    .frame(minHeight: 36)
                    .padding(.vertical, 5)
                    .padding(.leading, 16)
                Button(action: send) {
                    Group {
                        if sending { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold)) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Palette.brand, in: Circle())
                    .shadow(color: Color(hex: 0x06B6D4, opacity: 0.3), radius: 3, y: 2)
                }
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(5)
                .accessibilityLabel("Senden")
            }
            .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(inputFocused ? Palette.primary : Palette.border, lineWidth: 1.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func send() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await store.repository.sendMessage(threadId: threadId, text: message)
                text = ""
                if let list = try? await store.repository.messages(threadId: threadId) { messages = list }
                store.refreshInBackground()
            } catch {
                toasts.error(error)
            }
        }
    }

    private func report() {
        let partner = messages.filter { !$0.isMine }.suffix(10).map(\.text)
        let content = partner.isEmpty ? "(keine Nachrichten)" : partner.joined(separator: "\n---\n")
        let reason = reportReason
        runner.run(toasts, success: String(localized: "Gemeldet – danke!")) {
            try await store.repository.report(type: "chat", content: content, reason: reason, threadId: threadId)
        }
    }

    private func setStatus(_ status: String, success: String) {
        runner.run(toasts, success: success) {
            try await store.repository.setThreadStatus(threadId: threadId, status)
            await store.refreshAll()
        }
    }
}

/// Mine: gradient on the right; theirs: light on the left with the partner's name.
struct MessageBubble: View {
    let message: ChatMessage
    let partnerName: String

    var body: some View {
        let mine = message.isMine
        HStack {
            if mine { Spacer(minLength: 50) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    if !mine && !partnerName.isEmpty {
                        Text(partnerName).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.primaryDark)
                    }
                    Text(message.text)
                        .font(.system(size: 15.5))
                        .lineSpacing(2)
                        .foregroundStyle(mine ? .white : Palette.text)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background {
                    if mine {
                        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                            .fill(Palette.brand)
                            .shadow(color: Color(hex: 0x06B6D4, opacity: 0.22), radius: 3, y: 2)
                    } else {
                        UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                            .fill(Palette.surface)
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                                .stroke(Palette.borderLight, lineWidth: 1))
                    }
                }
                Text(Formats.clock(message.created)).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            if !mine { Spacer(minLength: 50) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(mine ? "Du: \(message.text)" : "\(partnerName): \(message.text)"))
    }
}
