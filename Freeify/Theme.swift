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
    static let action = Color(hex: 0xF5443A) // primary actions and the main play control; the gloves' red
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

// The bevel along an armor panel's clipped corner, from the faceted shoulder and boot plates
// in the full-body reference. Drawn over the panel in a lighter or darker shade; decorative only.
struct ArmorFacetShape: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let cut = min(cut, min(rect.width, rect.height) * 0.15)
        let inner = cut * 2.2
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

// The tapered hair slash beside section titles and selected items. Decorative only.
struct HairSlash: View {
    var height: CGFloat = 18

    var body: some View {
        HairSlashShape()
            .fill(Palette.hair)
            .frame(width: height * 2 / 3, height: height)
            .accessibilityHidden(true)
    }
}

// The spec's slash, M14 3 L19 3 L10 21 L7 21 Z, fitted to its own 12 × 18 bounds.
struct HairSlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 12, y: rect.minY + rect.height * y / 18)
        }
        var path = Path()
        path.move(to: point(7, 0))
        path.addLine(to: point(12, 0))
        path.addLine(to: point(3, 18))
        path.addLine(to: point(0, 18))
        path.closeSubpath()
        return path
    }
}

// The eight-sided housing for the large play button.
struct PlayHousing: Shape {
    func path(in rect: CGRect) -> Path {
        SVGShape(path: "M18 0 H54 L72 18 V54 L54 72 H18 L0 54 V18 Z", viewBox: 72).path(in: rect)
    }
}

// Seams that split the housing into layered plates, like the segmented mask in the
// face close-up: an inset rim joined to each outer corner. Abstract, never a literal mask.
struct PlayHousingSeams: Shape {
    func path(in rect: CGRect) -> Path {
        SVGShape(
            path: "M20 6 H52 L66 20 V52 L52 66 H20 L6 52 V20 Z "
                + "M18 0 L20 6 M54 0 L52 6 M72 18 L66 20 M72 54 L66 52 "
                + "M54 72 L52 66 M18 72 L20 66 M0 54 L6 52 M0 18 L6 20",
            viewBox: 72
        ).path(in: rect)
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

// The empty-state illustration: an armor panel with the hair slash, the loose arc of the
// narrow strand above the hair, and the hanging zigzag braid. Empty states only, never
// as a text underline.
struct EmptyStateMark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            ArmorFacetShape(cut: 12)
                .fill(Palette.borderSubtle)
                .frame(width: 80, height: 80)
                .offset(x: 30, y: 22)
            ArmorPanelShape(cut: 12)
                .stroke(Palette.borderControl, lineWidth: 2)
                .frame(width: 80, height: 80)
                .offset(x: 30, y: 22)
            HairSlash(height: 40)
                .offset(x: 101, y: 12)
            LooseArc()
                .stroke(Palette.hair, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 70, height: 20)
                .offset(x: 24, y: 0)
            ZigzagStrand()
                .fill(LinearGradient(colors: [Palette.hair, Palette.hair.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 70)
                .offset(x: 2, y: 36)
        }
        .frame(width: 135, height: 110, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// The zigzag braid from both references: a chain of filled diamond segments, each leaning
// the other way and smaller than the last, so the braid narrows toward the tip.
struct ZigzagStrand: Shape {
    var segments = 8

    func path(in rect: CGRect) -> Path {
        // Segment scale falls from 1 to 0.5; the heights together fill the rect.
        let scales = (0..<segments).map { 1 - 0.5 * CGFloat($0) / CGFloat(max(segments - 1, 1)) }
        let unit = rect.height / scales.reduce(0, +)
        var path = Path()
        var top = CGPoint(x: rect.midX, y: rect.minY)
        for (index, scale) in scales.enumerated() {
            let height = unit * scale
            let swing = rect.width * 0.1 * scale
            let bottom = CGPoint(x: rect.midX + (index.isMultiple(of: 2) ? swing : -swing), y: top.y + height)
            let middle = CGPoint(x: (top.x + bottom.x) / 2, y: top.y + height / 2)
            let halfWidth = rect.width * 0.4 * scale
            path.move(to: top)
            path.addLine(to: CGPoint(x: middle.x + halfWidth, y: middle.y))
            path.addLine(to: bottom)
            path.addLine(to: CGPoint(x: middle.x - halfWidth, y: middle.y))
            path.closeSubpath()
            top = bottom
        }
        return path
    }
}

// A single loose arc, rising left to right.
struct LooseArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35),
            control: CGPoint(x: rect.width * 0.35, y: rect.minY - rect.height * 0.6)
        )
        return path
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

// The red primary action: armor-cut fill with a facet, dark label, gentle press.
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
            .overlay {
                // Lighter bevel at the cut corner; the label's 20 pt padding keeps it clear.
                ArmorFacetShape(cut: 8)
                    .fill(Color.white.opacity(isEnabled ? 0.22 : 0.06))
                    .allowsHitTesting(false)
            }
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
