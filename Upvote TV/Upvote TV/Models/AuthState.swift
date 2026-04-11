import Foundation
import SwiftData

@Model
final class AuthState {
    var refreshToken: String
    var accessToken: String?
    var accessTokenExpiresAt: Date?
    var lastRefreshAt: Date?

    init(refreshToken: String, accessToken: String? = nil, accessTokenExpiresAt: Date? = nil, lastRefreshAt: Date? = nil) {
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.lastRefreshAt = lastRefreshAt
    }

    var isAccessTokenValid: Bool {
        guard let token = accessToken, !token.isEmpty,
              let expiresAt = accessTokenExpiresAt else {
            return false
        }
        return expiresAt > Date()
    }
}
