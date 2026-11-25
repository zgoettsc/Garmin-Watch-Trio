# Garmin-Watch-Trio
## Setting up the watch face (Nightscout address and token)

The face reads glucose, IOB and COB from your Nightscout site every 5 minutes.
The site address and access token are kept out of the repository.

1. In Nightscout: **Admin Tools > Subjects > Add new Subject**, name it
   `watch`, role `readable`, and save. Copy the access token it shows
   (it looks like `watch-0123456789abcdef`).
2. Copy `TrioWatchFace/source/Secrets.mc.example` to
   `TrioWatchFace/source/Secrets.mc`.
3. In `Secrets.mc`, set `NS_URL` to your site (no trailing slash) and
   `NS_TOKEN` to the token. Use `""` for the token if your site is readable
   without one.
4. Build and load the face as usual. `Secrets.mc` is in `.gitignore`; never
   commit it.

### Reading the bottom line of the face

`3m ago` is the time since the watch last got data. If the last poll failed,
a code follows it, for example `12m ago  E401`:

| Code | Meaning |
|---|---|
| `E401` | Nightscout rejected the token |
| `E404` | Wrong site address |
| `E-104` | Phone not connected over Bluetooth |
| `E-2` | No response from the phone (Garmin Connect not running) |
| `E-300` | Request timed out |
| `E-400` | Reply was not the expected JSON |
| other negative | Bluetooth or network problem between watch, phone and site |
