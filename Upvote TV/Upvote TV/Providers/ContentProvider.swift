import Foundation

enum ContentProviderError: Error, LocalizedError {
    case authenticationRequired
    case authenticationExpired
    case networkError(underlying: Error)
    case rateLimited
    case invalidResponse
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication is required. Please configure your Reddit credentials."
        case .authenticationExpired:
            return "Authentication has expired. You'll need to generate a new refresh token."
        case .networkError:
            return "A network error occurred. Please check your connection."
        case .rateLimited:
            return "Too many requests. Please try again in a moment."
        case .invalidResponse:
            return "Received an unexpected response."
        case .unknown:
            return "An unexpected error occurred."
        }
    }
}

protocol ContentProvider {
    func fetchUpvotedPosts() async throws -> [Post]
}
