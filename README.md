# Pogo Lens

An iPhone app that reads your own Pokémon GO screenshots and turns them into a box list:
species, CP, HP, level, IVs, moves. It writes a CSV in the Poke Genie dialect into a Files
folder you pick (iCloud Drive / Pokemon GO), where the Mac-side `pogo` CLI in the Exobrain
harness imports it automatically.

It never logs in to Pokémon GO and never talks to Niantic. Like Poke Genie and Calcy IV, it
reads pixels. That is the only way to see your own account data live that cannot get the
account banned: there is no player API, and every protocol-level client is a ban risk.

## How a scan works

1. In Pokémon GO, open a Pokémon and take a screenshot of its summary screen. For exact IVs,
   open Appraise and screenshot the three bars too.
2. Open Pogo Lens and tap **Scan new screenshots**. Each screenshot since the last scan goes
   through Apple's on-device Vision OCR:
   - **Summary screen**: name (or nickname), CP, HP, types, weight, height, moves, and the
     power-up dust cost. The dust cost fixes the level bracket; CP and HP then leave one or a
     few IV combinations, solved with the same formulas the `pogo` CLI uses (`Formula.swift`).
   - **Appraisal screen**: the three IV bars are read from pixels, located from the OCR'd
     Attack / Defense / HP labels, and attached to the summary taken just before it.
3. With **Export CSV after every scan** on and a sync folder chosen, the CSV lands in the folder
   and the Mac imports it within a minute (`pogo box stats`, `pogo box list`, `pogo box dupes`).

A nicknamed Pokémon is identified from its typing and moves; when several species fit, the
detail view offers a picker. Lucky, shadow, purified and favorite are toggles for now.

## Live scan (no screenshots)

Tap the broadcast icon in the **Live scan** row, choose Start Broadcast, switch to Pokémon GO
and open each Pokémon (Appraise for exact IVs). iOS streams the screen to the app's Broadcast
Upload Extension; about once a second, when the screen has changed, it downscales one frame
to 720 px, OCRs it and parses it exactly as the screenshot path does. Each newly opened
Pokémon is logged to the App Group and announced with one replaced banner over the game.
Stop the broadcast from the red status pill; back in Pogo Lens the readings merge into the
box (a Pokémon seen again within a day is refreshed, not duplicated) and the CSV exports.

The extension lives under a memory ceiling of about 50 MB, hence the pacing, the downscale
into one reused BGRA buffer, and never keeping a full-resolution copy.

## Build and install

```sh
cd ios
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # set DEVELOPMENT_TEAM
scripts/build.sh            # unsigned compile check
scripts/install.sh          # signed build, install and launch on the paired iPhone (Wi-Fi works)
```

XcodeGen (`project.yml`) generates the project; the `.xcodeproj` is not committed. iOS 17+.
The App Group both targets share needs Xcode to talk to Apple's portal once: if `xcodebuild`
stops with "No Accounts", sign in under Xcode > Settings > Accounts and rerun; the group and
the extension's App ID are registered automatically after that.

## Data

`ios/PogoLens/Resources/Data/gamedata.json` bundles base stats (megas included), typing, the
CP multiplier table, dust tiers, move names and movesets from [pogoapi.net](https://pogoapi.net).
`scripts/refresh-data.py` rebuilds it.

## Roadmap: read more of the game

Every screen is one more classifier and parser in `ScreenParser.swift`. In order of leverage:

1. Storage list view from a scrolled screen recording: name and CP for the whole box in one pass.
2. Pokédex pages: caught and seen per species, shiny, lucky, shadow, mega, XXL and XXS badges.
3. Trainer profile: level, XP, medals, lifetime stats.
4. Today view: field, timed and special research and their rewards.
5. Gym detail (defenders, team, motivation) and the Nearby raids panel.
6. Items and eggs.
7. **Live overlay.** iOS has no draw-over-apps overlay (that is Android, and how Calcy IV
   works there). The iOS equivalent is a ReplayKit Broadcast Upload Extension: the player
   starts a screen broadcast to Pogo Lens from Control Center, iOS streams every frame of
   Pokémon GO to the extension while they play, the extension samples a frame a second,
   OCRs it, and writes each read to an App Group container. The readout comes back over the
   game as a local notification banner first, then a Dynamic Island Live Activity. Niantic
   sees a system screen recording, which players do all the time. Needs an App Group
   entitlement and the extension's 50 MB memory ceiling respected (fast OCR on a downscaled,
   change-detected frame). Calibration comes first: constant scanning with untuned parsers is
   constant noise.

## Calibration

The appraisal bar reader and the summary parser were written against the layout of the
screens, not against real screenshots, so the first scans on a device will need tuning. Turn
on **Write OCR debug files to the sync folder** in Settings: each screenshot then also drops
a `pogolens-debug-*.json` with every recognised line and its position, which is what the
parsers are tuned from.
