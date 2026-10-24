import SwiftUI
import EverPlayCore

/// EverPlay's visual language: calm dark surfaces, one muted violet accent, quiet motion.
enum Theme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.063)
    static let surface = Color(red: 0.082, green: 0.090, blue: 0.114)
    static let elevated = Color(red: 0.110, green: 0.122, blue: 0.153)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.56, green: 0.53, blue: 0.93)
    static let accentSoft = accent.opacity(0.16)

    static func engineColor(_ engine: GameEngine) -> Color {
        switch engine {
        case .html5: return Color(red: 0.45, green: 0.72, blue: 0.69)
        case .rpgMakerMV: return Color(red: 0.86, green: 0.67, blue: 0.42)
        case .rpgMakerMZ: return Color(red: 0.84, green: 0.53, blue: 0.61)
        case .rpgMaker2000: return Color(red: 0.55, green: 0.70, blue: 0.93)
        case .onscripter: return Color(red: 0.78, green: 0.60, blue: 0.88)
        case .rgss: return Color(red: 0.60, green: 0.80, blue: 0.62)
        }
    }

    /// A stable, muted cover gradient derived from the title, so every game gets its own look.
    static func cover(for title: String) -> LinearGradient {
        var hash: UInt64 = 1469598103934665603
        for byte in title.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        let top = Color(hue: hue, saturation: 0.38, brightness: 0.42)
        let bottom = Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.16)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func initials(_ title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Visual style chosen in Settings. Liquid Glass needs iOS 26 and a build with its SDK.
enum AppearanceStyle: String, CaseIterable, Identifiable {
    case standard, liquidGlass
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "Liquid Glass" }

    static var liquidGlassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

private struct SurfaceModifier<S: Shape>: ViewModifier {
    @AppStorage("appearanceStyle") private var style = AppearanceStyle.standard.rawValue
    let shape: S

    func body(content: Content) -> some View {
        if style == AppearanceStyle.liquidGlass.rawValue {
            glass(content)
        } else {
            content.background(Theme.surface, in: shape).overlay(shape.stroke(Theme.stroke, lineWidth: 1))
        }
    }

    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.stroke, lineWidth: 1))
        }
        #else
        content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.stroke, lineWidth: 1))
        #endif
    }
}

extension View {
    /// A card or bar surface: flat in Standard, glass in Liquid Glass (material on older iOS).
    func surface<S: Shape>(_ shape: S) -> some View { modifier(SurfaceModifier(shape: shape)) }
    func surface(cornerRadius: CGFloat = 20) -> some View {
        modifier(SurfaceModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Animated highlight sweep for placeholders and progress text.
    func shimmer(active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

/// Cards sink slightly and spring back, like a physical tile.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PressableBody(configuration: configuration) }

    private struct PressableBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Filled accent button with a soft breathing glow.
struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GlowBody(configuration: configuration) }

    private struct GlowBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var glowing = false
        let configuration: ButtonStyleConfiguration
        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.vertical, 14).padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(glowing ? 0.45 : 0.18), radius: glowing ? 18 : 8, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glowing = true }
                }
        }
    }
}

/// Quiet secondary button on a surface.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.vertical, 14).padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .surface(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
                .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 } }
            }
        }
    }
}

/// Slowly turning, blurred colour field used behind the empty library and the import loader.
struct AmbientOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 220
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let angle = Angle.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 24) * 15)
            Circle()
                .fill(AngularGradient(colors: [Theme.accent, Color(red: 0.36, green: 0.62, blue: 0.78),
                                               Color(red: 0.58, green: 0.40, blue: 0.70), Theme.accent],
                                      center: .center, angle: angle))
                .frame(width: size, height: size)
                .blur(radius: size * 0.28)
                .opacity(0.55)
        }
        .accessibilityHidden(true)
    }
}

/// Indeterminate ring loader for imports.
struct RingLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    var body: some View {
        ZStack {
            Circle().stroke(Theme.stroke, lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(rotating ? 360 : 0))
        }
        .frame(width: 34, height: 34)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotating = true }
        }
        .accessibilityHidden(true)
    }
}

/// Small coloured dot plus engine name.
struct EngineBadge: View {
    let engine: GameEngine
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.engineColor(engine)).frame(width: 7, height: 7)
            Text(engine.title).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
