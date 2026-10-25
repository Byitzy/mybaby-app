import SwiftUI

private struct CanEditLogKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether this iPhone can add to and change the baby's log. False for family the owner invited
    /// as view only (a grandparent, a nanny): screens still show everything, but buttons that log,
    /// save or delete are turned off. Set by the root view from `PersistenceController.canEdit`.
    var canEditLog: Bool {
        get { self[CanEditLogKey.self] }
        set { self[CanEditLogKey.self] = newValue }
    }
}

/// Explains why the buttons are off, for someone invited to the log as view only.
struct ViewOnlyBanner: View {
    var message = "You can see everything, but only the parents can add or change entries."

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("View only")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
