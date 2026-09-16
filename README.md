# 8 Ball Pool (iPhone)

A native two-player 8-ball pool game for iPhone, written in Swift with SwiftUI + SpriteKit.
No third-party dependencies.

## Play

- **Aim**: drag anywhere on the table — the cue points from the cue ball toward your finger.
  A guide line shows the cue ball path, the ghost ball at contact, the object ball's direction
  and the cue ball's deflection.
- **Shoot**: pull the power bar at the bottom to the right and release.
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
    PhysicsEngine.swift       Custom fixed-step 2D physics (ball/ball, cushions, pockets, aim prediction)
    EightBallRules.swift      Turn, foul, group assignment and win/loss logic
    GameModel.swift           ObservableObject bridging the scene and SwiftUI
    Ball.swift                Ball model
    BallTextures.swift        Procedurally drawn ball textures
```

## Build & run

Open `EightBallPool.xcodeproj` in Xcode 16+ and run on an iPhone or simulator (iOS 17+).

From the command line (booted or auto-booted simulator):

```
./scripts/run-sim.sh            # defaults to "iPhone 17"
./scripts/run-sim.sh "iPhone 17 Pro"
```

To run on a physical iPhone, select your development team under
*Signing & Capabilities* in Xcode.
