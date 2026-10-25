import SwiftUI

// Freeify's visual system, from DESIGN.md: semantic colors, spacing, the character-inspired
// shapes, and the small set of themed components every screen shares.

// MARK: - Color tokens

enum Palette {
    static let canvas = Color(hex: 0x101015) // main background
    static let surface = Color(hex: 0x1B1B23) // rows, panels, mini player
    static let raised = Color(hex: 0x272630) // sheets, menus, current row
    static let pressed = Color(hex: 0x35313E) // pressed secondary surface
    static let borderSubtle = Color(hex: 0x45404F) // decorative separation only
    static let borderControl = Color(hex: 0x82798C) // outlines that carry meaning
    static let textPrimary = Color(hex: 0xF6EDF2)
    static let textSecondary = Color(hex: 0xBEB1C2)
    static let textMuted = Color(hex: 0x96899D)
    static let hair = Color(hex: 0xE9B8D2) // selection, section accents, favorites
    static let action = Color(hex: 0xFF715B) // primary actions and the main play control
    static let activity = Color(hex: 0x71E5EA) // progress, playing, focus
    static let ready = Color(hex: 0xDCEEA5) // saved / available offline
    static let error = Color(hex: 0xFF939E) // errors and destructive actions
    static let inkOnAccent = Color(hex: 0x101015) // text and glyphs on bright fills
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let gutter: CGFloat = 20
    static let thumbnail: CGFloat = 48
    static let rowMinHeight: CGFloat = 72
    static let target: CGFloat = 44
}

// MARK: - Shapes

// A rectangle with one clipped upper-right corner, from the asymmetric hair and armor plates.
// The cut is capped at 15% of the shorter side. Hit areas stay rectangular.
struct ArmorPanelShape: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let cut = min(cut, min(rect.width, rect.height) * 0.15)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// The tapered hair slash beside section titles and selected items. Decorative only.
struct HairSlash: View {
    var height: CGFloat = 18

    var body: some View {
        SVGShape(path: "M14 3 L19 3 L10 21 L7 21 Z", viewBox: 24)
            .fill(Palette.hair)
            .frame(width: height * 0.6, height: height)
            .accessibilityHidden(true)
    }
}

// The eight-sided housing for the large play button.
struct PlayHousing: Shape {
    func path(in rect: CGRect) -> Path {
        SVGShape(path: "M18 0 H54 L72 18 V54 L54 72 H18 L0 54 V18 Z", viewBox: 72).path(in: rect)
    }
}

// Two corner brackets outside full artwork: top-left, and bottom-right turning cyan while playing.
struct ArmorBrackets: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            bracket(color: Palette.borderControl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            bracket(color: isPlaying ? Palette.activity : Palette.borderControl)
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(-6)
        .accessibilityHidden(true)
    }

    private func bracket(color: Color) -> some View {
        SVGShape(path: "M0 14 L0 0 L14 0", viewBox: 14)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .bevel))
            .frame(width: 14, height: 14)
    }
}

// Freeify's themed glyphs, drawn on a 24-point grid with 2-point bevelled strokes.
// Standard actions use system symbols instead.
enum ThemeGlyph {
    static let library = "M4 5H8V20H4Z M11 3H15V20H11Z M18 5H20L22 7V20H18Z"
    static let add = "M4 3H17L21 7V21H3V4Z M12 7V17 M7 12H17"
    static let download = "M12 3V15 M7 10L12 15L17 10 M4 16V19L6 21H18L20 19V16"
    static let queue = "M4 6H18L20 8 M4 12H16L18 14 M4 18H12L14 20"
}

struct GlyphView: View {
    let path: String
    var size: CGFloat = 24

    var body: some View {
        SVGShape(path: path, viewBox: 24)
            .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .square, lineJoin: .bevel))
            .frame(width: size, height: size)
    }

    // The same glyph as a template image, for tab bar items, which only take images.
    @MainActor
    static func image(_ path: String) -> Image {
        let renderer = ImageRenderer(content: GlyphView(path: path).foregroundStyle(.black).padding(1))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return Image(systemName: "music.note.list") }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
    }
}

// Draws simple SVG path data (absolute M, L, H, V, Z) scaled from a square view box.
struct SVGShape: Shape {
    let path: String
    let viewBox: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        var result = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var command: Character = "M"
        var numbers: [CGFloat] = []

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        func flush() {
            switch command {
            case "M", "L":
                var index = 0
                while index + 1 < numbers.count {
                    current = CGPoint(x: numbers[index], y: numbers[index + 1])
                    if command == "M" && index == 0 {
                        result.move(to: point(current.x, current.y))
                        start = current
                    } else {
                        result.addLine(to: point(current.x, current.y))
                    }
                    index += 2
                }
            case "H":
                for x in numbers {
                    current.x = x
                    result.addLine(to: point(current.x, current.y))
                }
            case "V":
                for y in numbers {
                    current.y = y
                    result.addLine(to: point(current.x, current.y))
                }
            case "Z":
                result.closeSubpath()
                current = start
            default:
                break
            }
            numbers = []
        }

        var token = ""
        for character in path + " " {
            if character.isLetter {
                if !token.isEmpty, let value = Double(token) { numbers.append(CGFloat(value)) }
                token = ""
                flush()
                command = character
            } else if character == " " || character == "," {
                if !token.isEmpty, let value = Double(token) { numbers.append(CGFloat(value)) }
                token = ""
            } else {
                token.append(character)
            }
        }
        flush()
        return result
    }
}

// MARK: - Components

// The warm primary action: armor-cut fill, dark label, gentle press.
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.inkOnAccent : Palette.textSecondary)
            .padding(.horizontal, Spacing.gutter)
            .frame(minHeight: 48)
            .background(isEnabled ? Palette.action : Palette.raised, in: ArmorPanelShape(cut: 8))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// A compact status badge with an icon and a label, never color alone.
struct StatusChip: View {
    enum Kind {
        case neutral, downloading, saved, failed

        var color: Color {
            switch self {
            case .neutral: Palette.textSecondary
            case .downloading: Palette.activity
            case .saved: Palette.ready
            case .failed: Palette.error
            }
        }
    }

    let label: String
    let systemImage: String
    var kind = Kind.neutral

    var body: some View {
        Label(label, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.footnote.monospacedDigit())
            .foregroundStyle(kind.color)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 3)
            .background(Palette.raised, in: ArmorPanelShape(cut: 6))
            .lineLimit(1)
    }
}

// A section title with the hair slash.
struct SectionTitle: View {
    let title: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            HairSlash(height: 18)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// Three small bars while playing; a static pause glyph when paused or with Reduce Motion.
struct PlayingIndicator: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        Group {
            if isPlaying && !reduceMotion {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<3, id: \.self) { bar in
                        Capsule()
                            .frame(width: 3, height: raised ? [12, 7, 10][bar] : [5, 11, 4][bar])
                            .animation(
                                .easeInOut(duration: [0.7, 0.8, 0.65][bar]).repeatForever(autoreverses: true),
                                value: raised
                            )
                    }
                }
                .frame(width: 16, height: 14, alignment: .bottom)
                .onAppear { raised = true }
                .onDisappear { raised = false }
            } else {
                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .frame(width: 16, height: 14)
            }
        }
        .foregroundStyle(Palette.activity)
        .accessibilityElement()
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

// Track list background, rows, and separators in the dark theme.
extension View {
    func themedList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }

    func themedRow(current: Bool = false) -> some View {
        listRowBackground(
            ZStack(alignment: .leading) {
                current ? Palette.raised : Palette.surface
                if current {
                    // The pink leading marker on the current song.
                    Rectangle().fill(Palette.hair).frame(width: 3)
                }
            }
        )
        .listRowSeparatorTint(Palette.borderSubtle)
    }
}
