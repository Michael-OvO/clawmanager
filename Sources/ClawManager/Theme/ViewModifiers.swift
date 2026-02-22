import SwiftUI

// MARK: - Glass Card

struct GlassCard: ViewModifier {
    var isSelected: Bool = false
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .fill(isSelected || isHovered ? DS.Color.Surface.elevated : DS.Color.Surface.overlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl)
                    .stroke(
                        isSelected ? DS.Color.Border.accent :
                            (isHovered ? DS.Color.Border.default : DS.Color.Border.subtle),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .if(isSelected) { view in
                view.overlay(
                    LinearGradient(
                        colors: [DS.Color.Accent.primary.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: UnitPoint(x: 0.15, y: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
                )
            }
            .shadow(
                color: isSelected ? DS.Color.Accent.primary.opacity(0.08) :
                    (isHovered ? .black.opacity(0.3) : .clear),
                radius: isSelected ? 12 : (isHovered ? 8 : 0),
                y: isHovered ? 2 : 0
            )
    }
}

extension View {
    func glassCard(isSelected: Bool = false, isHovered: Bool = false) -> some View {
        modifier(GlassCard(isSelected: isSelected, isHovered: isHovered))
    }
}

// MARK: - Status Bar Breathing Glow

struct BreathingGlow: ViewModifier {
    let color: Color
    let isActive: Bool
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(isBreathing ? 0.6 : 0.15) : .clear,
                radius: isActive ? (isBreathing ? 8 : 3) : 0
            )
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        isBreathing = true
                    }
                } else {
                    isBreathing = false
                }
            }
    }
}

// MARK: - Pulse Opacity (for waiting status)

struct PulseOpacity: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? (isPulsing ? 0.4 : 1.0) : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    isPulsing = false
                }
            }
    }
}

// MARK: - Hover Tracking

struct HoverTracker: ViewModifier {
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(DS.Motion.fast) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func breathingGlow(color: Color, isActive: Bool) -> some View {
        modifier(BreathingGlow(color: color, isActive: isActive))
    }

    func pulseOpacity(isActive: Bool) -> some View {
        modifier(PulseOpacity(isActive: isActive))
    }

    func trackHover(_ isHovered: Binding<Bool>) -> some View {
        modifier(HoverTracker(isHovered: isHovered))
    }
}
