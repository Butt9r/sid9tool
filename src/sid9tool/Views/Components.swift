import SwiftUI

// MARK: - Shared Liquid Glass UI Components

/// Liquid Glass card container (LiveContainer-clean style).
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            }
    }
}

/// Small status chip (e.g. JIT, VPN, Slot) used on Home cards.
struct StatusChip: View {
    let title: String
    var isPositive: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isPositive ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.ultraThinMaterial))
    }
}

/// Primary action button with glass styling.
struct GlassButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.tint.opacity(0.85))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// App icon placeholder (generated image or SF Symbol fallback).
struct AppIconView: View {
    let name: String
    var url: URL? = nil
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    iconPlaceholder
                }
            } else {
                iconPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.quaternary)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Section header used across tabs.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
        }
    }
}
