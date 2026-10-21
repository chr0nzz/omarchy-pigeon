# Security

## Reporting a vulnerability

Report privately through [GitHub private vulnerability reporting](https://github.com/chr0nzz/omarchy-pigeon/security/advisories/new).
Do not open a public issue for anything that could be exploited.

Include what you found, how to reproduce it, and the Pigeon and Omarchy versions.
You will get an acknowledgement within 7 days and a fix or a decision within 30 days.

## Supported versions

Only the latest release on `main` receives fixes.

## What Pigeon touches

| Data | Where | Notes |
| --- | --- | --- |
| Server URL, topics, auth mode | `~/.config/omarchy/shell.json` | Written by the settings editor and `omarchy bar set` |
| Access token, username, password | `~/.config/omarchy/shell.json` | Stored in plain text, same as every other widget setting. Protect the file with your user permissions |
| Inbox, read state, cursors | `~/.local/state/omarchy/pigeon/state.json` | Full message bodies, plain text. Directory `0700`, file `0600`, also applied to an existing install at startup |
| Image previews | `~/.cache/omarchy/pigeon/previews/` | Up to 16 downloaded attachments, emptied when the shell starts. Directories `0700`, files `0600` |
| Clipboard | `wl-copy` | Only when you press `y` or click Copy |
| Audio | `pw-play` or `aplay` | Only when `sound` is on, plays the bundled chime |

## Network behaviour

| Request | Target | When |
| --- | --- | --- |
| Subscribe stream | Configured server only | Always, while topics are set |
| Publish | Configured server only | Compose box or `omarchy-shell pigeon publish` |
| Open link, open attachment, `view` action | Any `http` or `https` URL from the message | Only on click or keypress |
| Image preview | Attachment URL from the message, fetched by `curl` without credentials | When a message with an image attachment is expanded |
| `http` action | Any `http` or `https` URL from the message | Only on click or keypress, and only when `allowHttpActions` is on |

`curl` runs with `-g`, so `[]` and `{}` in a URL are sent as written and never expand into several requests.
`curl` follows at most 3 redirects and drops the `Authorization` header when a redirect leaves the original host.
Only `http` and `https` URLs are ever opened or fetched. Anything else from a message is ignored.
Topic names are limited to `[A-Za-z0-9_-]` so a message or setting cannot change the request path.
Request bodies reach `curl` on stdin and header names are limited to token characters, so `@file` and other `curl` syntax in a message can never read a local file.
QML never loads a remote URL. Image previews are downloaded by `curl` into the cache with a 10 MiB cap, enforced by `--max-filesize` and again by `head -c`, a 60 second timeout, and `http`/`https` only across redirects. The preview `Image` only reads that local file, decodes at no more than 1200 px a side without upscaling, and Qt rejects any image that would need more than 256 MB to decode.
A message for a topic you did not configure is dropped before it touches the inbox or the cursors, and saved state is filtered the same way when it is loaded. Deleted ids, toast tags, action states, and preview entries are capped, so nothing the server sends grows memory or `state.json` past a fixed size.
A bounded reader sits between `curl` and the shell: stream lines over 64 KiB are dropped before they reach QML, a line with no end within 1 MiB ends the connection, and every message field is cut to a fixed size before it is kept. The limits are listed in the [README](README.md#limits).

## Command lines

Other local accounts can read process command lines with `ps` or `/proc/<pid>/cmdline`. Pigeon keeps private data out of them:

| Data | Path into the child process |
| --- | --- |
| Credentials, `http` action headers | Environment, then an inherited pipe read with `curl -H @/dev/fd/3` |
| Request URLs, including topic names | Environment, then a `curl` config on an inherited pipe read with `-K /dev/fd/4` |
| Publish and action bodies | Environment, then `curl` stdin |
| Copied message text | Environment, then `wl-copy` stdin. The variable is removed before `wl-copy` starts |
| Toast headline and body | Environment, then `toast.py` stdin. The variable is removed before `python3` starts, and `toast.py` sends the D-Bus `Notify` call itself through Gio |
| Toast dismissal | A random 16 character zero-width tag at the end of each toast headline. `omarchy-shell notifications dismiss` gets the tag, never the headline |

If `python3` or `python-gobject` is missing, toasts fall back to `omarchy-notification-send` with only `New message` or `N new messages`.

Opening a link, an attachment, or a `view` action still passes the URL as an argument to `omarchy-launch-browser`, because a browser only takes a URL that way.
Toast bodies are escaped so a message can never add markup to the toast.

## Trust model

- The ntfy server and anyone who can publish to your topics control message content, links, attachments, and actions. An unprotected topic name is a public address.
- `http` actions run a request from your machine to a publisher chosen URL with publisher chosen method, headers, and body. Keep `allowHttpActions` off unless you trust every publisher on every topic.
- The `omarchy-shell pigeon` IPC commands are available to any process running as your user. Text given to `omarchy-shell pigeon publish` is part of that command's own arguments.
- Message text, server errors, and every other string Pigeon shows are rendered as plain text, never as rich text or markdown. `tests/qml.test.js` fails if any `Text` lacks `textFormat: Text.PlainText`.

## Out of scope

- The ntfy server itself. Report those to [binwiederhier/ntfy](https://github.com/binwiederhier/ntfy/security).
- The Omarchy shell, `curl`, `jq`, `wl-copy`, or `python-gobject`.
