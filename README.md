# Devin Pool — 8 Ball Pool for iPhone

A native two-player 8-ball pool game for iPhone, written in Swift with SwiftUI + SceneKit.
No third-party dependencies. The table is rendered in 3D from a player's-eye view behind the
cue ball, with an overhead view for the layout and ball-in-hand.

## Play

- **Aim (player view)**: drag left/right to walk around the cue ball and aim down the cue; drag
  up/down to raise or lower your eye. Touching down never snaps the aim. A guide line shows the
  cue ball path, the ghost ball at contact, the object ball's direction and the cue ball's deflection.
- **Overhead view**: the grid button toggles a top-down camera; drag around the cue ball to aim there.
  The camera stands up automatically while the balls are moving.
- **Spin**: drag the red dot on the cue-ball diagram (bottom right). Top = follow, bottom = draw,
  left/right = english (kicks off cushions). Double-tap to reset.
- **Shoot**: pull the power bar on the right side down and release.
- **Ball in hand** (after a foul): in the overhead view, drag the cue ball anywhere on the table,
  then aim and shoot.
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
    GameController.swift      Game loop: physics stepping, input, cameras, cue animation, turn flow
    TableScene.swift          SceneKit scene: table, cushions, pockets, lights, balls, cue, aim guide
    GameSceneView.swift       SCNView host that forwards touches to the controller
    PhysicsEngine.swift       Fixed-step (480 Hz) rigid-sphere physics, see below
    EightBallRules.swift      Turn, foul, group assignment and win/loss logic
    GameModel.swift           ObservableObject bridging the controller and SwiftUI
    Ball.swift                Ball model (position, velocity, full angular velocity, orientation)
    BallTextures.swift        Equirectangular ball textures (colours, stripes, numbers)
```

## Physics model

A 2.25" / 6 oz ball on a 7 ft table, simulated in the table plane at 480 Hz with published
coefficients. Sources: Alciatore's technical proofs and property FAQ (billiards.colostate.edu),
Marlow's *The Physics of Pocket Billiards*, and Mathavan, Jackson & Parkin (Proc. IMechE C, 2010).

| Effect | Model | Values |
| --- | --- | --- |
| Cue tip | Power bar sets cue-stick speed (0.35–8.8 m/s, i.e. up to a 25 mph break); cue-ball speed from TP A.30 (momentum + energy with tip efficiency η, so a max-offset hit leaves at 0.75·v_cue vs 1.27·v_cue for centre ball); ω = 5·v·b / (2r); squirt per TP A.31 | m_ball/m_cue = 6/19, η = 0.87, endmass ratio 19 (→3° at b = 0.5r); tip offset capped at the miscue limit 0.5r |
| Cloth | Coulomb sliding friction on the contact-point slip until the ball rolls; rolling resistance; constant spin-down | μs = 0.20, μr = 0.01, english decel 10 rad/s² |
| Ball–ball | Normal restitution + friction impulse along the 3-D surface slip (cut- and english-induced throw, english and follow/draw transfer); friction falls with rubbing speed (TP A.14 fit to Marlow) | e = 0.95, μ = 0.0100 + 0.108·e^(−1.088·v_rel) |
| Cushion | Mathavan 2010: impact integrated over normal impulse with friction at the nose (height 7r/5) and at the cloth; compression then restitution of e² of the work | e = 0.98, μ_nose = 0.14, μ_cloth = 0.20 |

Emergent behaviour: stop/stun/follow/draw (Dr. Dave's TP B.8 draw example — OB 6 ft away, 11.65 mph cue
at max offset — draws back 5.5 ft here vs his 6 ft), the parabolic cue-ball curve after contact, throw
(~2° on a 30° stun cut), a rolling ball rebounding ~5° long and at ~0.6× speed, running english
lengthening and reverse shortening the rebound, rail-induced english, and rail curve.

Not modelled: the ball leaving the cloth (jumps, hops), masse/swerve from cue elevation, cushion
deformation on very hard hits, and the tiny cloth "ball turn". The aim guide shows stun throw at a
typical speed but not english or speed effects.

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
