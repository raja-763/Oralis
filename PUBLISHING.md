# Publishing Oralis for free, safely

Goal: other people use Oralis, including the AI and the ElevenLabs voices, **without you paying
for their usage**, without the App Store, and without macOS security warnings.

## 1. Who pays for what

| Thing | Who pays | How |
|---|---|---|
| Hosting the download | Nobody | GitHub Releases is free |
| The AI (Anthropic) | Each user | Users paste **their own** Anthropic key in Settings. Anthropic has no free API tier, but Oralis uses a small, cheap model, so usage is typically cents per day |
| ElevenLabs voices | Each user | Users paste **their own** ElevenLabs key in Settings (optional). ElevenLabs has a free plan with monthly credits |
| Everything else | Nobody | Calendar, mail actions and Apple voices cost nothing |

**Never put your own keys in a build you share.** `build_dmg.sh` blanks every key and refuses to
finish if one is found inside the app.

## 2. No security warning, and no cost: the installer

macOS shows "cannot verify the developer" only for files marked as downloaded from the internet.
A file fetched by `curl` is not marked. So users install with one line in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/raja-763/Oralis/main/install.sh | bash
```

It finds the latest release, checks the checksum, installs to Applications, verifies the signature
and opens Oralis. Put this line at the top of your README and release notes.

People who prefer the DMG can still use it: the "READ ME FIRST" file inside explains the one-time
right-click Open step.

*The only way to remove the warning for DMG downloads is Apple's Developer ID and notarization
(US$99 a year). It is optional. `build_dmg.sh` is already set up for it: set `DEVELOPER_ID` and
`NOTARY_PROFILE` and it signs, notarizes and staples.*

## 3. Releasing a new version (free)

1. Bump the version in `project.yml` (`MARKETING_VERSION`), then run `xcodegen generate`.
2. Build the safe DMG: `./build_dmg.sh` (keyless, universal, signature-checked).
3. Test it: `INSTALL_DIR=$(mktemp -d) bash install.sh` after publishing, or open the DMG on a second Mac.
4. Publish: `gh release create vX.Y "build/Oralis.dmg#Oralis-X.Y.dmg" --title "Oralis X.Y" --notes-file notes.md --latest`
5. Check that no key is inside the release: download it and search it for your key values
   (the script does this for you before it finishes).

## 4. Gmail sign-in: the one real limit

Oralis reads and sends Gmail, a *restricted* Google permission. What that means for a free release:

- **In Testing mode:** you add up to 100 named test users in Google Cloud Console. It is free, but
  Google signs those users out every 7 days.
- **In Production, unverified:** switch the OAuth consent screen to "In production". Users click
  through an "unverified app" screen once, and are not signed out weekly. Google caps unverified
  apps at 100 users in total, for the life of the app.
- **Beyond 100 users:** Google requires verification, including an annual third-party security
  assessment that costs thousands of dollars. That is the point where a hosted, paid plan or a
  different design would be needed.

Setup steps (Google Cloud Console):
1. Create a project, enable the Gmail API.
2. OAuth consent screen: External, add the app name, your support email, and a link to `PRIVACY.md`
   on GitHub as the privacy policy.
3. Add the scope `https://mail.google.com/`.
4. Create an OAuth client for a macOS app, and put its **client ID** (not a secret) in
   `Secrets.xcconfig` as `GOOGLE_OAUTH_CLIENT_ID` before building the DMG. Oralis signs in with PKCE
   and needs no client secret.

## 5. Keep your own build private

Your personal copy keeps your keys in `Secrets.xcconfig` (ignored by git). Build it with Xcode or
the normal Release build, never with `build_dmg.sh`. Rotate any key that was ever inside a
published file.
