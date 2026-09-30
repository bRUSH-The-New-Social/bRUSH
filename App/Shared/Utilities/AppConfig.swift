import Foundation

enum AppConfig {
    static var dailyPromptAPIURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "DailyPromptAPIURL") as? String, !url.isEmpty else {
            fatalError("DailyPromptAPIURL not found in Info.plist")
        }
        return url
    }
}
