import SwiftUI

struct MediaErrorView: View {
    let post: Post

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(post.title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 600)

            Text("Media could not be loaded")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 80)
    }
}
