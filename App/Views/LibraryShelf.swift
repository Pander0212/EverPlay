import SwiftUI
import EverPlayCore

/// How the library shows games: cover posters or detailed rows.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Covers" : "List" }
    var icon: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// The last played game, big: its cover blurred behind, the poster, and a large Play button.
struct ContinueCard: View {
    let item: LibraryItem
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverView(item: item, cornerRadius: 0)
                .scaleEffect(1.35)
                .blur(radius: 26)
                .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 16) {
                CoverView(item: item, cornerRadius: 16)
                    .frame(width: 104, height: 138)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE")
                        .font(.caption2.weight(.heavy)).tracking(1.2)
                        .foregroundStyle(item.tint)
                    Text(item.title)
                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(item.engineLabel) · \(item.playtime)")
                        .font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(Theme.accent, in: Capsule())
                            .shadow(color: Theme.accent.opacity(0.5), radius: 10, y: 4)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                    .accessibilityLabel("Play \(item.title)")
                    .accessibilityIdentifier("continue-\(item.title)")
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityAction(named: "Details", open)
    }
}

/// A cover poster in the grid: tapping it opens the game's page, the round button plays it.
struct PosterCard: View {
    let item: LibraryItem
    var favorite = false
    var compact = false
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Color.clear
                .aspectRatio(0.75, contentMode: .fit)
                .overlay { CoverView(item: item, cornerRadius: compact ? 14 : 20) }
                .overlay(alignment: .topLeading) {
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(.yellow)
                            .padding(7).background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                            .accessibilityLabel("Favorite")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !compact {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.accent, in: Circle())
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                        }
                        .buttonStyle(PressableStyle())
                        .padding(10)
                        .accessibilityLabel("Play \(item.title)")
                        .accessibilityIdentifier("game-\(item.title)")
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !compact {
                    HStack(spacing: 5) {
                        Circle().fill(item.tint).frame(width: 7, height: 7)
                        Text(item.engineLabel).lineLimit(1)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: compact ? play : open)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("details-\(item.title)")
    }
}

/// Recently played games in a row, each one tap from playing.
struct RecentShelf: View {
    let items: [LibraryItem]
    let play: (LibraryItem) -> Void
    let menu: (LibraryItem) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recently played", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        PosterCard(item: item, compact: true, open: {}, play: { play(item) })
                            .frame(width: 96)
                            .contextMenu { menu(item) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}
