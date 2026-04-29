# tests

Diagnostic / regression scripts for `karabiner-cjk-helper`. They use
synthetic events (CGEvent + AppleScript `keystroke`), so they're not
*perfect* simulations of real hardware typing, but they reproduce the
same TIS / IME state machinery and have caught real bugs during
development.

All scripts assume the daemon is installed and running:

```sh
make install
launchctl print gui/$(id -u)/org.dilyin.karabiner-cjk-helper | grep state
# → state = running
```

Run any of them via `swift path/to/script.swift [N]` (interpreted) — no
build step needed.

## `poller.swift`

Live monitor that prints whenever `TISCopyCurrentKeyboardInputSource`
reports a different input source. Useful for ad-hoc debugging:

```sh
swift tests/poller.swift
# → tap your language-switch keys; only changes are printed
```

## `stress_textedit.swift`

Drives **TextEdit** via AppleScript: opens an empty document, switches
input source, sends keystrokes via `tell System Events to keystroke`
(which routes through the IME), reads the document's text back, and
classifies the result. Compares three mechanisms side-by-side:

1. `karabiner-cjk-trigger` — the daemon path
2. `macism` — baseline reference (must be installed via Homebrew)
3. `karabiner-cjk-kicker` — daemon's kicker invoked directly

```sh
swift tests/stress_textedit.swift 12   # 12 cycles per mechanism
```

Output reports per-mechanism × per-target pass/fail and an overall
percentage. **Don't touch the keyboard during the test** — TextEdit
must keep focus.

## `stress_ru_zh.swift`

Focused Russian↔Pinyin alternation through the daemon trigger, in
TextEdit. The transition pair most likely to expose the macOS half-switch
bug — useful for verifying the ASCII-interpose / `TISSetInputMethodKeyboardLayoutOverride`
workaround stays effective after kicker changes.

```sh
swift tests/stress_ru_zh.swift 30      # 30 alternating cycles
```

## What the tests can NOT catch

- Real-keyboard typing through Karabiner-Elements' virtual HID device
  (synthetic events take a different path through the OS).
- The IME server's per-app input-source memory drift over a long session
  (tests run too fast to reproduce this).
- Failures that only appear under sustained CPU load.

For those, you have to test interactively. The classical sequence is:
tap each language key in turn, type a known string in each language,
visually verify what appears.
