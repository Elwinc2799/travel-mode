import SwiftUI

/// One tile's state at a moment of a flip: the old letter, the new one, and how far the flap has fallen.
public struct TileFrame: Equatable, Sendable {
    public var from: Character
    public var to: Character
    public var progress: Double

    public init(from: Character, to: Character, progress: Double) {
        self.from = from
        self.to = to
        self.progress = progress
    }

    public static func resting(_ c: Character) -> TileFrame { TileFrame(from: c, to: c, progress: 1) }
}

/// Timing of the departure-board flip, shared by the live animation and the preview renderer.
public enum SplitFlapTiming {
    /// One flap falling, in seconds.
    public static let flip = 0.09
    /// Delay between neighbouring tiles starting, in seconds.
    public static let stagger = 0.035

    private static let alphabet = Array("ABCDEFGHIJKLMNOPRSTUVWabcdeghiklmnorstuvw")

    /// The letters a tile passes through: two in-between letters, then the target. Like a real
    /// board, it never jumps straight to the answer.
    public static func steps(forTile index: Int, to target: Character) -> [Character] {
        let first = alphabet[(index * 7 + 3) % alphabet.count]
        let second = alphabet[(index * 11 + 5) % alphabet.count]
        return [first, second, target]
    }

    /// How long a full board change takes.
    public static var duration: Double { stagger * Double(SplitFlapBoard.tileCount - 1) + flip * 3 }

    /// Every tile's state `time` seconds after a change from `old` to `new` started.
    public static func frames(from old: String, to new: String, at time: Double) -> [TileFrame] {
        let oldChars = SplitFlapBoard.pad(old)
        let newChars = SplitFlapBoard.pad(new)
        return (0..<SplitFlapBoard.tileCount).map { i in
            if oldChars[i] == newChars[i] { return .resting(newChars[i]) }
            let local = time - stagger * Double(i)
            if local <= 0 { return .resting(oldChars[i]) }
            let steps = steps(forTile: i, to: newChars[i])
            let step = Int(local / flip)
            if step >= steps.count { return .resting(newChars[i]) }
            let previous = step == 0 ? oldChars[i] : steps[step - 1]
            return TileFrame(from: previous, to: steps[step], progress: (local - Double(step) * flip) / flip)
        }
    }
}

/// The departure board: ten flap tiles in a slate housing.
public struct SplitFlapBoard: View {
    /// Enough tiles for the longest mode name, and at least ten, so no title is ever cut off.
    public static let tileCount = max(10, Mode.allCases.map(\.title.count).max() ?? 0)

    let text: String
    let frames: [TileFrame]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shows `text`, flipping to it whenever it changes. Pass `frames` to draw one fixed moment instead.
    public init(text: String, frames: [TileFrame]? = nil) {
        self.text = text
        self.frames = frames
    }

    static func pad(_ text: String) -> [Character] {
        let chars = Array(text.prefix(tileCount))
        return chars + Array(repeating: " ", count: tileCount - chars.count)
    }

    public var body: some View {
        let chars = Self.pad(text)
        HStack(spacing: 3) {
            ForEach(0..<Self.tileCount, id: \.self) { i in
                if let frames {
                    FlapFace(from: frames[i].from, to: frames[i].to, progress: frames[i].progress)
                } else {
                    FlapTile(target: chars[i], index: i, reduceMotion: reduceMotion)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.nightSlate)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current mode: \(text)")
        .onChange(of: text) { old, new in
            if frames == nil { Sounds.playFlip(from: old, to: new, reduceMotion: reduceMotion) }
        }
    }
}

/// A live tile: when its letter changes, it flips through the in-between letters to the new one.
struct FlapTile: View {
    let target: Character
    let index: Int
    let reduceMotion: Bool

    @State private var from: Character
    @State private var to: Character
    @State private var progress: Double = 1

    init(target: Character, index: Int, reduceMotion: Bool) {
        self.target = target
        self.index = index
        self.reduceMotion = reduceMotion
        _from = State(initialValue: target)
        _to = State(initialValue: target)
    }

    var body: some View {
        FlapFace(from: from, to: to, progress: progress)
            .task(id: target) { await flip(to: target) }
    }

    @MainActor
    private func flip(to target: Character) async {
        guard target != to else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                from = target
                to = target
                progress = 1
            }
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(SplitFlapTiming.stagger * Double(index) * 1_000_000_000))
        for letter in SplitFlapTiming.steps(forTile: index, to: target) {
            if Task.isCancelled { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                from = to
                to = letter
                progress = 0
            }
            withAnimation(.linear(duration: SplitFlapTiming.flip)) { progress = 1 }
            try? await Task.sleep(nanoseconds: UInt64(SplitFlapTiming.flip * 1_000_000_000))
        }
    }
}

/// Draws one tile at a given moment of a flip. The top half of the old letter falls forward
/// around the hinge, revealing the new letter's top; then the new letter's bottom half lands.
struct FlapFace: View, Animatable {
    var from: Character
    var to: Character
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private let size = Theme.tileSize

    var body: some View {
        let half = size.height / 2
        ZStack {
            VStack(spacing: 0) {
                FlapHalf(letter: to, edge: .top)
                FlapHalf(letter: from, edge: .bottom)
            }
            VStack(spacing: 0) {
                if progress < 0.5 {
                    let turn = progress * 2 // 0 → 1 while the old top falls
                    FlapHalf(letter: from, edge: .top)
                        .overlay(Color.black.opacity(0.45 * turn))
                        .rotation3DEffect(.degrees(-90 * turn), axis: (x: 1, y: 0, z: 0),
                                          anchor: .bottom, perspective: 0.55)
                } else {
                    Color.clear.frame(height: half)
                }
                if progress >= 0.5 && progress < 1 {
                    let turn = (progress - 0.5) * 2 // 0 → 1 while the new bottom lands
                    FlapHalf(letter: to, edge: .bottom)
                        .overlay(Color.black.opacity(0.35 * (1 - turn)))
                        .rotation3DEffect(.degrees(90 * (1 - turn)), axis: (x: 1, y: 0, z: 0),
                                          anchor: .top, perspective: 0.55)
                } else if progress >= 1 {
                    FlapHalf(letter: to, edge: .bottom)
                } else {
                    Color.clear.frame(height: half)
                }
            }
            Rectangle()
                .fill(Theme.hinge)
                .frame(height: 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The top or bottom half of a tile with its letter.
struct FlapHalf: View {
    enum Edge { case top, bottom }

    let letter: Character
    let edge: Edge
    private let size = Theme.tileSize

    var body: some View {
        let radius: CGFloat = 3
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .top ? radius : 0,
            bottomLeadingRadius: edge == .bottom ? radius : 0,
            bottomTrailingRadius: edge == .bottom ? radius : 0,
            topTrailingRadius: edge == .top ? radius : 0,
            style: .continuous)
        Text(String(letter))
            .font(.system(size: size.height * 0.68, weight: .heavy).width(.condensed))
            .foregroundStyle(Theme.paper)
            .frame(width: size.width, height: size.height)
            .frame(height: size.height / 2, alignment: edge == .top ? .top : .bottom)
            .clipped()
            .background(
                shape.fill(LinearGradient(
                    colors: edge == .top ? [Theme.flapLight, Theme.flap] : [Theme.flap, Theme.flap],
                    startPoint: .top, endPoint: .bottom))
            )
            .clipShape(shape)
    }
}
