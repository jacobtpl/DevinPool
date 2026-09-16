import SpriteKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameModel()

    private let topHUDHeight: CGFloat = 82
    private let bottomHUDHeight: CGFloat = 66
    private let powerBarWidth: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: model.scene)
                    .ignoresSafeArea()
                    .onAppear { updateInsets(geo) }
                    .onChange(of: geo.safeAreaInsets) { _, _ in updateInsets(geo) }

                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        ScoreboardView(model: model)
                        MessageBanner(text: model.message, phase: model.phase)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .frame(height: topHUDHeight, alignment: .top)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PowerBar(model: model)
                            .frame(width: powerBarWidth)
                            .padding(.vertical, 24)
                            .padding(.trailing, 8)
                    }

                    ControlsView(model: model)
                        .padding(.horizontal, 14)
                        .frame(height: bottomHUDHeight, alignment: .bottom)
                        .padding(.bottom, 2)
                }

                if let winner = model.winner {
                    GameOverView(winner: winner, message: model.message) {
                        model.newGame()
                    }
                }
            }
        }
    }

    private func updateInsets(_ geo: GeometryProxy) {
        model.scene.hudInsets = UIEdgeInsets(
            top: geo.safeAreaInsets.top + topHUDHeight + 4,
            left: 10,
            bottom: geo.safeAreaInsets.bottom + bottomHUDHeight + 6,
            right: 8 + powerBarWidth + 8
        )
    }
}

// MARK: - Scoreboard

private struct ScoreboardView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.players, id: \.number) { player in
                PlayerCard(
                    player: player,
                    isActive: model.currentPlayer == player.number && model.winner == nil,
                    isOpenTable: model.isOpenTable
                )
            }
        }
    }
}

private struct PlayerCard: View {
    let player: PlayerStatus
    let isActive: Bool
    let isOpenTable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Player \(player.number)")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                Spacer()
                Text(player.group?.rawValue ?? (isOpenTable ? "Open" : "—"))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                if let group = player.group {
                    ForEach(Array(group.numbers), id: \.self) { n in
                        MiniBall(number: n, dimmed: !player.remaining.contains(n))
                    }
                    MiniBall(number: 8, dimmed: !player.remaining.isEmpty)
                } else {
                    Text(isOpenTable ? "Pot a ball to claim a group" : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: 13)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.16 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? Color.yellow.opacity(0.9) : Color.white.opacity(0.08), lineWidth: isActive ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

private struct MiniBall: View {
    let number: Int
    let dimmed: Bool

    var body: some View {
        ZStack {
            Circle().fill(number >= 9 ? Color.white : Color(BallTextures.baseColor(number)))
            if number >= 9 {
                Rectangle()
                    .fill(Color(BallTextures.baseColor(number)))
                    .frame(height: 6.5)
                    .clipShape(Circle())
            }
            Text("\(number)")
                .font(.system(size: 6, weight: .heavy, design: .rounded))
                .foregroundStyle(number == 8 ? .white : Color(white: 0.1))
        }
        .frame(width: 13, height: 13)
        .opacity(dimmed ? 0.18 : 1)
    }
}

// MARK: - Message banner

private struct MessageBanner: View {
    let text: String
    let phase: GamePhase

    var body: some View {
        Text(displayText)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(displayText.isEmpty ? 0 : 0.45)))
            .animation(.easeInOut(duration: 0.2), value: displayText)
    }

    private var displayText: String {
        switch phase {
        case .ballsMoving, .shooting: return ""
        case .ballInHand: return text.isEmpty ? "Ball in hand: drag the cue ball to place it" : text
        default: return text
        }
    }
}

// MARK: - Controls

private struct ControlsView: View {
    @ObservedObject var model: GameModel
    @State private var confirmingNewGame = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                confirmingNewGame = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New game")
            .alert("Start a new game?", isPresented: $confirmingNewGame) {
                Button("New Game", role: .destructive) { model.newGame() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current game will be lost.")
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(spinLabel)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(model.power > 0.05 ? "Release to shoot" : "Pull the bar down to set power")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            SpinControl(model: model)
        }
    }

    private var spinLabel: String {
        let s = model.spin
        if hypot(s.x, s.y) < 0.05 { return "Spin: none" }
        var parts: [String] = []
        if s.y > 0.1 { parts.append("top") } else if s.y < -0.1 { parts.append("back") }
        if s.x > 0.1 { parts.append("right") } else if s.x < -0.1 { parts.append("left") }
        return "Spin: " + parts.joined(separator: " + ")
    }
}

/// Cue-ball diagram: drag the red dot to choose where the tip strikes the ball.
private struct SpinControl: View {
    @ObservedObject var model: GameModel

    private let diameter: CGFloat = 56

    var body: some View {
        let radius = diameter / 2
        let dotOffset = CGSize(width: model.spin.x * radius, height: -model.spin.y * radius)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [Color.white, Color(white: 0.78)],
                                   center: .init(x: 0.38, y: 0.32), startRadius: 2, endRadius: radius)
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: radius, y: 6))
                p.addLine(to: CGPoint(x: radius, y: diameter - 6))
                p.move(to: CGPoint(x: 6, y: radius))
                p.addLine(to: CGPoint(x: diameter - 6, y: radius))
            }
            .stroke(Color.black.opacity(0.12), lineWidth: 1)
            // Miscue limit: the tip slips off the ball beyond half a radius.
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.black.opacity(0.22))
                .frame(width: diameter * GameModel.maxSpinOffset, height: diameter * GameModel.maxSpinOffset)
            Circle()
                .fill(Color.red)
                .frame(width: 11, height: 11)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .offset(dotOffset)
        }
        .frame(width: diameter, height: diameter)
        .opacity(model.canShoot ? 1 : 0.4)
        .contentShape(Circle().inset(by: -8))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard model.canShoot else { return }
                    let x = (value.location.x - radius) / radius
                    let y = -(value.location.y - radius) / radius
                    model.setSpin(CGPoint(x: x, y: y))
                }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.setSpin(.zero) })
        .accessibilityLabel("Spin")
        .animation(.easeOut(duration: 0.08), value: model.spin)
    }
}

/// Vertical power bar: pull down to load the shot, release to strike.
private struct PowerBar: View {
    @ObservedObject var model: GameModel

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.green, .yellow, .orange, .red],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: max(0, height * model.power))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(model.canShoot ? 0.35 : 0.1), lineWidth: 1.5)
                VStack {
                    Image(systemName: "chevron.down.2")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.top, 10)
                    Spacer()
                    Text("\(Int(model.power * 100))")
                        .font(.system(.caption2, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .opacity(model.power > 0.05 ? 1 : 0)
                        .padding(.bottom, 8)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .opacity(model.canShoot ? 1 : 0.4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.canShoot else { return }
                        model.power = min(max(value.translation.height / (height * 0.85), 0), 1)
                    }
                    .onEnded { _ in
                        model.shoot()
                    }
            )
        }
    }
}

// MARK: - Game over

private struct GameOverView: View {
    let winner: Int
    let message: String
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🎱")
                    .font(.system(size: 56))
                Text("Player \(winner) wins!")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onRestart) {
                    Text("Play Again")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.green))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.12, blue: 0.16))
            )
            .padding(32)
        }
        .transition(.opacity)
    }
}

#Preview {
    ContentView()
}
