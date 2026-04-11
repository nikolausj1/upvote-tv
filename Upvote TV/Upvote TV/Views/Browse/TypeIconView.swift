import SwiftUI

struct TypeIconView: View {
    let postType: PostType
    var dimmed: Bool = false

    var body: some View {
        Image(systemName: postType.systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(postType.iconColor.opacity(dimmed ? 0.4 : 1.0))
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(postType.iconColor.opacity(dimmed ? 0.05 : 0.1))
            )
    }
}
