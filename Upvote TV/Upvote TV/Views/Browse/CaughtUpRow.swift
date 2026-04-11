import SwiftUI

struct CaughtUpCardRow: View {
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.green)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("You're Caught Up")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("No new upvoted posts to watch together right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
