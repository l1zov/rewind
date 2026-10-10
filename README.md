# Rewind

Rewind is a free, open-source macOS app for instantly clipping highlights of your gameplay. It sits quietly in your menu bar and is always ready to capture your best gaming moments with a simple hotkey.

## Features

- **Instant Replay Capture:** Save the last X seconds of your gameplay instantly (customizable duration).
- **Always Record Mode:** Optionally record continuously so you never miss a moment.
- **Customizable Quality:** Adjust resolution, frame rate, audio codec and container format to suit your needs.
- **Microphone and desktop audio in one track:** Saved clips mix your mic and desktop audio into a single audio track so everyone hears both, with separate **Desktop volume** and **Microphone volume** sliders in Settings.
- **Global Hotkeys:** Configure custom hotkeys for starting/stopping recording and saving replays.
- **Audio Feedback:** Hear customizable sound cues when a recording starts, stops, saves or if an error occurs.
- **Discord Rich Presence:** Show off what you're recording to your friends on Discord.

## Requirements

- macOS 14.0 (Ventura) or later
- At least 10 gb of free disk space on the volume your clips are saved to. Rewind also keeps a rolling buffer of recent footage (up to five minutes) in your Mac's temporary folder, so the system volume needs free space too. Rewind shows a low-storage warning if either one runs low

## Installation
 
1. Go to the [Releases page](https://github.com/l1zov/rewind/releases) and download the `.dmg` from the latest release
2. Open the DMG and double-click **Install Rewind**
3. Launch Rewind from Applications or from the installer prompt
 
**Note:** The first time you open the installer, macOS may block it since it's not yet signed with an Apple certificate. Go to **System Settings -> Privacy & Security**, scroll down and click **Open Anyway**. Read more about Gatekeeper [here](https://disable-gatekeeper.github.io/).

If you prefer to build from source, follow the instructions below.

## Building from Source

Rewind is built using Swift and Swift Package Manager.

1. Clone the repository:
   ```bash
   git clone https://github.com/l1zov/rewind.git
   cd rewind
   ```

2. You can build and run the project using the command line:
   ```bash
   swift build
   swift run
   ```

3. Run the tests:
   ```bash
   swift test
   ```

## Permissions


On first launch, Rewind will ask for **Screen Recording** access. Click Allow. If you accidentally denied it, turn it back on in **System Settings -> Privacy & Security -> Screen Recording**. If Screen Recording access is missing, Rewind won't keep retrying in the background; once you've granted it again, relaunch Rewind.

Turning **Record Microphone** off in Settings also removes Rewind's Microphone permission from macOS (`tccutil reset Microphone`), so it isn't left granted across updates; turning it back on asks again.

## Contact

Discord: https://discord.gg/4Dc9AgGC4e

## Donate

Ko-fi: https://ko-fi.com/l1zov

**Crypto:**
- USDT & USDC (Solana Network): `GhZQc8tGyNdGgSraq7KaLVzZH9EwJxESzKSf4bd7TkW1`
- USDT (TRON Network): `TYmyHtXYBJFgDsNjiM5gwMieemZG3KKJaq`
- LTC (LTC): `ltc1qpvwmcuhxucn07v6uql8af6wxnplt0mad07upsq`

## License

This project is licensed under the terms of the included [LICENSE](LICENSE) file.