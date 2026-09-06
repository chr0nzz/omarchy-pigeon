# Pigeon

A [ntfy](https://ntfy.sh) inbox for the [Omarchy](https://omarchy.org) bar. Pigeon keeps a live
subscription open to ntfy.sh or your own server and turns every message into an Omarchy toast
and an entry in a themed popup inbox.

![Pigeon panel](preview.png)

## Features

- Live JSON stream per subscription with automatic reconnect, keepalive watchdog, and catch-up after sleep
- Anonymous, access token, or username and password auth
- Bar pill with unread count that follows the theme, works in any section and on vertical bars
- Native Omarchy toasts with the message's emoji tag, ntfy priority mapped to urgency, and a click that opens the link or the panel
- Inbox panel with topic tabs, search, unread dots, expand in place, image preview, `view` and `http` actions, open link, copy, delete, mark read or unread, mark all read, clear, mute, reconnect, and full keyboard navigation
- Compose box to publish to any topic with a title and priority
- IPC for scripts through `omarchy-shell`
- Inbox and read state survive shell restarts

## Requirements

Omarchy 4 shell, `curl`, `jq`, `wl-copy`. All of them ship with Omarchy.

## Install

```bash
omarchy plugin add https://github.com/chr0nzz/omarchy-pigeon.git --enable
omarchy bar set xyzlab.pigeon server https://ntfy.example.com
omarchy bar set xyzlab.pigeon topics alerts,home
```

The widget lands in the right section. Move it anywhere:

```bash
omarchy bar move xyzlab.pigeon --section center
omarchy bar move xyzlab.pigeon --section left --index 2
```

Pigeon has no default topic. Pick a name that is hard to guess, an unprotected topic is a public address.

## Settings

Press `s` or the gear in the panel to open the settings editor. Enter saves, Esc cancels, Tab moves
between fields. It writes to the widget entry in `~/.config/omarchy/shell.json`, the same values
`omarchy bar set` edits. Changes apply live.

| Key | Default | Meaning |
| --- | --- | --- |
| `server` | `https://ntfy.sh` | Base URL of the ntfy server, reverse proxy prefixes are fine |
| `topics` | `""` | Comma separated topic names |
| `auth` | `none` | `none`, `token`, or `basic` |
| `token` | `""` | Access token for `auth = token` |
| `username` / `password` | `""` | Credentials for `auth = basic` |
| `toasts` | `true` | Show desktop toasts for new messages |
| `toastMinPriority` | `2` | Lowest ntfy priority (1 to 5) that produces a toast |
| `backfill` | `all` | History to load for a new topic: `all`, `12h`, `3d`, or `none` |
| `maxMessages` | `200` | Messages kept in the inbox |
| `allowHttpActions` | `false` | Let publisher defined `http` actions run |
| `showCount` | `true` | Show the unread count next to the glyph |
| `showZero` | `false` | Show the count even when it is zero |
| `glyph` | `""` | Replace the pigeon with your own glyph |

Token auth on a self-hosted server:

```bash
omarchy bar set xyzlab.pigeon server https://ntfy.example.com
omarchy bar set xyzlab.pigeon auth token
omarchy bar set xyzlab.pigeon token tk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
omarchy bar set xyzlab.pigeon topics alerts,backups,home
```

Auth and topic errors (401, 403, 404) show in the panel header and retry once a minute.

## Usage

Bar pill: left click opens the inbox, right click marks everything read, middle click toggles mute.

| Key | Action |
| --- | --- |
| `j` / `k`, arrows | Move the cursor |
| `h` / `l` | Switch topic tab |
| Enter, `e` | Expand or collapse, marks the message read |
| `o` | Open the message's click link |
| `a` | Open the attachment |
| `1` `2` `3` | Run the matching ntfy action |
| `y` | Copy the message |
| `d`, `x`, Delete | Delete the message |
| `D` | Clear the inbox or the current topic tab, with confirmation |
| `u` | Mark all read in the current tab |
| `m` | Mute or unmute toasts |
| `s` | Open the settings editor |
| `r` | Reload the backfill window from the server |
| `c` | Compose. Enter sends, Esc closes |
| `/` | Search. Enter returns to the list, Esc clears |
| `g` / `G` | First / last message |
| Tab / Shift-Tab | Switch to the neighbouring bar panel |
| Esc | Close |

Global shortcut in `~/.config/hypr/bindings.lua`, Omarchy leaves `SUPER + N` free:

```lua
o.bind("SUPER + N", "Pigeon inbox", "omarchy-shell shell toggle xyzlab.pigeon '{}'")
```

## IPC

```bash
omarchy-shell pigeon status
omarchy-shell pigeon publish alerts "Title" "Message"
omarchy-shell pigeon markAllRead
omarchy-shell pigeon clear
omarchy-shell pigeon mute 3600
omarchy-shell pigeon unmute
omarchy-shell pigeon reconnect
omarchy-shell pigeon reload
omarchy-shell shell toggle xyzlab.pigeon '{}'
```

| Command | Effect |
| --- | --- |
| `status` | JSON with state, unread and urgent counts, topics, last error |
| `publish <topic> <title> <message>` | Publish through the configured server |
| `mute <seconds>` | Mute toasts, `-1` mutes until `unmute` |
| `reload` | Re-fetch the backfill window from the server |
| `shell toggle` | Open or close the panel |

Messages you publish from Pigeon show up already read and never toast.

## State

| Path | Content |
| --- | --- |
| `~/.config/omarchy/shell.json` | Settings, including credentials |
| `~/.local/state/omarchy/pigeon/state.json` | Inbox, read state, per-topic cursors, deleted ids |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, layout, tests, and style.
Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
