# Pilot: an AI remote for your Roku TV

Talk to your TV. Pilot runs on your iPhone, uses Google Gemini to understand what you say,
and controls your Roku over your home Wi-Fi. No laptop or server is needed.

**Features**
- **Pilot tab:** tap the mic and say "play lo-fi beats", "open Netflix", "turn it off in 30 minutes" or "what's on?"
- **Remote tab:** D-pad, playback, volume and power, typing into TV search boxes, and sending links to the TV
- **Apps tab:** every app installed on your TV, with real icons. Tap one to open it.
- **Siri:** "Hey Siri, Ask Pilot" lets you control the TV hands-free. TV buttons also appear in Shortcuts and on the Action Button.
- A live "now playing" card with progress, play/pause, and the TV's connection status

## Build
Every push to `main` runs GitHub Actions on macOS (XcodeGen → xcodebuild) and uploads:
- `iphone-ipa-for-sideloadly`, which you install on your iPhone with Sideloadly (free Apple ID, re-sign every 7 days)
- `ios-simulator-app`, for Appetize (set the `APPETIZE_API_TOKEN` secret to get a browser link)

## First launch
1. On the TV, go to Settings › Network › About and note the IP address.
2. On the TV, go to Settings › System › Advanced system settings › Control by mobile apps and set it to **Enabled**.
3. Get a free Gemini key at https://aistudio.google.com/apikey
4. Enter both in Pilot and tap **Test connection**.

## Beam app (optional)
`roku-beam/` is a tiny Roku dev app that plays direct `.mp4`/`.m3u8` links sent from Pilot.
Zip its contents and install it from `http://<roku-ip>` (Developer Mode).
