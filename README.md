# Devin Pool — 8 Ball Pool for iPhone

A native two-player 8-ball pool game for iPhone, written in Swift with SwiftUI + SpriteKit.
No third-party dependencies.

## Play

- **Aim**: drag anywhere on the table — the cue rotates with your finger (touching down never
  snaps it). A guide line shows the cue ball path, the ghost ball at contact, the object ball's
  direction and the cue ball's deflection.
- **Spin**: drag the red dot on the cue-ball diagram (bottom right). Top = follow, bottom = draw,
  left/right = english (kicks off cushions). Double-tap to reset.
- **Shoot**: pull the power bar on the right side down and release.
- **Ball in hand** (after a foul): drag the cue ball anywhere on the table, then aim and shoot.
- **New game**: the circular arrow button.

## Rules implemented

Standard two-player 8-ball (simplified WPA):

- Table is open after the break; the first legally potted ball after the break assigns solids/stripes.
- A player keeps shooting after legally potting one of their own balls.
- Fouls (scratch, no contact, hitting the wrong group / the 8 first) give the opponent ball in hand.
- Potting the 8 after clearing your group wins. Potting it early, or scratching while potting it, loses.
- The 8 potted on the break is re-spotted.

## Project layout

```
EightBallPool/
  EightBallPoolApp.swift      App entry
  ContentView.swift           SwiftUI HUD (scoreboard, message banner, power bar, game over)
  Game/
    GameScene.swift           SpriteKit scene: table rendering, input, aim guide, turn flow
    PhysicsEngine.swift       Fixed-step (480 Hz) rigid-sphere physics, see below
    EightBallRules.swift      Turn, foul, group assignment and win/loss logic
    GameModel.swift           ObservableObject bridging the scene and SwiftUI
    Ball.swift                Ball model (position, velocity, full angular velocity, render orientation)
    BallTextures.swift        Sphere-map textures + SpriteKit shader that renders the rolling ball
```

## Physics model

A 2.25" ball on a 7 ft table, simulated in the table plane with real coefficients (Marlow; Alciatore):

- **Cue tip**: ω = 5·v·offset / (2r), so a hit 0.4r above centre starts with natural roll; english
  squirts the cue ball ~3° away from the tip side at maximum offset.
- **Cloth**: sliding friction μs = 0.20 acts while the contact point slips (stun, stop, follow, draw all
  come from this), then rolling resistance μr = 0.015; english decays with μsp = 0.044.
- **Ball–ball**: restitution 0.95 plus surface friction μ = 0.05, which gives cut-induced and
  english-induced throw and transfers a little english to the object ball. The aim guide includes
  stun throw.
- **Cushions**: restitution 0.90, angle-dependent friction (Han 2005) for english kicks and
  running/reverse rebound angles, and the nose rubs off most top/bottom spin, so a rolling ball
  slows more off a rail than a stunned one and curves after the rail.
- **Not modelled**: anything vertical (jumps, masse, cushion nose height), speed-dependent
  coefficients, follow/draw transfer between balls.

## Build & run

Open `EightBallPool.xcodeproj` in Xcode 16+ and run on an iPhone or simulator (iOS 17+).

From the command line (booted or auto-booted simulator):

```
./scripts/run-sim.sh            # defaults to "iPhone 17"
./scripts/run-sim.sh "iPhone 17 Pro"
```

To run on a physical iPhone, select your development team under
*Signing & Capabilities* in Xcode.

## Upload to App Store Connect / TestFlight (no Xcode UI needed)

Bundle ID `pool-ios`, team `J659DC2DZR`. With an App Store Connect API key (App Manager role):

```
export ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<uuid> ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
./scripts/upload-appstore.sh            # uses CURRENT_PROJECT_VERSION from the project
./scripts/upload-appstore.sh 2          # override the build number
```

The script archives unsigned, then `xcodebuild -exportArchive` signs with a cloud-managed
distribution certificate and uploads. Each upload needs a unique build number (App Store Connect
also auto-increments it because `manageAppVersionAndBuildNumber` is enabled).
