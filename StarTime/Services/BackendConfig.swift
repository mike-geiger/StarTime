import Foundation

/// Reads the Cognito Pool/Client IDs baked into Info.plist at build time (see
/// StarTime/Config/StarTime.xcconfig), with a ProcessInfo.environment override
/// so a value can be swapped at launch without rebuilding (e.g. from an Xcode
/// scheme's environment variables).
enum BackendConfig {
    static var userPoolId: String { value(infoPlistKey: "STARTimeUserPoolId", envKey: "STARTIME_USER_POOL_ID") }
    static var userPoolClientId: String { value(infoPlistKey: "STARTimeUserPoolClientId", envKey: "STARTIME_USER_POOL_CLIENT_ID") }
    static var awsRegion: String { value(infoPlistKey: "STARTimeAWSRegion", envKey: "STARTIME_AWS_REGION") }
    static var apiBaseUrl: String { value(infoPlistKey: "STARTimeApiBaseUrl", envKey: "STARTIME_API_BASE_URL") }
    static var webSocketUrl: String { value(infoPlistKey: "STARTimeWebSocketUrl", envKey: "STARTIME_WEBSOCKET_URL") }

    private static func value(infoPlistKey: String, envKey: String) -> String {
        if let override = ProcessInfo.processInfo.environment[envKey], !override.isEmpty {
            return override
        }
        return (Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String) ?? ""
    }
}
