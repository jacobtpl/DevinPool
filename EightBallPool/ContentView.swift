import SpriteKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = GameModel()

    private let topHUDHeight: CGFloat = 82
    private let bottomHUDHeight: CGFloat = 62

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

                    Spacer(minLength: 0)

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
            right: 10
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
        case .ballInHand: return text.isEmpty ? "Ball in hand: drag the cue ball" : text
        default: return text
        }
    }
}

// MARK: - Controls

private struct ControlsView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                model.newGame()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New game")

            PowerBar(model: model)
        }
    }
}

private struct PowerBar: View {
    @ObservedObject var model: GameModel

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.green, .yellow, .orange, .red],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, width * model.power))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(model.canShoot ? 0.35 : 0.1), lineWidth: 1.5)
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12, weight: .bold))
                    Text(model.power > 0.05 ? "Release to shoot" : "Pull right to set power")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                    Spacer()
                    Text("\(Int(model.power * 100))%")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .opacity(model.power > 0.05 ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .foregroundStyle(.white.opacity(0.85))
            }
            .opacity(model.canShoot ? 1 : 0.4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard model.canShoot else { return }
                        model.power = min(max(value.translation.width / (width * 0.85), 0), 1)
                    }
                    .onEnded { _ in
                        model.shoot()
                    }
            )
        }
        .frame(height: 44)
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
