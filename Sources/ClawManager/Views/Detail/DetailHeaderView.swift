import SwiftUI

struct DetailHeaderView: View {
    let summary: SessionSummary
    @Environment(SessionStore.self) private var store

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Status bar
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(statusBarColor)
                .frame(width: 4, height: 28)
                .breathingGlow(color: statusBarColor, isActive: isActiveStatus)

            // Session info
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Title row
                HStack {
                    Text(summary.projectName)
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Color.Text.primary)
                        .lineLimit(1)

                    Spacer()

                    // Connection controls
                    connectionControls

                    // Permission mode badge
                    if let mode = summary.permissionMode, mode != .default {
                        PermissionModeBadge(mode: mode)
                    }

                    // Copy session ID button
                    ActionButton(icon: "doc.on.doc", tooltip: "Copy Session ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(summary.sessionId, forType: .string)
                    }
                }

                // Metadata row
                HStack(spacing: 0) {
                    metadataItem(text: summary.workspacePath, isMono: true)

                    if let model = summary.model {
                        separator
                        metadataItem(text: shortModel(model))
                    }

                    if let version = summary.cliVersion {
                        separator
                        metadataItem(text: "v\(version)")
                    }

                    if let branch = summary.gitBranch {
                        separator
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(branch)
                                .font(DS.Typography.captionMono)
                        }
                        .foregroundStyle(DS.Color.Text.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
    }

    // MARK: - Connection State Helpers

    private var isConnectedToThis: Bool {
        if case .connected(let id) = store.connectionState {
            return id == summary.sessionId
        }
        return false
    }

    private var isConnecting: Bool {
        store.connectionState == .connecting
    }

    private var statusBarColor: Color {
        if isConnectedToThis { return DS.Color.Status.activeDot }
        return summary.status.dotColor
    }

    private var isActiveStatus: Bool {
        isConnectedToThis || summary.status == .active
    }

    /// Whether another process (e.g. VS Code) currently owns this session.
    private var isOwnedByOther: Bool {
        summary.pid != nil && summary.status != .stale
    }

    // MARK: - Connection Controls

    @ViewBuilder
    private var connectionControls: some View {
        if isConnectedToThis {
            // Disconnect button
            ConnectionButton(
                label: "Disconnect",
                icon: "bolt.slash.fill",
                color: DS.Color.Status.errorDot
            ) {
                store.disconnectInteractive()
            }
        } else if isConnecting {
            // Connecting spinner
            HStack(spacing: DS.Space.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(DS.Typography.small)
                    .foregroundStyle(DS.Color.Text.tertiary)
            }
            .padding(.horizontal, DS.Space.sm)
        } else if isOwnedByOther {
            // Take Over button (session owned by VS Code / another process)
            ConnectionButton(
                label: "Take Over",
                icon: "arrow.triangle.swap",
                color: DS.Color.Status.waitingDot
            ) {
                Task {
                    await store.takeOverSession(sessionId: summary.sessionId)
                }
            }
        } else if summary.status == .stale || summary.status == .idle {
            // Connect button (session is available)
            ConnectionButton(
                label: "Connect",
                icon: "bolt.fill",
                color: DS.Color.Status.activeDot
            ) {
                Task {
                    await store.connectInteractive(sessionId: summary.sessionId)
                }
            }
        }
    }

    private var separator: some View {
        Text("  |  ")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.Text.quaternary)
    }

    private func metadataItem(text: String, isMono: Bool = false) -> some View {
        Text(text)
            .font(isMono ? DS.Typography.captionMono : DS.Typography.caption)
            .foregroundStyle(DS.Color.Text.secondary)
            .lineLimit(1)
    }

    private func shortModel(_ model: String) -> String {
        if model.contains("opus") { return "Opus 4" }
        if model.contains("sonnet") { return "Sonnet 4" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }
}

// MARK: - Permission Mode Badge

private struct PermissionModeBadge: View {
    let mode: PermissionMode

    private var badgeColor: Color {
        switch mode {
        case .plan: DS.Color.Accent.primary
        case .acceptEdits: DS.Color.Status.activeDot
        case .bypassPermissions: DS.Color.Status.errorDot
        case .dontAsk: DS.Color.Status.waitingDot
        case .default: DS.Color.Text.tertiary
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: mode.icon)
                .font(.system(size: 9))
            Text(mode.displayName)
                .font(DS.Typography.micro)
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(badgeColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(badgeColor.opacity(0.2), lineWidth: 1)
        )
        .help("Permission mode: \(mode.displayName)")
    }
}

// MARK: - Connection Button

private struct ConnectionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(DS.Typography.small)
            }
            .foregroundStyle(isHovered ? .white : color)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isHovered ? color.opacity(0.8) : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? DS.Color.Text.secondary : DS.Color.Text.tertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(isHovered ? DS.Color.Surface.elevated : .clear)
                )
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(tooltip)
    }
}
