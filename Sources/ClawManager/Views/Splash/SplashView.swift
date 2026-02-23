import SwiftUI

struct SplashView: View {
    let onComplete: () -> Void

    // Claw drawing
    @State private var clawProgress1: CGFloat = 0
    @State private var clawProgress2: CGFloat = 0
    @State private var clawProgress3: CGFloat = 0

    // Glow layers
    @State private var innerGlow: CGFloat = 0
    @State private var outerGlow: CGFloat = 0
    @State private var ambientOpacity: Double = 0
    @State private var ambientScale: CGFloat = 0.6

    // Ring burst
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0

    // Ambient breathing (post-flash)
    @State private var isBreathing = false

    // Text
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 10
    @State private var subtitleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = 10

    var body: some View {
        ZStack {
            DS.Color.Surface.base
                .ignoresSafeArea()

            VStack(spacing: DS.Space.xxl) {
                // Claw marks with glow
                ZStack {
                    // Ring burst
                    Circle()
                        .stroke(
                            DS.Color.Accent.primary.opacity(ringOpacity),
                            lineWidth: 1.5
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)

                    // Outer bloom shadow (large, soft)
                    clawMarksGroup
                        .shadow(color: DS.Color.Accent.primary.opacity(0.3), radius: outerGlow)

                    // Inner crisp glow
                    clawMarksGroup
                        .shadow(color: DS.Color.Accent.primary.opacity(0.6), radius: innerGlow)

                    // Actual claw marks on top
                    clawMarksGroup
                }
                .frame(width: 100, height: 100)
                .background {
                    // Ambient glow layers — rendered as background so they
                    // share the icon's center without affecting ZStack layout.
                    ZStack {
                        RadialGradient(
                            colors: [
                                DS.Color.Accent.primary.opacity(0.12 * ambientOpacity),
                                DS.Color.Accent.primary.opacity(0.04 * ambientOpacity),
                                .clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 280
                        )
                        .frame(width: 560, height: 560)
                        .scaleEffect(ambientScale)
                        .opacity(isBreathing ? 0.7 : 1.0)

                        RadialGradient(
                            colors: [
                                DS.Color.Accent.secondary.opacity(0.06 * ambientOpacity),
                                .clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 200
                        )
                        .frame(width: 400, height: 400)
                        .scaleEffect(ambientScale * 1.1)
                    }
                }
                .shadow(
                    color: DS.Color.Accent.primary.opacity(isBreathing ? 0.15 : 0.25),
                    radius: isBreathing ? 20 : 12
                )

                // Title + subtitle
                VStack(spacing: DS.Space.sm) {
                    Text("ClawManager")
                        .font(DS.Typography.mega)
                        .foregroundStyle(DS.Color.Text.primary)
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)
                        .shadow(
                            color: DS.Color.Accent.primary.opacity(0.3 * titleOpacity),
                            radius: 12
                        )

                    Text("Claude Code Monitor")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.Text.tertiary)
                        .opacity(subtitleOpacity)
                        .offset(y: subtitleOffset)
                }
            }
            // Tell the ZStack to vertically center on the claw marks (top
            // 100pt of the VStack) instead of the whole VStack, so the icon
            // sits at true screen-center and the title hangs below it.
            .alignmentGuide(VerticalAlignment.center) { d in
                // 50pt = center of the 100pt claw-marks frame at the top
                50
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    // MARK: - Claw Marks Group

    private var clawMarksGroup: some View {
        ZStack {
            clawMark(offset: -20, progress: clawProgress1)
            clawMark(offset: 0, progress: clawProgress2)
            clawMark(offset: 20, progress: clawProgress3)
        }
    }

    /// Center of the claw pattern, offset to account for the 15pt leftward slant.
    /// Geometric center of the bounding box is at x=52, shifted 2pt right of frame
    /// center to compensate for the perceptual leftward bias of "///" diagonals.
    private static let clawCenterX: CGFloat = 59.5

    private func clawMark(offset: CGFloat, progress: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: Self.clawCenterX + offset, y: 10))
            path.addLine(to: CGPoint(x: Self.clawCenterX + offset - 15, y: 90))
        }
        .trim(from: 0, to: progress)
        .stroke(
            DS.Color.Accent.primary,
            style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )
    }

    // MARK: - Animation Sequence

    private func startAnimation() {
        // Phase 1: Staggered claw marks draw in
        withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
            clawProgress1 = 1
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
            clawProgress2 = 1
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
            clawProgress3 = 1
        }

        // Phase 2: Glow flash — inner glow snaps on
        withAnimation(.spring(duration: 0.25, bounce: 0.15).delay(0.5)) {
            innerGlow = 10
        }
        // Outer bloom follows slightly behind
        withAnimation(.spring(duration: 0.35, bounce: 0.1).delay(0.55)) {
            outerGlow = 24
        }

        // Phase 2b: Ambient radial gradient expands
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            ambientOpacity = 1
            ambientScale = 1.0
        }

        // Phase 2c: Ring burst
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) {
            ringScale = 2.0
            ringOpacity = 0.5
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.85)) {
            ringOpacity = 0
        }

        // Phase 3: Glow settles to resting state
        withAnimation(.easeOut(duration: 0.35).delay(0.85)) {
            innerGlow = 3
            outerGlow = 8
        }

        // Phase 4: Title fades in
        withAnimation(.easeOut(duration: 0.35).delay(0.75)) {
            titleOpacity = 1
            titleOffset = 0
        }

        // Phase 5: Subtitle fades in
        withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
            subtitleOpacity = 1
            subtitleOffset = 0
        }

        // Phase 6: Start ambient breathing loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }

        // Transition out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            onComplete()
        }
    }
}
