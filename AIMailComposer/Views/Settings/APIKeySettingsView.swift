import SwiftUI

struct APIKeySettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var anthropicKey: String = ""
    @State private var openaiKey: String = ""
    @State private var geminiKey: String = ""
    @State private var openrouterKey: String = ""
    @State private var trustedtokensKey: String = ""
    @State private var chatGPTWebKey: String = ""
    @State private var chatGPTWebBaseURL: String = ""
    @State private var localKey: String = ""
    @State private var localBaseURL: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var modelSearchText: String = ""
    @State private var autoSaveTask: Task<Void, Never>?

    var body: some View {
        Form {
            chatGPTWebSection
            keySection
            modelSections
        }
        .formStyle(.grouped)
        .onAppear {
            anthropicKey = settingsStore.getAPIKey(for: .anthropic) ?? ""
            openaiKey = settingsStore.getAPIKey(for: .openai) ?? ""
            geminiKey = settingsStore.getAPIKey(for: .gemini) ?? ""
            openrouterKey = settingsStore.getAPIKey(for: .openrouter) ?? ""
            trustedtokensKey = settingsStore.getAPIKey(for: .trustedtokens) ?? ""
            chatGPTWebKey = settingsStore.getAPIKey(for: .chatgptWeb) ?? ""
            chatGPTWebBaseURL = settingsStore.chatGPTWebBaseURL
            localKey = settingsStore.getAPIKey(for: .local) ?? ""
            localBaseURL = settingsStore.localAIBaseURL
        }
        .onChange(of: anthropicKey) { _, _ in scheduleAutoSave() }
        .onChange(of: openaiKey) { _, _ in scheduleAutoSave() }
        .onChange(of: geminiKey) { _, _ in scheduleAutoSave() }
        .onChange(of: openrouterKey) { _, _ in scheduleAutoSave() }
        .onChange(of: trustedtokensKey) { _, _ in scheduleAutoSave() }
        .onChange(of: chatGPTWebKey) { _, _ in scheduleAutoSave() }
        .onChange(of: chatGPTWebBaseURL) { _, _ in scheduleAutoSave() }
        .onChange(of: localKey) { _, _ in scheduleAutoSave() }
        .onChange(of: localBaseURL) { _, _ in scheduleAutoSave() }
        .task {
            if settingsStore.chatGPTWebEnabled {
                await settingsStore.fetchModels(for: .chatgptWeb)
            }
        }
    }

    // MARK: - ChatGPT Web subscription

    private var chatGPTWebSection: some View {
        Section {
            Toggle("Enable ChatGPT Web", isOn: Binding(
                get: { settingsStore.chatGPTWebEnabled },
                set: { enabled in
                    settingsStore.setChatGPTWebEnabled(enabled)
                    if enabled {
                        saveKeys()
                    }
                }
            ))
            .toggleStyle(.switch)

            if settingsStore.chatGPTWebEnabled {
                LabeledContent("Connection") {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(chatGPTWebStatusColor)
                            .frame(width: 9, height: 9)
                        Text(chatGPTWebStatusText)
                            .foregroundStyle(.secondary)
                    }
                }

                keyRow(
                    "Relay URL",
                    subtitle: "Loopback only",
                    placeholder: "http://127.0.0.1:8791",
                    text: $chatGPTWebBaseURL
                )
                keyRow(
                    "Relay token",
                    subtitle: "Stored in macOS Keychain",
                    placeholder: "Local relay access token",
                    text: $chatGPTWebKey
                )

                HStack {
                    Button {
                        saveKeys()
                    } label: {
                        HStack(spacing: 7) {
                            if settingsStore.isFetchingChatGPTWeb {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Check Again")
                        }
                    }
                    .disabled(settingsStore.isFetchingChatGPTWeb)

                    Spacer()
                    Link(
                        "Setup guide",
                        destination: URL(string: "https://github.com/guberm/chatgpt-web-provider#browser-backend-setup")!
                    )
                }
            }
        } header: {
            Text("ChatGPT Web (Experimental)")
        } footer: {
            Text("Uses a separate community relay and an isolated browser profile, so it targets your regular ChatGPT web allowance instead of Codex. The relay must run locally and may break when ChatGPT changes or trigger account restrictions. This app never reads your ChatGPT cookies or tokens.")
        }
    }

    private var chatGPTWebStatusText: String {
        switch settingsStore.chatGPTWebConnectionStatus {
        case .disabled:
            return "Disabled"
        case .checking:
            return "Checking local relay…"
        case .connected:
            return "Connected through browser relay"
        case .loginRequired:
            return "Open the relay browser and sign in"
        case .mockBackend:
            return "Relay is running in mock mode"
        case .unavailable(let message):
            return message
        }
    }

    private var chatGPTWebStatusColor: Color {
        switch settingsStore.chatGPTWebConnectionStatus {
        case .connected: return .green
        case .checking, .disabled: return .secondary
        case .loginRequired, .mockBackend: return .orange
        case .unavailable: return .red
        }
    }

    // MARK: - API Keys

    private var keySection: some View {
        Section {
            keyRow("Anthropic", placeholder: "sk-ant-api03-…", text: $anthropicKey)
            keyRow("OpenAI", placeholder: "sk-…", text: $openaiKey)
            keyRow("Google Gemini", placeholder: "AIza…", text: $geminiKey)
            keyRow("OpenRouter",
                   subtitle: "One key for every model on openrouter.ai",
                   placeholder: "sk-or-v1-…",
                   text: $openrouterKey)
            VStack(alignment: .leading, spacing: 4) {
                Link("OpenRouter privacy settings", destination: OpenRouterClient.privacySettingsURL)
                Text("OpenRouter controls which model providers your account allows. Adjust data and training preferences there if a model is blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            keyRow("TrustedTokens",
                   subtitle: "EU-sovereign models at api.trustedtokens.eu",
                   placeholder: "sk-bf…",
                   text: $trustedtokensKey)
            keyRow("Local AI URL",
                   subtitle: "Local or remote OpenAI-compatible server",
                   placeholder: "http://localhost:1234",
                   text: $localBaseURL)
            keyRow("Local AI API key",
                   subtitle: "Leave empty if your server needs no key",
                   placeholder: "Optional API key",
                   text: $localKey)
        } header: {
            Text("API Keys")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                Text("Keys are saved automatically to the macOS Keychain and never leave this Mac except to call the provider.")
            }
        }
    }

    private func keyRow(
        _ label: String,
        subtitle: String? = nil,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        LabeledContent {
            KeyInputField(placeholder: placeholder, text: text) {
                autoSaveTask?.cancel()
                saveKeys()
            }
        } label: {
            Text(label)
            if let subtitle {
                Text(subtitle)
            }
        }
    }

    // MARK: - Auto-save

    /// Saves and refetches models ~1s after the user stops typing in any
    /// key field, so entering a key immediately populates the model list
    /// without a separate Save step.
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            autoSaveIfChanged()
        }
    }

    private func autoSaveIfChanged() {
        func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Compare against what's stored so the initial onAppear load (and
        // saveKeys' own trim/sanitize write-backs) don't re-trigger a save.
        let changed = trimmed(anthropicKey) != (settingsStore.getAPIKey(for: .anthropic) ?? "")
            || trimmed(openaiKey) != (settingsStore.getAPIKey(for: .openai) ?? "")
            || trimmed(geminiKey) != (settingsStore.getAPIKey(for: .gemini) ?? "")
            || trimmed(openrouterKey) != (settingsStore.getAPIKey(for: .openrouter) ?? "")
            || trimmed(trustedtokensKey) != (settingsStore.getAPIKey(for: .trustedtokens) ?? "")
            || trimmed(chatGPTWebKey) != (settingsStore.getAPIKey(for: .chatgptWeb) ?? "")
            || trimmed(chatGPTWebBaseURL) != settingsStore.chatGPTWebBaseURL
            || trimmed(localKey) != (settingsStore.getAPIKey(for: .local) ?? "")
            || trimmed(localBaseURL) != settingsStore.localAIBaseURL
        guard changed else { return }
        saveKeys()
    }

    // MARK: - Model Selection

    private var isFetching: Bool {
        settingsStore.isFetchingChatGPTWeb
            || settingsStore.isFetchingAnthropic
            || settingsStore.isFetchingOpenAI
            || settingsStore.isFetchingGemini
            || settingsStore.isFetchingOpenRouter
            || settingsStore.isFetchingTrustedTokens
            || settingsStore.isFetchingLocal
    }

    @ViewBuilder
    private var modelSections: some View {
        Section {
            if settingsStore.allModels.isEmpty && !isFetching {
                modelEmptyState
            } else {
                searchRow
            }
        } header: {
            HStack {
                Text("Model")
                Spacer()
                if isFetching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await settingsStore.fetchAllModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh model list")
                }
            }
        } footer: {
            fetchErrorLines
        }

        ForEach(filteredGroupedModels, id: \.0) { provider, models in
            Section(provider.displayName) {
                ForEach(models) { model in
                    modelRow(model)
                }
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search models…", text: $modelSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !modelSearchText.isEmpty {
                Button {
                    modelSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modelEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No models available")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Connect the experimental ChatGPT Web relay, enter a provider API key, or add a Local AI URL above to load models.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var filteredGroupedModels: [(AIProvider, [AIModel])] {
        guard !modelSearchText.isEmpty else {
            return settingsStore.sortedGroupedModels
        }
        let query = modelSearchText.lowercased()
        return settingsStore.sortedGroupedModels.compactMap { provider, models in
            let filtered = models.filter {
                $0.displayName.lowercased().contains(query)
                    || $0.id.lowercased().contains(query)
            }
            guard !filtered.isEmpty else { return nil }
            return (provider, filtered)
        }
    }

    private func modelRow(_ model: AIModel) -> some View {
        Button {
            settingsStore.selectModel(model)
        } label: {
            HStack {
                Text(model.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if settingsStore.isSelected(model) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var fetchErrorLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let err = settingsStore.anthropicFetchError {
                Text("Anthropic: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.chatGPTWebFetchError {
                Text("ChatGPT Web: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.openaiFetchError {
                Text("OpenAI: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.geminiFetchError {
                Text("Gemini: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.openrouterFetchError {
                Text("OpenRouter: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.trustedtokensFetchError {
                Text("TrustedTokens: \(err)").foregroundStyle(.red)
            }
            if let err = settingsStore.localFetchError {
                Text("Local AI: \(err)").foregroundStyle(.red)
            }
        }
    }

    // MARK: - Save

    private func saveKeys() {
        let trimmedAnthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAI = openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGemini = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenRouter = openrouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrustedTokens = trustedtokensKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatGPTWebKey = chatGPTWebKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChatGPTWebURL = chatGPTWebBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalKey = localKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalURL = localBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        anthropicKey = trimmedAnthropic
        openaiKey = trimmedOpenAI
        geminiKey = trimmedGemini
        openrouterKey = trimmedOpenRouter
        trustedtokensKey = trimmedTrustedTokens
        chatGPTWebKey = trimmedChatGPTWebKey
        chatGPTWebBaseURL = trimmedChatGPTWebURL
        localKey = trimmedLocalKey
        localBaseURL = trimmedLocalURL

        do {
            try applyKey(trimmedAnthropic, for: .anthropic)
            try applyKey(trimmedOpenAI, for: .openai)
            try applyKey(trimmedGemini, for: .gemini)
            try applyKey(trimmedOpenRouter, for: .openrouter)
            try applyKey(trimmedTrustedTokens, for: .trustedtokens)
            try applyKey(trimmedChatGPTWebKey, for: .chatgptWeb)
            try applyKey(trimmedLocalKey, for: .local)

            var sanitizedChatGPTWebURL = trimmedChatGPTWebURL
            if !sanitizedChatGPTWebURL.lowercased().hasPrefix("http://")
                && !sanitizedChatGPTWebURL.lowercased().hasPrefix("https://") {
                sanitizedChatGPTWebURL = "http://" + sanitizedChatGPTWebURL
            }
            while sanitizedChatGPTWebURL.hasSuffix("/") {
                sanitizedChatGPTWebURL.removeLast()
            }
            settingsStore.chatGPTWebBaseURL = sanitizedChatGPTWebURL
            chatGPTWebBaseURL = sanitizedChatGPTWebURL

            if trimmedLocalURL.isEmpty {
                settingsStore.localAIBaseURL = ""
                settingsStore.clearModels(for: .local)
            } else {
                var sanitizedURL = trimmedLocalURL
                if !sanitizedURL.lowercased().hasPrefix("http://") && !sanitizedURL.lowercased().hasPrefix("https://") {
                    sanitizedURL = "http://" + sanitizedURL
                }
                while sanitizedURL.hasSuffix("/") {
                    sanitizedURL.removeLast()
                }
                settingsStore.localAIBaseURL = sanitizedURL
                localBaseURL = sanitizedURL
            }

            isError = false
            statusMessage = "Saved. Fetching models…"
            Task {
                await settingsStore.fetchAllModels()
                let errors = [
                    settingsStore.anthropicFetchError,
                    settingsStore.openaiFetchError,
                    settingsStore.geminiFetchError,
                    settingsStore.openrouterFetchError,
                    settingsStore.trustedtokensFetchError,
                    settingsStore.chatGPTWebFetchError,
                    settingsStore.localFetchError,
                ].compactMap { $0 }
                if errors.isEmpty {
                    statusMessage = "Saved. \(settingsStore.allModels.count) models loaded."
                    isError = false
                } else {
                    statusMessage = errors.joined(separator: "; ")
                    isError = true
                }
            }
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func applyKey(_ key: String, for provider: AIProvider) throws {
        if key.isEmpty {
            settingsStore.deleteAPIKey(for: provider)
            // Local AI can still load models without a key. Its URL controls
            // whether the provider is configured.
            if provider != .local {
                settingsStore.clearModels(for: provider)
            }
        } else {
            try settingsStore.setAPIKey(key, for: provider)
        }
    }
}

// MARK: - Key input field

/// A visibly bordered input for API keys. Fixed width so a long key scrolls
/// inside the field instead of stretching the row, with an accent border
/// while focused.
private struct KeyInputField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        // Empty title + explicit prompt: inside a Form, a TextField's
        // title renders as a second visible label, not as placeholder.
        TextField("", text: $text, prompt: Text(placeholder))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .multilineTextAlignment(.leading)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 250)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.15),
                        lineWidth: 1
                    )
            )
    }
}
