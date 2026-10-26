import CallKit
import Foundation

/// Knows whether a phone or FaceTime call is going on. iOS gives the microphone to the call, so cry
/// alerts can't start during one; this lets them start by themselves once the call ends.
final class CallWatcher: NSObject, CXCallObserverDelegate {
    static let shared = CallWatcher()

    private let observer = CXCallObserver()
    /// Run once, on the main queue, when the last call ends.
    private var whenCallsEnd: (() -> Void)?

    override private init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    var isOnCall: Bool {
        observer.calls.contains { !$0.hasEnded }
    }

    /// Runs `action` when no call is going on any more (replacing an earlier one).
    func afterCallsEnd(_ action: @escaping () -> Void) {
        whenCallsEnd = action
    }

    func cancel() {
        whenCallsEnd = nil
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard !isOnCall, let action = whenCallsEnd else { return }
        whenCallsEnd = nil
        action()
    }
}
