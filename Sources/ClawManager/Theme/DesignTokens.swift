import SwiftUI

enum DS {
    // MARK: - Colors
    enum Color {
        enum Surface {
            static let base      = SwiftUI.Color(hex: 0x0C0C0E)
            static let raised    = SwiftUI.Color(hex: 0x141416)
            static let overlay   = SwiftUI.Color(hex: 0x1C1C20)
            static let elevated  = SwiftUI.Color(hex: 0x242428)
            static let floating  = SwiftUI.Color(hex: 0x2C2C32)
        }

        enum Text {
            static let primary    = SwiftUI.Color(hex: 0xF0F0F3)
            static let secondary  = SwiftUI.Color(hex: 0xA0A0AB)
            static let tertiary   = SwiftUI.Color(hex: 0x6B6B76)
            static let quaternary = SwiftUI.Color(hex: 0x45454D)
        }

        enum Accent {
            static let primary      = SwiftUI.Color(hex: 0xD4A853)
            static let primaryHover = SwiftUI.Color(hex: 0xE0B860)
            static let primaryMuted = SwiftUI.Color(hex: 0xD4A853).opacity(0.15)
            static let secondary      = SwiftUI.Color(hex: 0x8B7EC8)
            static let secondaryMuted = SwiftUI.Color(hex: 0x8B7EC8).opacity(0.12)
        }

        enum Status {
            static let activeDot    = SwiftUI.Color(hex: 0x4ADE80)
            static let activeBg     = SwiftUI.Color(hex: 0x4ADE80).opacity(0.12)
            static let activeText   = SwiftUI.Color(hex: 0x6EE7A0)

            static let waitingDot   = SwiftUI.Color(hex: 0xFACC15)
            static let waitingBg    = SwiftUI.Color(hex: 0xFACC15).opacity(0.12)
            static let waitingText  = SwiftUI.Color(hex: 0xFDE047)

            static let idleDot      = SwiftUI.Color(hex: 0x818CF8)
            static let idleBg       = SwiftUI.Color(hex: 0x818CF8).opacity(0.10)
            static let idleText     = SwiftUI.Color(hex: 0xA5B4FC)

            static let staleDot     = SwiftUI.Color(hex: 0x6B7280)
            static let staleBg      = SwiftUI.Color(hex: 0x6B7280).opacity(0.08)
            static let staleText    = SwiftUI.Color(hex: 0x9CA3AF)

            static let errorDot     = SwiftUI.Color(hex: 0xF87171)
            static let errorBg      = SwiftUI.Color(hex: 0xF87171).opacity(0.12)
            static let errorText    = SwiftUI.Color(hex: 0xFCA5A5)
        }

        enum Border {
            static let subtle  = SwiftUI.Color.white.opacity(0.04)
            static let `default` = SwiftUI.Color.white.opacity(0.08)
            static let strong  = SwiftUI.Color.white.opacity(0.14)
            static let accent  = SwiftUI.Color(hex: 0xD4A853).opacity(0.40)
        }
    }

    // MARK: - Typography
    enum Typography {
        static let mega       = Font.system(size: 28, weight: .semibold)
        static let title      = Font.system(size: 20, weight: .semibold)
        static let heading    = Font.system(size: 16, weight: .semibold)
        static let subheading = Font.system(size: 14, weight: .medium)
        static let body       = Font.system(size: 13, weight: .regular)
        static let caption    = Font.system(size: 12, weight: .regular)
        static let captionMono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let small      = Font.system(size: 11, weight: .medium)
        static let micro      = Font.system(size: 10, weight: .medium)
        static let microMono  = Font.system(size: 10, weight: .medium, design: .monospaced)

        // Markdown-specific
        static let mdH1       = Font.system(size: 20, weight: .bold)
        static let mdH2       = Font.system(size: 17, weight: .bold)
        static let mdH3       = Font.system(size: 15, weight: .semibold)
        static let mdH4       = Font.system(size: 13, weight: .semibold)
        static let mdCode     = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let mdCodeBlock = Font.system(size: 11.5, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing (4pt base)
    enum Space {
        static let xxs: CGFloat  = 2
        static let xs: CGFloat   = 4
        static let sm: CGFloat   = 8
        static let md: CGFloat   = 12
        static let lg: CGFloat   = 16
        static let xl: CGFloat   = 20
        static let xxl: CGFloat  = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Border Radius
    enum Radius {
        static let xs: CGFloat  = 2
        static let sm: CGFloat  = 4
        static let md: CGFloat  = 6
        static let lg: CGFloat  = 8
        static let xl: CGFloat  = 10
        static let xxl: CGFloat = 12
    }

    // MARK: - Animation
    enum Motion {
        static let instant  = Animation.easeOut(duration: 0.08)
        static let fast     = Animation.easeOut(duration: 0.12)
        static let normal   = Animation.easeOut(duration: 0.20)
        static let slow     = Animation.easeOut(duration: 0.35)

        static let springInteractive = Animation.spring(duration: 0.2, bounce: 0.0)
        static let springSmooth      = Animation.spring(duration: 0.35, bounce: 0.1)
        static let springBouncy      = Animation.spring(duration: 0.4, bounce: 0.2)
    }
}
