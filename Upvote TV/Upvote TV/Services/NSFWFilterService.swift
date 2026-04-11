import Foundation

enum NSFWFilterService {
    private static let key = "nsfw_enabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [key: true])
    }

    static var isNSFWEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func filter(_ posts: [Post]) -> [Post] {
        if isNSFWEnabled { return posts }
        return posts.filter { !$0.isNSFW }
    }
}
