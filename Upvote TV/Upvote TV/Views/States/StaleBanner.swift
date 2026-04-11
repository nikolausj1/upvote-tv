import SwiftUI

struct StaleBanner: View {
    let cachedDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)

            if let cachedDate {
                Text("Showing cached content. Last updated \(cachedDate.relativeDescription).")
            } else {
                Text("Showing cached content. Refresh failed.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
