import Foundation

final class PromptService {
    static let shared = PromptService()
    private init() {}

    func fetchPrompt() async throws -> String {
        guard let url = URL(string: AppConfig.dailyPromptAPIURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(PromptResponse.self, from: data)

        return decoded.prompt
    }
}

struct PromptResponse: Codable {
    let success: Bool
    let prompt: String
}


