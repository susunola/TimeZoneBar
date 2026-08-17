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
        "Could not determine your time zone (check your network connection)"
    }
}

enum LocationDetector {
    /// ip-api.com is free and reliable in practice (http, ATS exception added); ipapi.co is the fallback
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
