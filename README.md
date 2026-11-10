# Oralis

**Voice-first, accessibility-first email for macOS.**

Oralis is a native macOS email client built from the ground up for screen reader users. Talk to an AI assistant to manage your inbox hands-free — read emails aloud, delete spam in bulk, unsubscribe from mailing lists, accept meeting invites, and open links — all by voice or keyboard, with full VoiceOver support throughout.

---

## Features

### Voice control
Say commands like:
- *"Read my latest email"*
- *"Delete all spam"*
- *"Unsubscribe from this list"*
- *"Archive everything older than a week"*
- *"How many unread emails do I have?"*
- *"Reply to the last email from Sarah"*

Oralis understands natural language and translates it into real actions on your inbox.

### Batch actions
Select any number of emails with the spacebar and act on all of them at once — delete, archive, mark as read, or move to spam. Works on hundreds of emails in a single command.

### Voice link reader
When reading an email, say *"Read links"* to hear every link. Say a link's name to open it in your browser.

### Unsubscribe by voice
Say *"Unsubscribe"* on any promotional email. Oralis automatically finds the unsubscribe method (one-click List-Unsubscribe, webpage, or reply email) and handles it for you.

### Calendar invites
Accept or decline meeting invites by voice. Oralis adds accepted events to your macOS Calendar and can read the meeting link (Zoom, Teams, Meet, Webex) aloud.

### Multiple accounts
Add as many accounts as you need — Gmail, Outlook / Exchange, iCloud, Yahoo, or any IMAP / SMTP provider. Oralis can also import accounts already set up in macOS Mail (opt-in).

### Voice customisation
Choose your preferred reading voice from Apple's full catalogue, including high-quality Premium voices. Adjust reading speed, pitch, and volume. Toggle options like reading the sender name and date before each email.

### Accessible onboarding
A 7-step, VoiceOver-guided setup walks you through choosing a voice, connecting your first account, and configuring the AI assistant — entirely by keyboard and voice, with no sighted assistance required.

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- Microphone access (for voice commands)
- An Anthropic API key (for the AI assistant — optional but recommended)

---

## Installation

1. Go to the [latest release](https://github.com/raja-763/Oralis/releases/latest) and download **Oralis-1.0.0.dmg**.
2. Open the DMG file. macOS will mount it as a disk image.
3. Inside the disk image, drag **Oralis.app** into the **Applications** shortcut.
4. Eject the disk image.
5. Open **Oralis** from your Applications folder.
6. Follow the voice-guided onboarding. Oralis will ask for microphone and speech recognition permissions on first launch — both are required for voice commands.

> **VoiceOver tip:** When the DMG opens, press VO+Shift+M to open the Finder menu and navigate to the mounted volume, then drag Oralis.app to Applications with VO+Command+Drag or use the keyboard shortcut shown in the onboarding.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⌥L | Start / stop listening |
| ⌘⌥A | Toggle AI assistant panel |
| ⌘A | Select all emails |
| ⌘⌫ | Delete selected emails |
| Space | Toggle selection on focused email |
| ⌘R | Reply |
| ⌘⌥R | Read email aloud / stop |
| ⌘⌥U | Unsubscribe from focused email |
| ⌘F | Search inbox |
| ⌘, | Open Settings |

---

## Getting an API key

The AI assistant requires an Anthropic API key.

1. Go to [console.anthropic.com](https://console.anthropic.com) and sign up or log in.
2. Under **API Keys**, create a new key.
3. In Oralis, open **Settings › AI Assistant** and paste the key. It is saved to your Mac's Keychain — Oralis never transmits it anywhere else.

Anthropic offers pay-as-you-go pricing. Typical email management costs a fraction of a cent per session. See [anthropic.com/pricing](https://www.anthropic.com/pricing) for current rates.

---

## Privacy & Security

Your data stays on your Mac.

**Credentials and tokens**
All account credentials, OAuth tokens, and your Anthropic API key are stored exclusively in the **macOS Keychain**. They are never written to disk in plain text, never included in crash reports, and never transmitted to any server operated by Oralis.

**Email content**
Oralis fetches email directly from your provider (Gmail, Outlook, etc.) over encrypted HTTPS or SSL/TLS connections. Email content is processed locally on your device. When you send a voice command, only the relevant context (email subjects, senders, counts) is sent to the Anthropic API to generate a response — full email bodies are never sent unless you explicitly ask Oralis to summarise or reply to a specific message.

**macOS Mail import**
The option to import accounts from macOS Mail reads a local configuration file (`~/Library/Mail/…/Accounts.plist`) once, with your explicit opt-in, and only to pre-fill account settings. No passwords are read from that file.

**Microphone**
The microphone is used solely for voice commands via Apple's on-device SFSpeechRecognizer framework. Audio is not recorded, stored, or transmitted.

**No analytics, no telemetry**
Oralis collects no usage data, crash metrics, or analytics of any kind.

**Open source**
Oralis is fully open source. You can review every line of code at [github.com/raja-763/Oralis](https://github.com/raja-763/Oralis).

---

## Building from source

```bash
# Prerequisites: Xcode 15+, Homebrew
brew install xcodegen

# Clone and build
git clone https://github.com/raja-763/Oralis.git
cd Oralis
xcodegen generate
open Oralis.xcodeproj
```

Build and run the **Oralis** scheme in Xcode. The first launch will trigger permission prompts for microphone and speech recognition.

---

## Supported email providers

| Provider | Auth method | Notes |
|---|---|---|
| Gmail | OAuth 2.0 | Full Gmail API v1 |
| Outlook / Exchange | OAuth 2.0 | Microsoft Graph API |
| iCloud | OAuth 2.0 | iCloud Mail |
| Yahoo | Password + App Password | IMAP |
| Any IMAP / SMTP | Password | Generic provider |

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgements

Built with [Claude](https://claude.ai) by Anthropic (AI assistant), Apple AVSpeechSynthesizer and SFSpeechRecognizer (voice), EventKit (calendar), and WebKit (link reader).
