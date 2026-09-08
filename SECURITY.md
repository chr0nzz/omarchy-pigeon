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
| Inbox, read state, cursors | `~/.local/state/omarchy/pigeon/state.json` | Full message bodies, plain text |
| Clipboard | `wl-copy` | Only when you press `y` or click Copy |

## Network behaviour

| Request | Target | When |
| --- | --- | --- |
| Subscribe stream | Configured server only | Always, while topics are set |
| Publish | Configured server only | Compose box or `omarchy-shell pigeon publish` |
| Open link, open attachment, `view` action | Any `http` or `https` URL from the message | Only on click or keypress |
| Image preview | Attachment URL from the message | When a message with an image attachment is expanded |
| `http` action | Any `http` or `https` URL from the message | Only on click or keypress, and only when `allowHttpActions` is on |

Credentials go to `curl` through the process environment, never on the command line.
`curl` follows at most 3 redirects and drops the `Authorization` header when a redirect leaves the original host.
Only `http` and `https` URLs are ever opened or fetched. Anything else from a message is ignored.
Topic names are limited to `[A-Za-z0-9_-]` so a message or setting cannot change the request path.
A bounded reader sits between `curl` and the shell: stream lines over 64 KiB are dropped before they reach QML, a line with no end within 1 MiB ends the connection, and every message field is cut to a fixed size before it is kept. The limits are listed in the [README](README.md#limits).

## Trust model

- The ntfy server and anyone who can publish to your topics control message content, links, attachments, and actions. An unprotected topic name is a public address.
- `http` actions run a request from your machine to a publisher chosen URL with publisher chosen method, headers, and body. Keep `allowHttpActions` off unless you trust every publisher on every topic.
- The `omarchy-shell pigeon` IPC commands are available to any process running as your user.
- Message text is rendered as plain text, never as rich text or markdown.

## Out of scope

- The ntfy server itself. Report those to [binwiederhier/ntfy](https://github.com/binwiederhier/ntfy/security).
- The Omarchy shell, `curl`, `jq`, or `wl-copy`.
