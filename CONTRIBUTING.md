# Contributing

## Setup

```bash
git clone https://github.com/chr0nzz/omarchy-pigeon.git
cd omarchy-pigeon
omarchy plugin add "$PWD" --enable
```

Edits hot-reload. If a change does not apply, run `omarchy restart shell`.
`quickshell log -i <instance> -t 100` shows QML errors, `quickshell list --all` prints the instance id.

## Layout

| File | Role |
| --- | --- |
| `Service.qml` | One per session: settings, curl stream, inbox state, toasts, publish, IPC |
| `BarWidget.qml` | The bar pill, one per monitor |
| `Panel.qml` | The popup inbox and the settings editor |
| `components/MessageRow.qml` | One inbox row |
| `components/TopicStrip.qml` | Topic pills that fit one line, used by the tabs and the compose box |
| `sounds/pigeon.wav` | The chime |
| `Model.js` | Pure logic: parsing, priorities, tags, URLs, time formatting |
| `Emojis.js` | ntfy emoji tag table |
| `tests/` | Node tests for `Model.js` and `Emojis.js` |

## Tests

```bash
npm test
```

Needs Node 22 or newer, nothing else. The tests load `Model.js` and `Emojis.js` directly, so anything that can live in `Model.js` should, with a test next to it.
Add or update a test for every change to `Model.js` or `Emojis.js`. QML changes are checked by hand in a running shell.

## Style

- No code comments, in any language. Name things so they explain themselves.
- No em dashes anywhere: code, docs, commit messages. Use a comma, a hyphen, or a full stop.
- Match the shell: build on `KeyboardPanel`, `CursorSurface`, `Button`, `TextField`, and `ConfirmDialog`, and take colours, spacing, and fonts from the theme. Do not invent new styles.
- Only `curl`, `jq`, `wl-copy`, and `pw-play` or `aplay` for the chime may be called. No new runtime dependencies.
- Credentials go to child processes through the environment, never on the command line.
- Anything from a message is untrusted. Render it as plain text and pass URLs through `Model.safeHttpUrl`.
- Keep docs short. Prefer a table to a paragraph. Describe what a thing does, not why.

## Pull requests

- One change per pull request.
- Commit messages are a single line.
- Update `README.md` when behaviour, settings, keys, or IPC change.
- Bump `version` in `manifest.json` and `package.json` only when asked in review.
- Security issues go through [SECURITY.md](SECURITY.md), not a pull request.

## Releases

1. Bump `version` in `manifest.json` and `package.json`, commit, push.
2. Tag and push the tag:

```bash
git tag -a v0.1.3 -m "v0.1.3"
git push origin v0.1.3
```

The release workflow checks the tag against `manifest.json`, runs the tests, creates the GitHub release, and opens the marketplace verification issue for the tagged commit. The last step needs a `MARKETPLACE_TOKEN` repository secret, a classic personal access token with the `public_repo` scope.

By contributing you agree that your work is released under the [MIT License](LICENSE).
