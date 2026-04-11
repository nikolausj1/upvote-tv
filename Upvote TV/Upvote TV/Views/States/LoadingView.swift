import SwiftUI

struct BrowseSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<10, id: \.self) { _ in
                    SkeletonCardRow()
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
    }
}

private struct SkeletonCardRow: View {
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 20) {
            // Type icon placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .frame(width: 40, height: 40)

            // Title + metadata
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.03))
                    .frame(height: 20)
                    .frame(width: 320)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.02))
                    .frame(height: 14)
                    .frame(width: 200)
            }

            Spacer()

            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .frame(width: 96, height: 64)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                )
        )
        .opacity(shimmer ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}
