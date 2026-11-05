# Readout

Readout is a macOS menu bar app that reads selected text aloud. Select text in any app,
press **⌃⌥R**, and it starts speaking. Press **⌃⌥R** again to stop, or **⌃⌥P** to pause and
resume.

It runs entirely on your Mac. It makes no network requests, collects no analytics, and keeps no
record of what it reads. Speech comes from the system's offline voices (`AVSpeechSynthesizer`),
or from optional [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) neural voices that also run
on your Mac.

- Menu bar only, with no Dock icon. Launch at login is optional.
- Gets the selection through the Accessibility API. Where an app doesn't expose its selection,
  Readout presses ⌘C for you and then puts your clipboard back exactly as it was.
- Cleans up Markdown before speaking: tables become "column: value" sentences, code blocks are
  skipped, links are shortened to their domain, and symbols are spoken as words.
- Splits text into sentences and queues them, so even very long selections start speaking
  immediately and stop instantly.
- A floating mini player shows the sentence being read, highlights the current word, and has
  controls for back, play/pause, stop, forward and speed.

Requires macOS 14 or later and Swift 5.9 or later.

## Build and run

```bash
make app        # builds build/Readout.app (release, ad-hoc signed)
make run        # builds and opens it
make install    # builds and copies it to /Applications
make test       # unit tests: clean-up, sentence splitter, reading queue
make selftest   # timing and clipboard checks against the real speech engines
make neural-voice  # one-time download of the optional Kokoro neural voices (about 360 MB)
```

The project is a Swift package. `Package.swift` is the project file, and you can open it
directly in Xcode (**File › Open…** or `open Package.swift`). Use the `Readout` scheme to build
and debug. To run the app for real, use `make app`: that wraps the binary in a proper `.app`
with the `Info.plist` that hides the Dock icon.

### Building without Xcode

The scripts work with only the Command Line Tools installed, which is how this was built.
`scripts/toolchain.sh` handles two problems with that setup:

- Starting with the macOS 27 SDK, SwiftUI's `@State` is a macro, and its plugin ships only with
  full Xcode. When Xcode is missing, the script picks the newest installed SDK where `@State` is
  still a plain property wrapper (macOS 26.5 on this machine).
- It passes the Swift Testing macro plugin path explicitly, because SwiftPM doesn't always find
  it with the Command Line Tools.

When full Xcode is installed, the script steps aside and the normal SDK is used.

## Grant Accessibility permission

Readout needs Accessibility access to see what you've selected in other apps and to press ⌘C
when an app doesn't share its selection.

1. Launch Readout. The welcome window explains why it needs access.
2. Click **Open Accessibility Settings**. Readout adds itself to the list and opens
   **System Settings › Privacy & Security › Accessibility**.
3. Turn on **Readout**, and unlock with your password if asked.
4. Switch back. The welcome window notices within a second and shows **Access granted**.

You can reopen this window from the menu bar icon (**Grant Accessibility Access…**). The
permission status is also shown under **Settings › General**.

**Keeping the permission across rebuilds.** macOS ties Accessibility access to the app's code
signature. An ad-hoc signature changes on every build, so each rebuild would lose the
permission. To avoid that, create a local signing certificate once:

```bash
scripts/create-signing-identity.sh
```

This creates a self-signed certificate called "Readout Local Signing" (code signing only, valid
for 10 years) in your login keychain, and gives only `codesign` access to its key. It isn't marked
as trusted system-wide, and it doesn't need to be. `make app` then signs with it automatically
and prints which identity it used. The signature's designated requirement becomes
`identifier "dev.readout.Readout" and certificate leaf = H"…"`, which stays the same across
builds, so you grant access once. Without the certificate, builds are ad-hoc signed and you have
to remove Readout from the Accessibility list and add it again after each rebuild. To sign with a
different identity, such as a Developer ID, set `SIGN_IDENTITY="…"`.

## Change the hotkeys

1. Open **Settings…** from the menu bar icon (or press ⌘, while Settings is open).
2. In the **General** tab, click the shortcut next to **Read selection / stop** or **Pause / resume**.
3. Press the new combination. It must include ⌃, ⌥ or ⌘.

While you're recording, **Esc** cancels, **Delete** clears the shortcut, and **Default**
restores ⌃⌥R or ⌃⌥P. Readout won't let both actions use the same shortcut. Shortcuts are saved
straight away and work in every app.

## Voices and speed

**Settings › Voice** lists every installed voice, grouped by language, with Premium and Enhanced
voices first. ★ marks languages that have a Premium or Enhanced voice.

- **Automatic** uses the best installed voice for your system language.
- **Switch voice when the text is in another language** detects the selection's language and
  uses the best voice installed for it.
- **Speed** goes from 0.5× to 2×. **Preview** plays a sample. If you change the speed while
  Readout is reading, the current sentence restarts at the new speed.

The voices macOS ships by default are basic. For much more natural speech (still offline), go
to **System Settings › Accessibility › Spoken Content › System Voice › Manage Voices…** and
download a Premium or Enhanced voice, for example *Ava (Premium)* or *Zoe (Premium)*. Settings
has a button that opens that pane. New voices appear in Readout as soon as they finish
downloading.

## Neural voices (Kokoro)

Kokoro is an open neural text-to-speech model (82M parameters, Apache-2.0). It sounds much
closer to a real person than the system voices. Readout runs it locally through the
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) runtime. Install it once:

```bash
make neural-voice
```

That runs `scripts/fetch-neural-voice.sh`, which downloads two files from the official
k2-fsa/sherpa-onnx GitHub releases. It checks each file's SHA-256, then installs them into
`~/Library/Application Support/Readout/Neural`:

| File | Size | What it is |
| --- | --- | --- |
| `sherpa-onnx-v1.13.8-osx-universal2-shared-lib.tar.bz2` | 18 MB | the runtime: sherpa-onnx and ONNX Runtime libraries |
| `kokoro-multi-lang-v1_0.tar.bz2` | 334 MB | the Kokoro v1.0 model, voices, lexicons and espeak-ng data |

The script is the only part of Readout that uses the network. The app never downloads anything.
It looks for the files at launch and loads the runtime with `dlopen`, so Readout builds and runs
the same with or without them.

Once installed, **Settings › Voice** lists 27 English neural voices under English (US) and
English (UK). They're marked *(Neural)* and sorted best first: *Heart*, *Bella*, *Emma*, *Nicole*,
*Michael* and so on. **Automatic** picks *Heart*. Text in other languages still goes to the
system voices when **Switch voice when the text is in another language** is on.

Measured on this Mac (`make selftest`):

| | System voice | Kokoro |
| --- | --- | --- |
| Selection to first audio | 35 ms | 0.7–0.8 s |
| Stop | 3 ms | 1 ms |
| Memory while loaded | — | about 680 MB in total |

Kokoro renders a sentence in about a fifth of the time it takes to say it. While one sentence
plays, the next one is already rendering, so there are no gaps. To start quickly, Readout renders
the first clause of a long opening sentence on its own. The model loads when Readout launches
(about 0.7 s, in the background) and is released after 15 minutes without reading, so the first
read after a long pause takes about a second longer.

The sherpa-onnx 2.0 runtime is deliberately not used. It dropped the espeak-ng fallback, so any
word missing from its lexicon is silently skipped, even common words like "selected". 1.13.8
pronounces every word.

## Text clean-up

This is on by default. Turn it off in **Settings › Text**, which also has a box where you can
paste text and see exactly what will be spoken.

| Input | Spoken as |
| --- | --- |
| `# Heading`, `**bold**`, `*italic*`, `` `code` ``, `> quote`, `- item` | the text, without the symbols; headings and list items become their own sentences |
| A Markdown table | one sentence per row: "Name: Alice, Age: 30." |
| A fenced code block | "Code block skipped." (or the code itself, if you turn skipping off) |
| `https://www.example.com/a/b?c=d` | "example.com" |
| `[the docs](https://…)` | "the docs" |
| `&`, `->`, `→` | "and", "to" |
| `e.g.`, `i.e.`, `etc.`, `vs.` | "for example", "that is", "et cetera", "versus" |
| Line breaks inside a paragraph (common in PDFs) | joined, with hyphenated words repaired |

## Project layout

```
Readout/
  App/            ReadoutApp (entry point), AppModel (wiring), Preferences, SelfTest
  Hotkeys/        KeyboardShortcuts names and a shortcut recorder
  Selection/      Accessibility selection, the ⌘C fallback, clipboard snapshot and restore
  Speech/Core/    SpeechEngine protocol, ReadingQueue, SentenceSplitter, LanguageDetector
  Speech/Engines/ SystemSpeechEngine (AVSpeechSynthesizer), NeuralSpeechEngine and KokoroSynthesizer
                  (Kokoro via sherpa-onnx), RoutingSpeechEngine (picks one per voice), VoiceCatalog
  Speech/CSherpaOnnx/ the sherpa-onnx v1.13.8 C header, used for its types only
  TextCleanup/    TextCleaner (Markdown, tables, code, URLs, symbols)
  UI/             menu, settings, onboarding, mini player, HUD
Tests/            unit tests for the ReadoutCore target
Resources/        Info.plist
scripts/          toolchain selection and app bundling
```

`TextCleanup` and `Speech/Core` form the `ReadoutCore` target. It has no AppKit dependency, so
all of its logic is covered by unit tests.

### Adding another speech engine

To add another engine, implement `SpeechEngine` from `Speech/Core/SpeechEngine.swift`. Then send
its voices to it from `RoutingSpeechEngine` and list them in `VoiceCatalog`.
`NeuralSpeechEngine` is a worked example. The
queue hands the engine one sentence at a time (with one queued ahead) and expects the following:

- Call the delegate on the main actor: `didStart` when a sentence begins, `willSpeak` with word
  ranges if the engine has them, and `didFinish` when the sentence ends.
- After `stop()`, send no callbacks for anything queued before it.
- `pause()` and `resume()` act on whatever is currently playing.

The queue handles skipping, speed changes, the end of the text, and ignoring stale callbacks.

## Developer options

```bash
build/Readout.app/Contents/MacOS/Readout --self-test        # prints PASS/FAIL timings, then quits
open -W build/Readout.app --args --self-test --report /tmp/readout.txt  # same, as a normal launch
open build/Readout.app --args --read "Text to speak now"    # reads the given text on launch
open build/Readout.app --args --settings                    # opens Settings on launch
```

## Known limitations

- **Apps that don't expose their selection through Accessibility** use the ⌘C fallback. These
  include Chrome, Arc, Brave, Edge, Firefox, and Electron apps such as Slack, VS Code, Discord,
  Notion and Obsidian. The fallback adds about 50–150 ms.
- **Places where ⌘C doesn't copy text, so capture fails:** remote desktop and VM windows (⌘C goes
  to the remote machine), pages that block copying, apps that remap ⌘C, terminal programs that
  capture the mouse, canvas-drawn text in games and some design tools, and scanned PDFs with no
  text layer. Readout shows "Nothing selected" in these cases.
- **Password fields** are never read. Readout detects secure text fields and skips the fallback.
- **Clipboard managers** (Maccy, Raycast, Paste and others) may record the temporary copy as a
  history entry. Your clipboard contents are put back exactly, but the history entry stays.
  Restoring also counts as a clipboard change, so apps that sync the clipboard (such as Universal
  Clipboard) may sync it again.
- **Keyboard layouts:** Readout finds the key that types "c" in your current layout, so Dvorak,
  AZERTY and non-Latin layouts work. Layouts that switch to QWERTY while ⌘ is held
  ("Dvorak – QWERTY ⌘") can send the wrong key.
- **Languages without an installed voice:** macOS doesn't ship an Urdu voice, for example. Text in
  that language is read by your chosen voice, which usually can't pronounce it.
- **Neural voices are English only.** The Kokoro model has voices for other languages, but they
  need pronunciation data that this runtime and model package don't include. The neural word
  highlight is estimated from playback time, so it can drift by a word or so, while system
  voices report exact word timings.
- **Neural voice memory:** Readout uses about 680 MB while Kokoro is loaded. Use a system voice
  if that matters more than quality.
- **Licences:** Kokoro and sherpa-onnx are Apache-2.0. The espeak-ng pronunciation data in the
  model package is GPL-3.0. That's fine for personal use; check the terms before you
  redistribute Readout together with the model.
- **Speed changes** restart the current sentence rather than changing speed mid-sentence.
- **Signing:** the local certificate is for your own Mac. Gatekeeper will block Readout on other
  Macs unless it's signed with a Developer ID and notarized.
- **KeyboardShortcuts is pinned to 1.15.0.** Later versions use `#Preview`, which needs full Xcode
  to compile. Readout also uses its own shortcut recorder instead of `KeyboardShortcuts.Recorder`.
  The package's localization bundle would have to sit at the root of the `.app`, which `codesign`
  rejects. Once Xcode is installed, both can be upgraded.

## Licence

Readout is released under the [MIT licence](LICENSE).

It builds on other people's work, each under its own licence:

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and
  [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) (MIT): Swift
  packages fetched at build time.
- `Readout/Speech/CSherpaOnnx/include/sherpa-onnx-c-api.h`, from
  [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache-2.0): included unchanged.
- The neural voice download, which isn't part of this repository: the sherpa-onnx and ONNX Runtime
  libraries (Apache-2.0 and MIT), the [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
  model (Apache-2.0), and the espeak-ng pronunciation data bundled with it (GPL-3.0).
