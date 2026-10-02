import SwiftUI

/// One bubble of the AI conversation.
struct AiEntry: Identifiable, Equatable {
    let id = UUID()
    let role: String
    var content: String
    var reasoning = ""
    var streaming = false
    var error = false
}

/// Conversation lives only in memory (like the web app); the server is stateless.
@MainActor
@Observable
final class AiChatModel {
    var entries: [AiEntry] = []
    var busy = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Returns the text to put back into the input if sending failed.
    func send(_ text: String, store: AppStore, onFailed: @escaping (String) -> Void) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !question.isEmpty else { return }
        let history = entries.filter { !$0.error } + [AiEntry(role: "user", content: question)]
        entries = history + [AiEntry(role: "assistant", content: "", streaming: true)]
        busy = true
        task = Task {
            defer { busy = false }
            do {
                let stream = try store.repository.aiChat(history: history.map { AiMessage(role: $0.role, content: $0.content) })
                for try await chunk in stream {
                    guard let last = entries.indices.last else { break }
                    switch chunk {
                    case .content(let text): entries[last].content += text
                    case .reasoning(let text): entries[last].reasoning += text
                    }
                }
                if let last = entries.indices.last { entries[last].streaming = false }
            } catch is CancellationError {
                if let last = entries.indices.last { entries[last].streaming = false }
            } catch {
                // Drop the question and the empty answer, show the error, give the text back
                entries = Array(entries.dropLast(2)) + [AiEntry(role: "assistant", content: String(localized: "Fehler: \(APIError.text(error))"), error: true)]
                onFailed(question)
            }
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        entries = []
        busy = false
    }
}

struct AiChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var model = AiChatModel()
    @State private var text = ""
    @State private var reporting: AiEntry?
    @State private var reason = ""
    @State private var runner = ActionRunner()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.primary)
                Text("KI-Support").font(.system(size: 18, weight: .heavy)).foregroundStyle(Palette.text)
                Spacer()
                Button("Verlauf löschen") { model.clear() }
                    .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                    .disabled(model.entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.entries.isEmpty { welcome }
                        ForEach(model.entries) { entry in
                            AiBubble(entry: entry) {
                                reason = ""
                                reporting = entry
                            }
                            .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.entries.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.entries.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            inputBar
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Antwort melden", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            TextField("Grund (optional)", text: $reason)
            Button("Abbrechen", role: .cancel) { reporting = nil }
            Button("Melden", role: .destructive) { if let entry = reporting { report(entry) } }
        } message: {
            Text("Die Antwort und deine Frage werden an die Administratoren gesendet.")
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.primary)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [Palette.primary.opacity(0.15), Palette.secondary.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            Text("KI-Assistent bereit").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
            Text(store.user?.viewsFinances == true ? "Stelle Fragen zu deinen Mitgliedern, Finanzen oder Einstellungen."
                 : "Stelle Fragen zur Gemeinde, Mitgliedern oder zur App-Nutzung.")
                .font(.system(size: 15)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 290)
        }
        .padding(.top, 60)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Frage stellen…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .font(.system(size: 16))
                    // As tall as the send button for one line, so the text sits in the middle; grows upwards
                    .frame(minHeight: 36)
                    .padding(.vertical, 5)
                    .padding(.leading, 16)
                Button(action: send) {
                    Image(systemName: model.busy ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Palette.brand, in: Circle())
                }
                .disabled(model.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(5)
                .accessibilityLabel("Senden")
            }
            .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(focused ? Palette.primary : Palette.border, lineWidth: 1.5))
            Text("Antworten werden von einer KI erzeugt und können fehlerhaft sein.")
                .font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let question = text
        text = ""
        model.send(question, store: store) { failed in text = failed }
    }

    private func report(_ entry: AiEntry) {
        let visible = AiText.splitThinking(entry.content).visible
        let index = model.entries.firstIndex(of: entry) ?? 0
        let prompt = model.entries[..<index].last { $0.role == "user" }?.content ?? ""
        let why = reason
        runner.run(toasts, success: String(localized: "Gemeldet – danke!")) {
            try await store.repository.report(type: "ai", content: visible, reason: why, prompt: prompt)
        }
    }
}

struct AiBubble: View {
    let entry: AiEntry
    let onReport: () -> Void
    @State private var showThinking = false

    var body: some View {
        if entry.role == "user" {
            HStack {
                Spacer(minLength: 50)
                Text(entry.content)
                    .font(.system(size: 15.5))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18, style: .continuous)
                        .fill(Palette.brand))
            }
        } else {
            let split = AiText.splitThinking(entry.content)
            let thinking = [entry.reasoning.trimmingCharacters(in: .whitespacesAndNewlines), split.thinking].filter { !$0.isEmpty }.joined(separator: "\n")
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if !thinking.isEmpty {
                        Button {
                            withAnimation(.snappy) { showThinking.toggle() }
                        } label: {
                            Label(showThinking ? "Denkprozess ausblenden" : "Denkprozess anzeigen", systemImage: "brain")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        if showThinking {
                            Text(thinking).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).italic()
                                .padding(10)
                                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    if entry.streaming && split.visible.isEmpty {
                        TypingDots()
                    } else if entry.error {
                        Text(entry.content).font(.system(size: 15)).foregroundStyle(Palette.danger)
                    } else {
                        MarkdownView(text: split.visible, fontSize: 15.5).textSelection(.enabled)
                    }
                    if !entry.streaming && !entry.error && !split.visible.isEmpty {
                        Button(action: onReport) {
                            Label("Antwort melden", systemImage: "flag")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                        .fill(entry.error ? Palette.danger.opacity(0.08) : Palette.surface)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                            .stroke(Palette.borderLight, lineWidth: 1))
                }
                Spacer(minLength: 30)
            }
        }
    }
}

/// Three bouncing dots while the answer is being written.
struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle().fill(Palette.textSecondary.opacity(0.6)).frame(width: 7, height: 7)
                    .offset(y: phase == index ? -4 : 0)
            }
        }
        .padding(.vertical, 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Antwort wird geschrieben")
    }
}
