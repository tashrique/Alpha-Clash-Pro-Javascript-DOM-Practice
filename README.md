# LyricDash

Spotify lyrics on your CarPlay screen next to the map, plus a sound when CarPlay connects.

LyricDash is a personal iPhone app (iOS 26+). It doesn't need Apple's special CarPlay app
permission. It uses two things iOS 26 already puts on CarPlay:

| What you see in the car | How it works |
|---|---|
| **The current lyric line on the CarPlay Dashboard, next to Maps** | A **Live Activity** (`.small` family). iOS 26 shows Live Activities on the CarPlay Dashboard. |
| **A lyrics widget on the CarPlay widget page** | A **WidgetKit widget** (`systemSmall`). iOS 26 shows iPhone widgets on CarPlay. |
| **A chime when CarPlay connects** | An App Intent you call from a Shortcuts **"When CarPlay connects"** automation. It also plays from inside the app if the app is already running. |

```
Spotify Web API ──(what's playing + position, every 4s)──┐
                                                         ▼
LRCLIB (synced lyrics, once per song) ──────────► NowPlayingEngine ──► Live Activity ──► CarPlay Dashboard
                                                         │                            └─► Lock Screen / Dynamic Island
                                                         └──► App Group snapshot ──► Widget ──► CarPlay widget page
```

## Limits to know first

- **Spotify has no lyrics API.** The lyrics Spotify shows in its own app (from Musixmatch) can't be
  read by other apps. LyricDash uses [LRCLIB](https://lrclib.net), a free, community-built database of
  time-synced lyrics. Most popular songs are there. Some songs only have unsynced lyrics or nothing.
- **There's no custom full-screen CarPlay app.** That needs a CarPlay entitlement from Apple, and Apple
  only gives it to certain kinds of apps (audio, navigation, EV charging, parking and a few others).
  A lyrics viewer doesn't fit any of them. That's why LyricDash uses a Live Activity and a widget.
- **You don't control where the system puts it.** iOS decides where the Live Activity and widget appear
  on CarPlay. The layout depends on your car's screen size and iOS version.
- **Staying alive in the background:** iOS would normally suspend the app while Maps is in front.
  LyricDash keeps a low-power location session running during the drive so lyrics keep updating.
  That's fine for personal use, but App Store review would likely reject it.
- **Sync is close, not perfect.** Live Activity updates can be throttled by the system, and the widget
  can drift after you seek. Use the **Lyric timing** slider in the app if lines feel early or late.
- Keep it glanceable while you drive. The car layout is deliberately big text with 1 to 3 lines.

## What you need

- A Mac with **Xcode 26** or later
- An iPhone on **iOS 26** or later, and a CarPlay car or head unit
- An **Apple Developer Program** membership ($99/year). A free Apple ID technically works, but
  those builds stop working after 7 days and some capabilities this app uses may not be available.
- A Spotify account (Premium recommended)

## Setup

### 1. Create a Spotify developer app

1. Go to <https://developer.spotify.com/dashboard> and choose **Create app**.
2. Set the **Redirect URI** to exactly `lyricdash://callback`.
3. Under "Which API/SDKs are you planning to use", tick **Web API**.
4. Open the app's **Settings** and copy the **Client ID**.
5. In **User Management**, add the email address of your own Spotify account. Development-mode
   apps only work for users on this list. Spotify has been tightening development-mode rules, so
   check the dashboard if sign-in fails.

### 2. Put your keys in `.env`

The only key this app needs is the **Spotify Client ID**. With PKCE sign-in there's no client
secret, and there's no server. Your Apple Team ID isn't a secret either, but it's personal, so it
goes in `.env` too.

```bash
git clone <this repo> && cd <repo>
cp .env.example .env        # .env is git-ignored, so it never gets committed
open -e .env                # fill in the 4 values (each one is explained in the file)
./scripts/setup.sh          # writes Config.local.xcconfig (git-ignored) + generates the Xcode project
```

| `.env` key | Where to find it |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com > Account > Membership details > Team ID |
| `BUNDLE_ID` | Make one up: `com.<yourname>.lyricdash` |
| `APP_GROUP_ID` | `group.` + your bundle ID |
| `SPOTIFY_CLIENT_ID` | Spotify dashboard > your app > Settings |

Run `./scripts/setup.sh` again whenever you change `.env`.

### 3. Install it on your iPhone

```bash
open LyricDash.xcodeproj
```

1. Plug in your iPhone (or pair it over Wi-Fi). On the phone, turn on
   *Settings > Privacy & Security > Developer Mode* and restart when asked.
2. In Xcode, choose the **LyricDash** scheme, pick your iPhone at the top, and press **Run** (Cmd-R).
3. With automatic signing, Xcode creates the App ID and App Group for you. If it complains, open
   *Signing & Capabilities* on both targets, choose your team, and make sure the same App Group is ticked.

The app then stays on your phone like any other app.

#### "Can I get an APK?"

APK files are Android-only. The iPhone version is an **.ipa**, and an iPhone only installs an
.ipa if it's signed for your device. So there's no file you can just download and tap. Your options:

| Option | Cost | How long the install lasts | Effort |
|---|---|---|---|
| **Xcode > Run** (above) | $99/yr developer account | 1 year, then press Run again | Easiest |
| **TestFlight**: Xcode > Product > Archive > Distribute > TestFlight Internal | $99/yr | 90 days per build; install from the TestFlight app with no cable | Medium |
| Free Apple ID + Xcode Run | Free | **7 days**, and widgets/App Groups may not work | Annoying |

For a personal app, use **Xcode > Run** once a year. If you'd rather not plug in, use TestFlight.

### 4. First run on the phone

1. Tap **Connect Spotify** and sign in.
2. Tap **Allow background (location)** twice: first choose **While Using**, then **Always**.
3. Allow Live Activities if iOS asks. You can also turn them on in *Settings > LyricDash*.
4. Play a song on Spotify and tap **Start lyrics**. You should see the line change in the app and
   on the Lock Screen.

### 5. Turn it on in CarPlay

- On the iPhone, go to *Settings > General > CarPlay > (your car)*. Make sure **Widgets** (and
  Live Activities, if your iOS version lists it separately) are on.
- To add the **Lyrics** widget, long-press the CarPlay widget page or use the widget settings on
  the iPhone.
- With lyrics running, open the CarPlay **Dashboard** to see Maps and the lyric line side by side.

### 6. Automatic start + connect sound (recommended)

This works even when LyricDash is closed:

1. Open **Shortcuts > Automation > + > CarPlay**.
2. Choose **Connects**, then **Run Immediately**.
3. Add these actions:
   1. *(optional, most reliable)* **Open App > LyricDash**
   2. **Start CarPlay Lyrics** (LyricDash)
   3. **Play CarPlay Connect Sound** (LyricDash)
4. Optional: make a second automation, **CarPlay > Disconnects > Stop CarPlay Lyrics**.

Pick the sound in the app: Rise, Glass, Pulse, or **My sound** (any audio file from Files).
Spotify gets turned down while the chime plays and comes back afterwards. If the app is also
running, it won't play the chime twice.

## Does CarPlay need any login or approval?

**No.** LyricDash doesn't use Apple's CarPlay app framework, so you don't need a CarPlay entitlement
or approval from Apple. Nothing to sign into in the car, and nothing to pair besides your usual
CarPlay connection. iOS 26 shows any app's widgets and Live Activities on CarPlay automatically.

The only sign-ins are one-time, on the phone:
- **Spotify:** tap *Connect Spotify* once. The app refreshes the token by itself after that.
- **Permissions:** allow Location (Always) and Live Activities.

**Testing on a Mac without a car:** Xcode > Open Developer Tool > Simulator, run the app on an
iPhone simulator, then *I/O > External Displays > CarPlay*. Or download the standalone
**CarPlay Simulator** (in *Additional Tools for Xcode* on developer.apple.com) and connect a real
iPhone to it over USB.

## Tests

`LyricDashTests` covers LRC parsing, picking the current line, the widget hand-off, the chime
synthesis, the Spotify PKCE sign-in URL, and a live LRCLIB lookup. GitHub Actions
(`.github/workflows/ios.yml`) builds the app for iOS and runs the tests on an iPhone simulator on
every push and pull request. Locally: Cmd-U in Xcode.

## Project layout

```
project.yml                     XcodeGen spec (app + widget extension + tests)
.env.example                    Template for your keys (copy to .env, which is git-ignored)
scripts/setup.sh                .env -> Config.local.xcconfig -> xcodegen generate
Config.xcconfig                 Placeholder build settings (your real values come from .env)
Shared/                         Code compiled into both targets
  LyricActivityAttributes.swift   Live Activity data
  WidgetSnapshot.swift            App Group hand-off to the widget
LyricDash/                      The iPhone app
  Spotify/                        PKCE sign-in, Keychain, "currently playing" client
  Lyrics/                         LRCLIB lookup + LRC parser
  Engine/                         Polling/sync engine, Live Activity, background keeper
  CarPlay/                        CarPlay connect detection + chime synth/player
  Intents/                        Shortcuts actions (start/stop lyrics, play sound)
  ContentView.swift               Settings + now-playing screen
LyricDashWidgets/               Widget extension
  LyricLiveActivity.swift         Dashboard / Lock Screen / Dynamic Island views
  NowPlayingLyricWidget.swift     CarPlay + home screen widget (timeline per line)
LyricDashTests/                 Unit tests
.github/workflows/ios.yml       CI: build + test on macOS
```

## Troubleshooting

- **"Connect Spotify" fails with INVALID_CLIENT or a redirect error:** `SPOTIFY_CLIENT_ID` in `.env`
  or the redirect URI in the Spotify dashboard is wrong. Fix it, run `./scripts/setup.sh`, then Run again.
- **Lyrics stop updating after a few minutes in the car:** location permission isn't set to
  **Always**, or Low Power Mode is on.
- **"No synced lyrics for this song":** LRCLIB only has plain lyrics for that track. You can add
  synced lyrics to LRCLIB yourself.
- **Nothing on the CarPlay Dashboard:** check that Live Activities are allowed for LyricDash and
  that your car's CarPlay screen shows the Dashboard. Some very small screens show less.
