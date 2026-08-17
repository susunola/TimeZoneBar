import Foundation

struct GeoResult: Decodable {
    let timezone: String
    let city: String?
    let country_name: String?
    let country: String?
}

enum DetectionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "未能确定当前位置时区（请检查网络连接）"
    }
}

enum LocationDetector {
    /// ip-api.com 免费且实测稳定（http，已加 ATS 例外）；ipapi.co 免费档易限流，作备用
    static let endpoints: [URL] = [
        URL(string: "http://ip-api.com/json/")!,
        URL(string: "https://ipapi.co/json/")!
    ]

    static func detect() async throws -> DetectedZone {
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, _) = try await URLSession.shared.data(for: request)
                let geo = try JSONDecoder().decode(GeoResult.self, from: data)
                guard !geo.timezone.isEmpty else { continue }
                return DetectedZone(timezone: geo.timezone,
                                    city: geo.city ?? "",
                                    country: geo.country_name ?? geo.country ?? "")
            } catch {
                continue
            }
        }
        throw DetectionError.failed
    }
}
