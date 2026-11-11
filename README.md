# Oralis 4.0

**A voice-first macOS assistant for blind and visually-impaired users.**

Oralis lets you control email, browse the web, and manage your calendar entirely by voice — no mouse, no reading required. Press a keyboard shortcut, speak naturally, and Oralis handles the rest.

---

## ⚠️ Personal Use Only

Oralis is built for **personal accessibility use**. It is not a commercial product, is not intended for redistribution, and comes with no warranty. Use it for your own needs.

---

## Privacy First

Oralis is **privacy-first** by design:

- **No analytics, no telemetry, no tracking** — Oralis never phones home
- **Email credentials stay on your Mac** — stored encrypted in macOS Keychain, never transmitted
- **AI is opt-in** — the AI assistant only activates when you speak to it; your emails are never sent anywhere automatically
- **AI queries go to Anthropic's Claude API directly** — Anthropic's privacy policy applies; no data is stored by Oralis
- **ElevenLabs voice synthesis** is processed on their servers per their privacy policy; no audio is stored
- **Web browsing stays local** — Oralis does not log sites you visit or forms you fill
- **Calendar access is on-device only** — via macOS EventKit; calendar data never leaves your Mac
- **No account required** — Oralis works for TTS and STT without signing in to anything

---

## Features

### Email (Lumin-inspired)

- **Read** your emails aloud, with sender name and date
- **Summarize** long email threads in a few sentences
- **Triage** your inbox — hear what needs attention
- **Draft** new emails by voice
- **Reply** and **forward** without touching the keyboard
- **Search** by voice query ("emails from John about the invoice")
- **Unsubscribe** from mailing lists in one command
- **Delete spam** in bulk with a single phrase
- **Manage attachments** via voice commands

### Calendar

- **Hear upcoming events** ("What's on my calendar this week?")
- **Create events** by voice ("Add a meeting tomorrow at 3pm")
- **Accept or decline** meeting invites from email

### Voice-Controlled Web Browser

- **Navigate** to any website by voice ("Go to nytimes.com")
- **Read and summarize** web pages aloud
- **Fill out forms** by describing the fields ("Fill in my email address")
- **Click buttons and links** by name ("Click the submit button")
- **Scroll** and navigate back/forward by voice

### 70+ Languages

Oralis speaks and listens in over 70 languages including English, Spanish, French, German, Arabic, Hindi, Japanese, Chinese, Swahili, and more. Change the language in Settings → Voice → Conversation Language. The AI assistant always responds in the language you used.

### Voices

- **Apple system voices** — Premium and Enhanced quality, available offline
- **ElevenLabs AI voices** — Rachel, Josh, Adam, and more (requires API key)
- Adjustable **speed**, **pitch**, and **volume**

---

## Setup

1. Download **Oralis 4.dmg**
2. Open the DMG and drag **Oralis.app** to Applications
3. First launch: **right-click → Open** (once, to bypass Gatekeeper on a personal build)
4. Connect your email account in **Settings → Accounts**
5. Grant **microphone** and **speech recognition** permission when prompted

> **Note:** Oralis is not signed with an Apple Developer ID (this is a personal build). macOS Gatekeeper will warn you on first launch. Right-click → Open to proceed.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘⌥Space** | Open / close Oralis from anywhere |
| **⌘⌥L** | Start / stop listening |

---

## AI Assistant (Optional)

For the AI features (summarize, draft, triage, web reading), add your Anthropic API key to `Secrets.xcconfig`:

```
ANTHROPIC_API_KEY = sk-ant-...your key here...
```

Get a key at [console.anthropic.com](https://console.anthropic.com). The app works without it — voice commands for navigation, reading, and playback are always available.

---

## Requirements

- **macOS 14.0** or later
- Apple Silicon or Intel Mac
- Microphone access (for voice input)

---

## Building from Source

```bash
# Install xcodegen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build and package (strips quarantine automatically)
./build_dmg.sh
```

The build script removes the quarantine flag from the DMG, so users never see the Gatekeeper warning.
