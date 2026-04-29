# karabiner-cjk-helper

A tiny background helper that fixes macOS' broken programmatic input-source
switching, so that Karabiner-Elements key taps for Pinyin / Russian / Latin
layouts actually engage the right input method every time.

## The problem

You have Karabiner-Elements bound to switch input sources on key tap
(e.g. `left_command` → English, `right_command` → Russian, `left_control`
→ Pinyin). It works for plain keyboard layouts, but for Apple Pinyin
(`com.apple.inputmethod.SCIM.ITABC`) — and for any switch that crosses
between a non-ASCII layout (Russian, Arabic, Hebrew, Greek) and a CJK IME
— you observe one or more of:

- The macOS menu-bar input-source icon updates, but typing keeps
  going through the previous layout. You have to click the menu bar
  manually to make the switch "take".
- After typing in Pinyin, switching back to Russian leaves you typing
  Latin (`dhbsgk`) instead of Cyrillic (`привет`).
- The above behaves randomly: works most of the time, fails seemingly
  at random in heavy use.

This is **not a Karabiner bug** — Karabiner's `select_input_source` action
just calls Carbon's `TISSelectInputSource`, which is what every other tool
uses. The Karabiner maintainer has explicitly declared this out of scope
(see [pqrs-org/Karabiner-Elements#4266](https://github.com/pqrs-org/Karabiner-Elements/issues/4266)).

The actual bugs are in macOS:

1. **Faceless launchd-managed daemons** (which is what
   `karabiner_console_user_server` is) aren't treated as "valid TSM clients"
   for CJK IME activation. `TISSelectInputSource` returns success but the
   IME server never binds the new source to the focused text input client.
2. **Switching between a non-ASCII layout and a CJK IME** leaves the
   underlying Latin layout half-resolved. Apple's documented workaround
   is to interpose an ASCII layout (e.g. ABC). See
   [Apple Discussions #8197631](https://discussions.apple.com/thread/8197631).

## What this helper does

Three components, all outside the Karabiner-Elements source tree:

- **`karabiner-cjk-helper`** — a long-lived launchd agent. Listens on
  `/tmp/karabiner-cjk-helper.sock`. On each request it spawns the kicker
  with `posix_spawn(POSIX_SPAWN_SETSID)` so the kicker gets its own
  session and is treated as a foreground-eligible TSM client. The daemon
  itself never touches Carbon/TIS — that's deliberate, because long-lived
  TIS-touching processes appear to leak IME state.
- **`karabiner-cjk-kicker`** — a short-lived AppKit one-shot that does
  the actual switching:
  - For non-CJK targets: plain `TISSelectInputSource`.
  - For CJK targets: optional pre-switch through Colemak (when current
    is non-ASCII, e.g. Russian), then `TISSelectInputSource`, then
    `TISSetInputMethodKeyboardLayoutOverride` to pin Pinyin's underlying
    Latin layout to Colemak (so your Colemak fingers produce the right
    pinyin syllables, not QWERTY transliterations of them), then the
    macism-style window-flash to engage the IME server.
  - For CJK → non-ASCII transitions: two-step via Colemak with a 40 ms
    gap so the second TIS call isn't coalesced.
- **`karabiner-cjk-trigger`** — a 30-line C client that opens the socket
  and writes the target input-source id. Fast (~2 ms cold), so Karabiner's
  `shell_command` invocation of it doesn't add perceptible latency.

The Latin layout used as the override / interpose is hard-coded to prefer
Colemak first, then ABC, then U.S. — adjust `pickAsciiLatin()` in
`src/karabiner-cjk-kicker.swift` if your preferred Latin layout is
different.

## Installation

Requires macOS 13+, Xcode command line tools, and Homebrew (only used
for `make`).

```sh
git clone https://github.com/widgetii/karabiner-cjk-helper.git
cd karabiner-cjk-helper
make build
make install        # sudo for /usr/local/bin install + launchctl bootstrap
```

Verify the daemon is running:

```sh
launchctl print gui/$(id -u)/org.dilyin.karabiner-cjk-helper | grep state
# → state = running
```

## Karabiner-Elements config

Replace your existing `select_input_source` actions with `shell_command`
calls to the trigger. Example (from `~/.config/karabiner/karabiner.json`):

```json
{
  "to_if_alone": [
    { "shell_command": "/usr/local/bin/karabiner-cjk-trigger com.apple.keylayout.Colemak" }
  ]
}
```

```json
{
  "to_if_alone": [
    { "shell_command": "/usr/local/bin/karabiner-cjk-trigger com.apple.keylayout.Russian" }
  ]
}
```

```json
{
  "to_if_alone": [
    { "shell_command": "/usr/local/bin/karabiner-cjk-trigger com.apple.inputmethod.SCIM.ITABC" }
  ]
}
```

Karabiner reloads its config automatically when you save the file.

## Uninstall

```sh
make uninstall
```

## Reliability

In a TextEdit-driven end-to-end test (synthetic keystrokes via
AppleScript `keystroke`, 30 cycles alternating Russian↔Pinyin):

| Transition       | Reliability |
|------------------|-------------|
| Colemak ↔ Russian | 100%        |
| Colemak ↔ Pinyin  | ~95%        |
| Russian ↔ Pinyin  | ~85% Pinyin engage, 100% Russian engage |

The remaining Pinyin failures appear to be the underlying macOS-level
randomness — they happen at the same rate with `macism` directly.

## Credits

- The "tiny key window" IME-engagement trick is from
  [`laishulu/macism`](https://github.com/laishulu/macism), which itself
  credits a [Squirrel issue
  comment](https://github.com/rime/squirrel/issues/866#issuecomment-2800561092)
  for the empirical insight.
- The "interpose ASCII layout to fix Cyrillic↔CJK" workaround is documented
  in [Apple Discussions](https://discussions.apple.com/thread/8197631).

## License

MIT. See [LICENSE](LICENSE).
