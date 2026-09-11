# tailclip

One clipboard across your Macs, over Tailscale. A rewrite of
[telltail](https://github.com/ajitid/telltail-center) with the parts that expired taken out.

- **center/** — a Sinatra app on the always-on Mac. It holds the latest clip (text or PNG) and
  tells every connected device over SSE when it changes. `GET /` is a page any tailnet device
  can paste into or copy from.
- **sync/** — a Swift daemon on every Mac. It watches the pasteboard and sends changes to Center,
  and writes what other devices send back to the pasteboard. Raycast's clipboard history picks
  those writes up like any other copy.

Center listens on `127.0.0.1:8788` only; `tailscale serve --https=8443` puts it on the tailnet
with a certificate Tailscale renews. Nothing here runs its own tailnet node, so there is no
auth key to expire.

Sync tags what it writes with a private pasteboard type and skips it on the next poll, so a
received clip never gets sent back. It also skips passwords (`org.nspasteboard.ConcealedType`),
files copied in Finder, anything over 10 MB, and content identical to the last clip it saw.

## Install

```sh
bin/install center   # on the always-on Mac
bin/install sync     # on every other Mac
```

Sync reads `TAILCLIP_CENTER` if Center lives somewhere other than the default in
`sync/Sources/tailclip-sync/main.swift`.

## Test

```sh
cd center && bundle exec rspec
cd sync && swift run sync-check
```
