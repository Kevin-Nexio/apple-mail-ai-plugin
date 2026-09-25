<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png">
    <img src="logo-light.png" width="128" height="128" alt="Apple Mail AI Plugin logo">
  </picture>
</p>

<h1 align="center">Apple Mail AI Plugin</h1>

<p align="center">
  The missing AI agent for Apple Mail. Apple Mail AI Plugin is a native macOS menu bar app that uses AI (Claude, GPT, Gemini) to help you write email replies in Apple Mail, and chat messages in Discord and WhatsApp.
</p>

<p align="center">
  <a href="#installation">Installation</a> &middot;
  <a href="#get-your-api-key">Get Your API Key</a> &middot;
  <a href="#usage">Usage</a> &middot;
  <a href="#building-from-source">Build from Source</a>
</p>

---

The **Apple Mail AI Plugin** lives in your menu bar and connects directly to Apple Mail. When you're composing a reply, press **Option + H** to open the composer panel. Type a few thoughts about what you want to say, pick an AI model, and the app writes your reply — matching the language and tone of the conversation.

Switch it on for **Discord**, **WhatsApp**, or any other app and the same shortcut works there too: the app takes a screenshot of the chat window, sends it to the model as the conversation context, and puts the finished message into the chat box for you to review and send.

Use your **ChatGPT subscription through Codex**, bring your own API key, or connect a compatible local server. Provider keys are stored in macOS Keychain and calls go directly to the selected service.

## Features

- **Menu bar app** — stays out of your way until you need it
- **Works with Apple Mail** — reads your email thread, recipients, subject, and current draft
- **Works in Discord, WhatsApp, and any app you add** — opt-in per app: screenshots the chat window as context and inserts the message into the chat box, never sending it for you
- **ChatGPT subscription** — use the ChatGPT account already connected to Codex, without adding an OpenAI API key
- **ChatGPT Web (experimental)** — use a local community browser relay as a separate provider, with its own connection light
- **Multiple AI providers** — Anthropic (Claude), OpenAI API (GPT), Google Gemini, OpenRouter, and TrustedTokens (EU-sovereign)
- **Local and custom servers** — connect to local or remote OpenAI-compatible servers, with an optional API key
- **Streaming responses** — see the reply as it's being written
- **Language matching** — automatically replies in the same language as the conversation
- **Keyboard shortcut** — **⌥H** (Option + H) to open from anywhere
- **Secure key storage** — API keys stored in macOS Keychain, never on disk

## Installation

**Requirements:** macOS 14 (Sonoma) or later. On recent macOS versions, Mail's AppleScript interface no longer reliably exposes compose windows, so the app can optionally use the Accessibility API to read your draft — grant **Accessibility** permission when the in-app banner suggests it (System Settings → Privacy & Security → Accessibility). The banner is dismissible; a blank new-message compose keeps working without it.

Composing from a screenshot is off for every app until you enable it under **Settings → General → Compose from a Screenshot**, so using only Mail never asks for extra permissions. Enabled apps additionally need **Screen Recording** permission (System Settings → Privacy & Security → Screen & System Audio Recording) so the app can screenshot the chat window, and **Accessibility** so it can type the result into the chat box. macOS applies a new Screen Recording grant after the app relaunches. Without Screen Recording the message is written from your notes alone; without Accessibility it is copied to the clipboard for you to paste.

### Download

Grab the latest `.dmg` from the [Webpage](https://jpwahle.github.io/apple-mail-ai-plugin/).

## Get Your API Key

You do not need an API key to use a ChatGPT subscription. For other providers, add a provider API key or connect to a local or custom server below.

### ChatGPT Subscription via Codex

1. Install the [ChatGPT macOS app](https://openai.com/chatgpt/desktop/) or the Codex CLI
2. Sign in to Codex with your ChatGPT account. In the CLI, run `codex login` and choose ChatGPT
3. Open **Settings → Models → API Keys** in Apple Mail AI Plugin
4. Check that **ChatGPT Subscription** has a green status light, then select **ChatGPT (via Codex)** in the model picker

The plugin starts Codex locally and uses its app-server protocol. Codex keeps control of the ChatGPT credentials; the plugin never reads or stores an access token. It also rejects Codex sessions authenticated with an API key so this mode cannot silently create API charges. The app-server protocol is currently experimental, so a future Codex update may require a plugin update.

### ChatGPT Web Subscription (Experimental)

This mode connects to the community project [chatgpt-web-provider](https://github.com/guberm/chatgpt-web-provider). The relay controls a dedicated Chromium profile logged in to ChatGPT and exposes an OpenAI-compatible API on your Mac. It is separate from the Codex provider and is intended to use the regular ChatGPT web allowance reported by that project.

1. Install and configure `chatgpt-web-provider` by following its [browser backend setup](https://github.com/guberm/chatgpt-web-provider#browser-backend-setup)
2. Keep the relay bound to `127.0.0.1`, start it on the default port `8791`, and use a long local access token
3. Open **Settings → Models → API Keys** in Apple Mail AI Plugin
4. Enable **ChatGPT Web (Experimental)**, paste the same relay token, and check that its status light turns green
5. Select a model under **ChatGPT Web (Experimental)** in the model picker

The plugin only accepts a loopback relay URL (`localhost`, `127.0.0.1`, or `::1`). The relay token is stored in macOS Keychain. Every generated email starts a fresh web conversation so context from an earlier email is not intentionally reused.

This is unofficial browser automation. ChatGPT UI or Cloudflare changes can break it, and automated use may trigger warnings or account restrictions. Use a dedicated browser profile, keep the relay local, and do not use this mode if that risk is unacceptable. The plugin never reads ChatGPT cookies or account tokens; those remain inside the relay's browser profile.

### Anthropic (Claude)

1. Go to [console.anthropic.com](https://console.anthropic.com/)
2. Sign up or log in
3. Navigate to **API Keys** in the sidebar
4. Click **Create Key**, give it a name, and copy the key

### OpenAI (GPT)

1. Go to [platform.openai.com](https://platform.openai.com/)
2. Sign up or log in
3. Navigate to **API Keys** in the sidebar
4. Click **Create new secret key**, name it, and copy the key

### Google Gemini

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Sign in with your Google account
3. Click **Create API Key**, select a project (or create one), and copy the key

### OpenRouter

1. Go to [openrouter.ai](https://openrouter.ai/)
2. Sign up or log in
3. Navigate to **Keys** in the sidebar
4. Click **Create Key**, name it, and copy the key

> **Tip:** OpenRouter gives you access to models from many providers through a single key. Great if you want to try different models without managing multiple accounts.

If OpenRouter reports a **model training violation (account settings)**, your account's privacy policy has excluded the available providers for that model. Choose another model, or open [OpenRouter privacy settings](https://openrouter.ai/settings/privacy) and allow routing to providers that may train on your data for the affected category (paid or free models). The app links to these settings from **Settings → Models → API Keys** and from the error message. The app sends no additional guardrail restrictions; OpenRouter account policies apply independently of TrustedTokens and cannot be disabled with an app setting. See [OpenRouter's provider policy documentation](https://openrouter.ai/docs/guides/privacy/provider-logging).

### TrustedTokens

1. Go to [trustedtokens.eu](https://trustedtokens.eu/)
2. Sign up for a free trial
3. Open **Account** to find your API token
4. Copy the token

> **Tip:** TrustedTokens is an EU-sovereign, OpenAI-compatible gateway hosted in Germany — all data processed in the EU. The app fetches model IDs automatically and sends the selected ID unchanged. Default-provider entries use a bare model ID (e.g. `zai-org/GLM-5.3`); provider-specific entries include a routing prefix (e.g. `skainet/zai-org/GLM-5.3`). See the [TrustedTokens API documentation](https://trustedtokens.eu/docs/) for details.

### Local or Custom OpenAI-Compatible Server

1. Open **Settings → Models**
2. Enter your server's base URL in **Local AI URL**, for example `http://localhost:1234` (LM Studio), `http://localhost:11434` (Ollama), or `https://llm.example.com` (remote server). The app appends `/v1/models` and `/v1/chat/completions`, so omit those paths from the base URL.
3. If your server requires authentication, enter its key in **Local AI API key**. This supports servers such as vLLM configured with an API key. Leave the field empty for servers without authentication.
4. Settings save automatically and the app loads your server's models. Select one to start composing.

The optional key is stored in macOS Keychain and sent as a Bearer token for both model loading and reply generation. Clear the key field to remove authentication.

### Add Your Key to the App

1. Click the **Apple Mail AI Plugin** icon in your menu bar
2. Open **Settings**
3. Paste your API key for the provider you chose
4. The app will automatically fetch available models from that provider

## Usage

1. Open **Apple Mail** and start composing a reply
2. Press **⌥H** (Option + H) to open the composer panel
3. Type a few words describing what you want to say (e.g. "sounds good, let's meet thursday")
4. Pick a model from the dropdown
5. Hit **Generate** — the reply streams into your compose window

The app reads the full email thread for context, so the generated reply stays relevant to the conversation.

### Discord, WhatsApp, and other apps

1. In **Settings → General → Compose from a Screenshot**, switch on **Discord** or **WhatsApp**, or click **Add App…** to pick any other app (Slack, Telegram, Messages, …)
2. Open a conversation in that app and make it the active app
3. Press **⌥H** (or your shortcut) — the app screenshots the chat window and opens the composer next to it, with a thumbnail of what the model will see
4. Type what you want to say and hit **Generate**
5. Click **Insert into Discord** (or the app's name) — the message lands in the chat box, unsent, so you can read it over before pressing Enter

Pick a vision-capable model for this (for example a current Claude, GPT, or Gemini model); text-only models reject the screenshot. **Summarize chat** gives you a TL;DR of the visible conversation instead. Switch an app off again and the shortcut goes back to the Mail flow there. The list is stored with your other settings and kept across updates.

## Building from Source

```bash
git clone https://github.com/jpwahle/aimail.git
cd aimail
make build
make run
```

### Developing in Xcode

Open `AIMailComposer.xcodeproj` and hit Run — the shared `AIMailComposer`
scheme builds and launches the app bundle directly (requires Xcode 16 or
later). The project uses a synchronized folder reference, so new source
files added under `AIMailComposer/` are picked up automatically.

### Available Make Targets

| Command | Description |
|---------|-------------|
| `make build` | Debug build |
| `make run` | Build and launch the app |
| `make release` | Optimized release build |
| `make sign` | Code sign (ad-hoc or with `SIGNING_IDENTITY`) |
| `make dmg` | Create a `.dmg` installer |
| `make install` | Install to `/Applications` |
| `make clean` | Remove build artifacts |

### Notarization (for distribution)

```bash
make notarize \
  SIGNING_IDENTITY="Developer ID Application: ..." \
  APPLE_ID=you@example.com \
  TEAM_ID=ABC123
```

## Privacy

- ChatGPT subscription requests, including enabled chat screenshots, are sent to OpenAI through the local Codex process; Codex retains control of the account credentials
- Experimental ChatGPT Web requests are sent to a loopback-only community relay, which controls its own isolated ChatGPT browser profile
- API keys are stored in macOS Keychain — never written to disk as plain text
- Email content is sent directly to your chosen AI provider and nowhere else
- No analytics, no telemetry, no data collection

## License

[MIT](LICENSE)
