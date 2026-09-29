import SwiftUI

struct MailChatView: View {
    @ObservedObject var viewModel: MailChatViewModel
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            Divider()
            inputBar
        }
        .frame(minWidth: 520, minHeight: 620)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope.badge.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("Mail AI Chat")
                    .font(.headline)
                Text(settingsStore.selectedModel.map { "\($0.provider.displayName) · \($0.displayName)" } ?? "Aucun modèle sélectionné")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if viewModel.isBusy && !viewModel.isSavingDrafts {
                Button("Annuler") { viewModel.cancel() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    quickActions

                    ForEach(viewModel.entries) { entry in
                        chatBubble(entry)
                            .id(entry.id)
                    }

                    if let progress = viewModel.progressText {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(progress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 4)
                    }

                    if !viewModel.pendingDrafts.isEmpty {
                        draftReview
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.entries.count) {
                guard let last = viewModel.entries.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button("Résumer aujourd’hui") {
                viewModel.useQuickPrompt("Résume les mails reçus aujourd’hui et indique mes actions prioritaires.")
            }
            Button("Préparer les brouillons") {
                viewModel.useQuickPrompt("Prépare des réponses en brouillon aux mails reçus aujourd’hui qui nécessitent une réponse.")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(viewModel.isBusy)
    }

    private func chatBubble(_ entry: MailChatEntry) -> some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 70) }
            Text(entry.text)
                .textSelection(.enabled)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(entry.role == .user ? Color.accentColor : Color.secondary.opacity(0.13))
                .foregroundStyle(entry.role == .user ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if entry.role == .assistant { Spacer(minLength: 70) }
        }
    }

    private var draftReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brouillons proposés")
                .font(.headline)

            ForEach($viewModel.pendingDrafts) { $draft in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $draft.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.message.displaySubject)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(draft.message.sender)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    TextEditor(text: $draft.body)
                        .font(.system(size: 12))
                        .frame(minHeight: 110)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!draft.isSelected || viewModel.isBusy)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Button("Supprimer les propositions") { viewModel.discardDrafts() }
                Spacer()
                Button("Créer \(viewModel.selectedDraftCount) brouillon(s) dans Mail") {
                    viewModel.createSelectedDrafts()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedDraftCount == 0 || viewModel.isBusy)
            }
        }
        .padding(.top, 4)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Demande quelque chose à propos de tes mails…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit { viewModel.submit() }

            Button {
                viewModel.submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
    }
}
