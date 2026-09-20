import Foundation

enum AppConfig {
    static var revenueCatAPIKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String, !key.isEmpty else {
            fatalError("RevenueCatAPIKey not found in Info.plist")
        }
        return key
    }

    static var dailyPromptAPIURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "DailyPromptAPIURL") as? String, !url.isEmpty else {
            fatalError("DailyPromptAPIURL not found in Info.plist")
        }
        return url
    }
}
