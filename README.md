# tailclip

Copy on one Mac, paste on the other. Text and images, over Tailscale, no cloud, no account,
nothing that expires. Raycast's clipboard history on each Mac fills up on its own, because it
records whatever hits the pasteboard and doesn't care who put it there.

It's a rewrite of [telltail](https://github.com/ajitid/telltail-center) with the annoying parts
removed. Same two halves:

- **Center** — a small Ruby (Sinatra) server on the Mac that's always on. Holds the latest clip
  and tells everyone when it changes. Also serves a web page your phone can paste into.
- **Sync** — a small Swift daemon on every Mac. Watches the pasteboard, sends changes to Center,
  writes what comes back.

## What you need

- Two or more Macs signed in to the same Tailscale account, with Tailscale.app running.
- One of them always on. That's where Center lives. (Here: the Mac mini.)
- Xcode Command Line Tools on every Mac (`xcode-select --install` if `swift --version` complains).
- Ruby on the Center Mac. Any recent one, from wherever you usually get Ruby.

You do not need Xcode, Homebrew, Docker, or a Tailscale auth key. If you find yourself
generating a key, stop, you've wandered off.

## Install on the always-on Mac

```sh
git clone https://github.com/ikraamg/tailclip.git
cd tailclip
bin/install center
```

That does four things. You can read `bin/install`, it's short.

1. `bundle install` in `center/`.
2. Loads a LaunchAgent, `com.ikraam.tailclip.center`, that runs Puma on `127.0.0.1:8788`.
   Localhost only. Nothing on your LAN can see it.
3. `tailscale serve --bg --https=8443 http://127.0.0.1:8788`. Tailscale now answers
   `https://<this-mac>.<tailnet>.ts.net:8443` for tailnet devices only, with a certificate it
   renews itself. This is the whole reason there's no expiry bug.
4. Runs `bin/install sync` with that URL, because this Mac has a clipboard as well.

It prints the URL at the end. Write it down, you'll want it for the other Macs and the phone.

Port 8443 and not 443? Because something else might already be on 443. `tailscale serve status`
shows what's mapped where. Don't clobber it.

If more than one person is on your tailnet, read "Who can read your clipboard" below before
you go any further.

## Install on every other Mac

```sh
git clone https://github.com/ikraamg/tailclip.git
cd tailclip
bin/install sync https://<your-center>.<your-tailnet>.ts.net:8443
```

The URL is the one `bin/install center` printed. Don't guess it, run `tailscale status` on the
Center Mac and copy the name. It ends up as `TAILCLIP_CENTER` in the LaunchAgent, and Sync
refuses to start without it.

That builds `sync/` in release mode, copies the binary to `~/.local/bin/tailclip-sync`, and loads
the `com.ikraam.tailclip.sync` LaunchAgent. It starts at login and restarts if it dies.

## Check it actually works

Do this. Don't skip it because it "looks fine". On the Mac you just installed:

```sh
launchctl list | grep tailclip            # a PID and a 0, not a "-"
tail -3 ~/Library/Logs/tailclip-sync.log  # one "tailclip-sync on <host>" line, no loop of "disconnected"
```

Now the loop, both directions:

```sh
echo "hello from $(hostname)" | pbcopy; sleep 2
curl -s -D - <center-url>/clip
```

Expect `x-device: <your host name>` and your text. Then pretend to be another device:

```sh
curl -s -X POST <center-url>/clip \
  -H 'Content-Type: text/plain' -H 'X-Device: fake' --data 'hi back'
sleep 2; pbpaste
```

Expect `hi back`. Run the first `curl` again and check `x-seq` did not tick up. If it did,
Sync sent the received clip back out, which is the one bug this thing is built to not have.
Open an issue on yourself.

Images: take a screenshot with ⌃⇧⌘4 (to clipboard), then `curl -s -D - -o /dev/null <url>/clip`
should say `content-type: image/png`.

Then the real test: copy something on Mac A, open Raycast's clipboard history on Mac B. It's
there or it isn't.

## The phone

Open `<center-url>/` in the phone's browser while its Tailscale is on. You get the latest clip, a Copy button, and a box to send text from. That's
it. There's no app and there won't be one; iOS and Android kill background clipboard readers.

## Who can read your clipboard

Everyone on your tailnet. That's the whole security model, so be clear about what it means:

- Any device that can reach the Center Mac on port 8443 can read the latest clip and push text
  or an image onto every Mac running Sync. Tailscale decides who that is. On a tailnet of one
  person and their own devices, that's you. On a shared tailnet, or with shared nodes, it's
  them too.
- What lands on your pasteboard is whatever the sender sent. If you then paste it into a
  terminal, that's what runs. Treat a received clip like you'd treat one from a coworker's
  screen share: fine most of the time, but look before you paste a command.
- Center keeps one clip in memory and never writes it to disk. Sync logs device names and
  sequence numbers, never content.
- Center only listens on `127.0.0.1` and only admits the `Host` values Tailscale Serve sends,
  so a web page open on the Center Mac can't reach it by DNS rebinding.

Two ways to narrow it:

- `TAILCLIP_LOGINS=you@example.com bin/install center` makes Center refuse any request Tailscale
  Serve stamps with a different login (comma-separate to allow several). A request with no
  login came from the Center Mac itself and is allowed. Serve overwrites the header if a client
  tries to send its own, so this can't be spoofed from the tailnet.
- Tailscale ACLs can restrict port 8443 on the Center Mac to your own devices.

Never put this behind `tailscale funnel`. That's the public internet, and Center has no login of
its own.

## What Sync refuses to send

On purpose. Each one is a line in `sync/Sources/SyncCore/ClipDecision.swift` and a check in
`sync/Sources/sync-check/main.swift`.

- Anything it wrote itself. Every write carries a private pasteboard type
  (`com.ikraam.tailclip`); the next poll sees the tag and shuts up. No echo loop.
- Passwords. 1Password, Bitwarden and friends mark copies as `org.nspasteboard.ConcealedType`.
  Skipped. Same for `TransientType`.
- Files copied in Finder. That "copy" is a file URL plus the file name as text; sending the
  name alone is useless, and sending the file is a different project.
- Empty text, and anything over 10 MB.
- The same content as the last thing it sent or received. Copying the same thing twice does
  nothing, which is what you'd want.

Everything else goes: text as `text/plain`, images as PNG (TIFF screenshots get converted).

## When it breaks

- **`Host not permitted`** on the URL — Center is being reached by a name that isn't `*.ts.net`
  or localhost. Use the URL `bin/install center` printed.
- **`login not permitted`** — you set `TAILCLIP_LOGINS` and this device is signed in as someone
  else. Check `tailscale status` on that device.
- **Sync log says `TAILCLIP_CENTER is not set`** — run `bin/install sync <center-url>` with the URL.
- **403 from the URL on your phone** — the phone isn't on the tailnet. Turn Tailscale on.
- **Sync log loops "events disconnected ... retrying"** — Center is down or the URL you gave
  `bin/install sync` is wrong. Check `tail ~/Library/Logs/tailclip-center.log` on the always-on Mac.
- **Copied something, nothing arrived** — check the refuse list above. Then check Sync is running
  on *both* Macs; it's the one you forgot.
- **Restart a thing:** `launchctl kickstart -k gui/$(id -u)/com.ikraam.tailclip.sync` (or `.center`).
- **Remove a thing:** `launchctl bootout gui/$(id -u)/com.ikraam.tailclip.sync` and delete the
  plist from `~/Library/LaunchAgents/`. For Center also `tailscale serve --https=8443 off`.

## Working on it

```sh
cd center && bundle exec rspec       # 25 specs, five of them against a real Puma for the SSE stream
cd sync && swift run sync-check      # 12 checks; Command Line Tools have no XCTest, so it's an executable
```

After a change, `bin/install center` or `bin/install sync <center-url>` rebuilds and reloads. Then run the
"check it actually works" section again. Green tests say the code runs; they don't say your
clipboard moved.

## Why not X

- **Apple Universal Clipboard** — Mac to Mac, same Apple ID, works when it feels like it, no
  way to see why it didn't. This one has a log file and a curl command.
- **Telltail as-is** — its server joined the tailnet as its own node with an auth key, and auth
  keys expire. Its client used `pbpaste` and couldn't tell its own writes from yours, so it
  had a copy loop on the todo list. Both gone here.
- **A cloud sync service** — your clipboard has your passwords in it sometimes. No.
