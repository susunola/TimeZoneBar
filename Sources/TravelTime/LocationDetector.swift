import Foundation

/// Response model shared by both geolocation providers.
///
/// The two providers disagree on shape:
/// - ipwho.is returns a *nested* `timezone` object: `{"timezone":{"id":"Asia/Bangkok"},...}`
/// - ipapi.co returns a *flat* `timezone` string and names the country `country_name`
/// - both report throttling as HTTP 200 with `{"error":true,"reason":"..."}`
struct GeoResult: Decodable {
    let timezone: String?
    let city: String?
    let country_name: String?
    let country: String?
    let error: Bool?
    let reason: String?

    /// ipwho.is error shape: {"code": 429, "message": "Too Many Requests"}.
    private struct ErrorDetail: Decodable {
        let code: Int?
        let message: String?
    }

    enum CodingKeys: String, CodingKey {
        case timezone, city, country_name, country, error, reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        country_name = try c.decodeIfPresent(String.self, forKey: .country_name)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        var reasonValue = try c.decodeIfPresent(String.self, forKey: .reason)
        // `error` is a bare bool on ipapi.co but an object on ipwho.is —
        // accept both.
        if let flag = try? c.decode(Bool.self, forKey: .error) {
            error = flag
        } else if let detail = try? c.decode(ErrorDetail.self, forKey: .error) {
            error = true
            if reasonValue == nil { reasonValue = detail.message }
        } else {
            error = nil
        }
        reason = reasonValue
        if let flat = try? c.decodeIfPresent(String.self, forKey: .timezone) {
            timezone = flat
        } else if let nested = try? c.decodeIfPresent([String: String].self, forKey: .timezone) {
            // ipwho.is shape: {"id": "Asia/Bangkok", "abbreviation": "ICT", ...}
            timezone = nested["id"]
        } else {
            timezone = nil
        }
    }
}

enum DetectionError: LocalizedError {
    case failed
    case networkUnavailable
    case noTimezoneReturned
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Could not determine your time zone (check your network connection)"
        case .networkUnavailable:
            return "Network unavailable — please check your internet connection"
        case .noTimezoneReturned:
            return "Server response did not contain a valid time zone"
        case .rateLimited(let reason):
            let detail = reason.isEmpty ? "" : " (\(reason))"
            return "Location service is temporarily rate-limited\(detail) — try again in a minute"
        }
    }
}

enum LocationDetector {
    /// ipwho.is first: free, HTTPS-only, no API key. ipapi.co is the fallback.
    ///
    /// ip-api.com is deliberately absent: its free tier has no HTTPS at all
    /// ("256-bit SSL encryption is not available for this free API"), and
    /// ATS blocks plain HTTP, so it would fail on every call.
    /// A response from either provider feeds a privileged timezone switch, so
    /// an unencrypted endpoint is a real injection surface — keep both HTTPS.
    static let endpoints: [URL] = [
        URL(string: "https://ipwho.is/")!,
        URL(string: "https://ipapi.co/json/")!
    ]

    /// `session` is injectable so network behaviour (success, throttling,
    /// malformed JSON, total failure) can be unit-tested with a URLProtocol
    /// stub instead of hitting the real providers.
    static func detect(session: URLSession = .shared) async throws -> DetectedZone {
        var lastError: Error?
        for url in endpoints {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await session.data(for: request)

                // Check HTTP status. 429/403 from these providers mean
                // throttling/blocking, not "no network" — surface them as
                // rateLimited so the message doesn't mislead the user.
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    switch httpResponse.statusCode {
                    case 429, 403:
                        lastError = DetectionError.rateLimited("HTTP \(httpResponse.statusCode)")
                    default:
                        lastError = DetectionError.networkUnavailable
                    }
                    continue
                }

                let geo = try JSONDecoder().decode(GeoResult.self, from: data)
                // Providers report throttling as HTTP 200 + {"error": true},
                // so a status check alone is not enough.
                if geo.error == true {
                    lastError = DetectionError.rateLimited(geo.reason ?? "")
                    continue
                }
                guard let timezone = geo.timezone, !timezone.isEmpty else {
                    lastError = DetectionError.noTimezoneReturned
                    continue
                }
                return DetectedZone(timezone: timezone,
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
