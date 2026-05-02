import Foundation

// MARK: - Status

struct NullHubStatusResponse: Decodable {
    let hub: NullHubInfo
    let components: [String: NullHubComponentRollup]
    let instances: [String: [String: NullHubInstanceSummary]]
    let overallStatus: String
}

struct NullHubInfo: Decodable {
    let version: String
    let platform: String
    let pid: Int
    let uptimeSeconds: Int
    let access: NullHubAccessInfo
}

struct NullHubAccessInfo: Decodable {
    let browserOpenUrl: String
    let directUrl: String
    let canonicalUrl: String
    let fallbackUrl: String
    let localAliasChain: Bool
    let publicAliasActive: Bool
    let publicAliasProvider: String
    let publicAliasUrl: String
}

struct NullHubComponentRollup: Decodable {
    let total: Int
    let running: Int
    let starting: Int
    let restarting: Int
    let failed: Int
    let stopped: Int
    let autoStart: Int
    let status: String
}

struct NullHubInstanceSummary: Decodable {
    let version: String
    let autoStart: Bool
    let launchMode: String
    let verbose: Bool
    let status: String
}

// MARK: - Components

struct NullHubComponentsResponse: Decodable {
    let components: [NullHubComponentInfo]
}

struct NullHubComponentInfo: Decodable {
    let name: String
    let displayName: String
    let description: String
    let repo: String
    let alpha: Bool
    let installed: Bool
    let standalone: Bool
    let instanceCount: Int
}

// MARK: - Instances

struct NullHubInstancesResponse: Decodable {
    let instances: [String: [String: NullHubInstanceSummary]]
}

// MARK: - Settings

struct NullHubSettings: Decodable {
    let port: Int
    let host: String
    let authToken: String?
    let autoUpdateCheck: Bool
    let access: NullHubAccessInfo
}

// MARK: - Service Status

struct NullHubServiceStatus: Decodable {
    let status: String
    let message: String?
    let registered: Bool
    let running: Bool
    let serviceType: String
    let unitPath: String?
}

// MARK: - Providers

struct NullHubProvidersResponse: Decodable {
    let providers: [NullHubProviderInfo]
}

struct NullHubProviderInfo: Decodable {
    let id: String
    let name: String
    let provider: String
    let apiKey: String?
    let model: String?
    let validatedAt: String?
    let validatedWith: String?
    let lastValidationAt: String?
    let lastValidationOk: Bool?
}

// MARK: - Channels (hub-level)

struct NullHubChannelsResponse: Decodable {
    let channels: [NullHubChannelInfo]
}

struct NullHubChannelInfo: Decodable {
    let id: String?
    let name: String?
    let channelType: String?
    let account: String?
    let validatedAt: String?
    let validatedWith: String?
}

// MARK: - Updates

struct NullHubUpdatesResponse: Decodable {
    let updates: [NullHubUpdateInfo]
}

struct NullHubUpdateInfo: Decodable {
    let component: String
    let instance: String
    let currentVersion: String
    let latestVersion: String
    let updateAvailable: Bool
}

// MARK: - Usage

struct NullHubUsageResponse: Decodable {
    let window: String
    let generatedAt: Int
    let totals: NullHubUsageTotals
    let byModel: [NullHubModelUsage]
    let byInstance: [NullHubInstanceUsage]
    let timeseries: [NullHubUsageTimeseriesEntry]
}

struct NullHubUsageTotals: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let requests: Int
}

struct NullHubModelUsage: Decodable {
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let requests: Int
}

struct NullHubInstanceUsage: Decodable {
    let instance: String?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let requests: Int?
}

struct NullHubUsageTimeseriesEntry: Decodable {
    let timestamp: Int?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

// MARK: - Meta Routes

struct NullHubMetaRoutesResponse: Decodable {
    let version: Int
    let routes: [NullHubRouteInfo]
}

struct NullHubRouteInfo: Decodable {
    let id: String
    let method: String
    let pathTemplate: String
    let category: String
    let summary: String?
    let destructive: Bool?
    let authRequired: Bool?
    let authMode: String?
    let pathParams: [NullHubRouteParam]?
    let queryParams: [NullHubRouteParam]?
    let response: String?
    let examples: [NullHubRouteExample]?
}

struct NullHubRouteParam: Decodable {
    let name: String?
    let location: String?
    let type: String?
    let required: Bool?
    let description: String?
}

struct NullHubRouteExample: Decodable {
    let command: String?
    let description: String?
}
