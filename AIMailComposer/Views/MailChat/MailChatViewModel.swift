import AppKit
import Combine
import Foundation

struct MailChatEntry: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}

@MainActor
final class MailChatViewModel: ObservableObject {
    @Published var entries: [MailChatEntry] = [
        MailChatEntry(
            role: .assistant,
            text: "Demande-moi de résumer les mails d’aujourd’hui, de rechercher un expéditeur ou de préparer des réponses en brouillon."
        )
    ]
    @Published var input = ""
    @Published var isBusy = false
    @Published private(set) var isSavingDrafts = false
    @Published var progressText: String?
    @Published var pendingDrafts: [PreparedMailDraft] = []

    let settingsStore: SettingsStore
    private var activeTask: Task<Void, Never>?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var canSend: Bool {
        !isBusy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedDraftCount: Int {
        pendingDrafts.filter(\.isSelected).count
    }

    func useQuickPrompt(_ prompt: String) {
        guard !isBusy else { return }
        input = prompt
        submit()
    }

    func submit() {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isBusy else { return }
        input = ""
        entries.append(MailChatEntry(role: .user, text: request))
        pendingDrafts = []
        isBusy = true
        progressText = "Lecture de Mail…"

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.handle(request)
        }
    }

    func cancel() {
        guard !isSavingDrafts else { return }
        activeTask?.cancel()
        activeTask = nil
        isBusy = false
        progressText = nil
    }

    func discardDrafts() {
        pendingDrafts = []
        entries.append(MailChatEntry(role: .assistant, text: "Propositions supprimées. Aucun brouillon n’a été créé."))
    }

    func createSelectedDrafts() {
        guard !isBusy else { return }
        let selected = pendingDrafts.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        isBusy = true
        isSavingDrafts = true
        activeTask = Task { [weak self] in
            await self?.saveDrafts(selected)
        }
    }

    private func handle(_ request: String) async {
        do {
            let intent = MailChatIntentParser.parse(request)
            if intent == .unsupported {
                appendAssistant("Je peux résumer les mails d’aujourd’hui, rechercher un expéditeur ou préparer des réponses en brouillon. Précise ce que tu veux faire.")
                isBusy = false
                progressText = nil
                activeTask = nil
                return
            }
            let client = try settingsStore.makeAIClient()
            switch intent {
            case .askAboutToday:
                let messages = try await MailBridge.fetchTodayInboxMessages(limit: 25)
                try Task.checkCancellation()
                progressText = "Analyse avec \(client.provider.displayName)…"
                let prompts = SystemPrompt.inboxChat(
                    messages: messages,
                    userRequest: request,
                    conversation: conversationContext,
                    customInstructions: settingsStore.customWritingInstructions
                )
                let answer = try await client.complete(systemPrompt: prompts.system, userMessage: prompts.user)
                try Task.checkCancellation()
                appendAssistant(answer)

            case .search(let query):
                let messages = try await MailBridge.searchInboxMessages(query: query, limit: 25)
                try Task.checkCancellation()
                progressText = "Analyse de \(messages.count) résultat(s)…"
                let prompts = SystemPrompt.inboxChat(
                    messages: messages,
                    userRequest: request,
                    conversation: conversationContext,
                    customInstructions: settingsStore.customWritingInstructions
                )
                let answer = try await client.complete(systemPrompt: prompts.system, userMessage: prompts.user)
                try Task.checkCancellation()
                appendAssistant(answer)

            case .prepareTodayDrafts:
                try await prepareDrafts(request: request, client: client)

            case .unsupported:
                break
            }
        } catch is CancellationError {
            // The Cancel button is the user-visible result.
        } catch {
            appendAssistant("Erreur : \(error.localizedDescription)")
        }
        isBusy = false
        progressText = nil
        activeTask = nil
    }

    private func prepareDrafts(request: String, client: AIClient) async throws {
        let messages = try await MailBridge.fetchTodayInboxMessages(limit: 25)
        let candidates = messages.filter { !$0.isLikelyAutomated && !$0.wasRepliedTo }
        guard !candidates.isEmpty else {
            appendAssistant("Je n’ai trouvé aucun mail d’aujourd’hui qui semble nécessiter une nouvelle réponse.")
            return
        }

        var proposals: [PreparedMailDraft] = []
        for (index, message) in candidates.enumerated() {
            if proposals.count == 10 { break }
            try Task.checkCancellation()
            progressText = "Préparation \(index + 1)/\(candidates.count) : \(message.displaySubject)"
            let prompts = SystemPrompt.prepareInboxReply(
                to: message,
                userRequest: request,
                customInstructions: settingsStore.customWritingInstructions
            )
            let body = try await client.complete(systemPrompt: prompts.system, userMessage: prompts.user)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty && body.caseInsensitiveCompare("NO_REPLY") != .orderedSame {
                proposals.append(PreparedMailDraft(message: message, body: body))
            }
        }

        pendingDrafts = proposals
        if proposals.isEmpty {
            appendAssistant("L’IA estime qu’aucun de ces mails ne nécessite de réponse.")
        } else {
            appendAssistant("J’ai préparé \(proposals.count) réponse(s). Relis-les ci-dessous, puis choisis celles à créer dans les brouillons de Mail.")
        }
    }

    private func saveDrafts(_ drafts: [PreparedMailDraft]) async {
        var created = 0
        var failures: [String] = []
        for (index, draft) in drafts.enumerated() {
            if Task.isCancelled { break }
            progressText = "Création du brouillon \(index + 1)/\(drafts.count)…"
            do {
                try await MailBridge.createReplyDraft(for: draft.message, body: draft.body)
                created += 1
            } catch {
                failures.append("\(draft.message.displaySubject) : \(error.localizedDescription)")
            }
        }

        pendingDrafts = []
        isBusy = false
        isSavingDrafts = false
        progressText = nil
        activeTask = nil

        var result = "\(created) brouillon(s) créé(s) dans Mail. Aucun message n’a été envoyé."
        if !failures.isEmpty {
            result += "\n\nÉchecs :\n" + failures.joined(separator: "\n")
        }
        appendAssistant(result)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").first?.activate()
    }

    private var conversationContext: String {
        entries.suffix(6).map { entry in
            "\(entry.role == .user ? "User" : "Assistant"): \(entry.text)"
        }.joined(separator: "\n")
    }

    private func appendAssistant(_ text: String) {
        entries.append(MailChatEntry(role: .assistant, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
