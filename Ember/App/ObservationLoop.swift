import Observation

/// Runs `onChange` every time something `read` touches on an
/// `@Observable` object changes, on the main actor, after the change
/// (Observation reports before; this waits a turn). Lives until
/// `cancel()` or until it is released.
@MainActor
final class ObservationLoop {
    private let read: @MainActor () -> Void
    private let onChange: @MainActor () -> Void
    private var active = true

    init(read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        self.read = read
        self.onChange = onChange
        track()
    }

    func cancel() { active = false }

    private func track() {
        guard active else { return }
        withObservationTracking(read) { [weak self] in
            Task { @MainActor in
                guard let self, self.active else { return }
                self.onChange()
                self.track()
            }
        }
    }
}
