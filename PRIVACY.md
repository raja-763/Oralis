# Oralis privacy policy

Oralis runs on your Mac. It has no servers, no accounts, no analytics and no tracking.

## What stays on your Mac
- Your email sign-in tokens, kept in the macOS Keychain.
- Your Anthropic and ElevenLabs API keys, if you add them, kept in your Mac's settings.
- A local copy of your recent emails, so your inbox appears instantly when Oralis opens. It is stored
  in your user Library folder and never uploaded by Oralis.
- Your voice and personality choices.
- A small diagnostic log in `~/Library/Logs/Oralis.log` with technical events only, never the text
  of your emails or commands.

## What is sent, and only when you use that feature
- **Google (Gmail):** to read, send, delete and organize your email, directly between your Mac and
  Gmail, under Google's privacy policy.
- **Anthropic:** when you speak or type a request, that request and the relevant part of your inbox or
  calendar are sent to Anthropic's API using your own key, under Anthropic's privacy policy. Nothing is
  sent unless you make a request.
- **ElevenLabs (optional):** the text Oralis speaks is sent to ElevenLabs using your own key, only if you
  turn on an ElevenLabs voice, under ElevenLabs' privacy policy.
- **Senders' unsubscribe links:** when you ask Oralis to unsubscribe, it contacts the sender's
  unsubscribe address, or emails it, on your behalf.
- **Web forms:** only when you ask Oralis to fill in a form, it opens the page you name.

## Your control
Delete Oralis and its folder in `~/Library/Application Support/Oralis` to remove local data. Remove
Oralis's access at https://myaccount.google.com/permissions at any time.

## Contact
Open an issue at https://github.com/raja-763/Oralis/issues
