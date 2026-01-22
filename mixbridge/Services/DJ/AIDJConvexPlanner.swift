import Foundation

@MainActor
struct AIDJConvexPlanner: AIDJPlanner {
    func plan(request: AIDJMixPlanRequest) async throws -> AIDJMixPlanResponse {
        try await ConvexService.shared.planAIDJMix(request: request)
    }
}
