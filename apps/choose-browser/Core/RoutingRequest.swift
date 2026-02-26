import Foundation

struct RoutingRequest: Equatable {
    let url: URL
}

protocol RoutingRequestQueueing: AnyObject {
    func enqueue(_ request: RoutingRequest)
}
