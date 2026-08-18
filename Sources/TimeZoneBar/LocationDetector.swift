import Foundation

struct GeoResult: Decodable {
    let timezone: String
    let city: String?
    let country_name: String?
    let country: String?
}

enum DetectionError: LocalizedError {
    case failed
    case networkUnavailable
    case noTimezoneReturned

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Could not determine your time zone (check your network connection)"
        case .networkUnavailable:
            return "Network unavailable — please check your internet connection"
        case .noTimezoneReturned:
            return "Server response did not contain a valid time zone"
        }
    }
}

enum LocationDetector {
    /// Both endpoints use HTTPS (the previous plain-HTTP ip-api.com call
    /// required an ATS exception and let a same-network attacker spoof the
    /// response — that response feeds a privileged timezone switch, so it is
    /// a real injection surface). ip-api.com first, ipapi.co as fallback.
    static let endpoints: [URL] = [
        URL(string: "https://ip-api.com/json/")!,
        URL(string: "https://ipapi.co/json/")!
    ]

    static func detect() async throws -> DetectedZone {
        var lastError: Error?
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    lastError = DetectionError.networkUnavailable
                    continue
                }
                
                let geo = try JSONDecoder().decode(GeoResult.self, from: data)
                guard !geo.timezone.isEmpty else {
                    lastError = DetectionError.noTimezoneReturned
                    continue
                }
                return DetectedZone(timezone: geo.timezone,
                                    city: geo.city ?? "",
                                    country: geo.country_name ?? geo.country ?? "")
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? DetectionError.failed
    }
}
