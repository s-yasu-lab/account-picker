# AccountPicker

**A free macOS tool that lets you choose which Google account (Chrome profile) opens a link — every time you click one.**

[日本語のREADMEはこちら → README.ja.md](README.ja.md)

When you click a Google Docs link in Slack or Chatwork, it opens in whatever account Chrome used last — leaving your name in the document's view history. AccountPicker prevents that by asking you first.

## Features

- Click any link → a picker dialog appears → the page opens in the Chrome profile you choose
- **Auto-detects your Chrome profiles on every launch.** Adding, removing, or renaming accounts is reflected automatically — no config file to edit
- An Incognito option (leaves no trace) is always available
- **100% free and 100% local.** Zero network communication, zero telemetry, nothing is ever sent or collected (the whole tool is one plain-text script — audit it yourself)
- No third-party apps required. Built entirely on built-in macOS features (AppleScript)

## Requirements

- macOS (Apple Silicon or Intel)
- Google Chrome

## Install

1. Download `install.sh`
2. Open Terminal and run:

```bash
bash ~/Downloads/install.sh
```

3. Answer the prompts (run the test → set as default browser; when macOS asks, click **"Use AccountPicker"**)

That's it. From now on, clicking a link in any app shows the picker.

## Tips

- The list shows your actual Chrome profiles (profile name + signed-in email address)
- Double-click an entry or press Return to open; press esc to cancel
- Double-click the app itself (`~/Applications/AccountPicker.app`) for a maintenance menu: test run, profile list, etc.

## Troubleshooting

```bash
bash install.sh --doctor
```

Runs a full diagnosis: registration status, default browser, Chrome profiles.

## Uninstall

```bash
bash install.sh --uninstall
```

Restores your previous default browser (Chrome/Safari) and removes the app.

## How it works

`install.sh` compiles an AppleScript applet on your machine, adds http/https URL schemes and an HTML document declaration to its `Info.plist`, and registers it with macOS as a browser. Once set as the default browser, macOS delivers clicked URLs to the applet's `on open location` handler. The applet reads Chrome's Local State to build the profile list, then launches your choice via `open -na "Google Chrome" --args --profile-directory="..."`.

## Notes

- If Slack/Chatwork is set to open links in its built-in browser, the OS default browser is bypassed. Switch those apps to "open in external browser"
- If multiple Google accounts are signed in to a single Chrome profile, Google uses the profile's default account. One account per profile is recommended
- Provided as-is, without warranty of any kind (MIT License). Use at your own risk

## License

MIT
