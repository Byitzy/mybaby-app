import CoreData
import SwiftUI

/// "Nursery monitor (Noah's iPad) · listening · checked 3 min ago", one row for each monitor seen in the
/// last day, on Today and in Cry alerts.
///
/// Warns when a listening monitor hasn't checked in for 15 minutes. The warning comes from the check-ins
/// already synced to this phone, so it costs no extra notifications.
struct MonitorStatusRows: View {
    @FetchRequest private var monitors: FetchedResults<MonitorDevice>

    init(baby: Baby) {
        _monitors = FetchRequest(fetchRequest: baby.entries(MonitorDevice.recent()))
    }

    var body: some View {
        // The monitor doesn't list itself; its own screen says what it's doing.
        ForEach(monitors.filter { $0.uuid?.uuidString != NurseryMonitor.ownRowID }) { device in
            MonitorStatusRow(device: device)
        }
    }
}

private struct MonitorStatusRow: View {
    @ObservedObject var device: MonitorDevice

    var body: some View {
        // Redrawn each minute, so "checked 3 min ago" and the warning keep up.
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            HStack(alignment: .top, spacing: Spacing.m) {
                EmojiBadge(emoji: "📡", tint: device.isListening ? Palette.listening : Palette.inactive)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Nursery monitor (\(device.deviceName.isEmpty ? "spare device" : device.deviceName))")
                        .font(.body.weight(.medium))
                    Text(status(now: now))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if device.isStale(at: now) {
                        NoticeLabel(
                            "The monitor hasn't checked in since \(device.lastSeen.formatted(date: .omitted, time: .shortened)). Is it plugged in and on Wi-Fi?"
                        )
                        .font(.subheadline)
                        .padding(.top, Spacing.xs)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Listening · white noise · checked 3 min ago", or "Off since 7:02 AM".
    private func status(now: Date) -> String {
        guard device.isListening else {
            return "Off since \(device.lastSeen.formatted(date: .omitted, time: .shortened))"
        }
        var parts = ["Listening"]
        if device.noise != .off {
            parts.append("\(device.noise.title.lowercased()) noise")
        }
        parts.append("checked \(Self.ago(device.lastSeen, now: now))")
        return parts.joined(separator: " · ")
    }

    /// "just now", "3 min ago", "1h 20m ago".
    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Format.duration(seconds)) ago"
    }
}

/// Cry alerts' "Use this device as the baby monitor", and the family's monitors.
struct NurseryMonitorSection: View {
    @FetchRequest(fetchRequest: Baby.fetchAll()) private var babies: FetchedResults<Baby>
    @AppStorage(SettingsKey.selectedBaby, store: .shared) private var selectedBabyID = ""
    @AppStorage(SettingsKey.iCloudSync, store: .shared) private var syncEnabled = false

    private let monitor = NurseryMonitor.shared
    private let cryMonitor = CryMonitor.shared
    private let inboxes = AlertInboxes.shared

    var body: some View {
        let baby = Baby.preferred(from: Array(babies), selectedID: selectedBabyID)
        // Read so the section updates when iCloud is switched.
        let availability = syncEnabled ? NurseryMonitor.availability(for: baby) : .syncOff

        Section {
            if let baby {
                MonitorStatusRows(baby: baby)
            }

            if let explanation = availability.explanation {
                Label {
                    Text(explanation)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else if let baby {
                Button {
                    Task { await monitor.start(baby: baby) }
                } label: {
                    Label("Use this device as the baby monitor", systemImage: "dot.radiowaves.left.and.right")
                }
                if cryMonitor.mode == .monitorDevice, !monitor.isActive, let error = cryMonitor.errorMessage {
                    NoticeLabel(error, systemImage: "exclamationmark.circle.fill", tint: Palette.danger)
                        .font(.subheadline)
                }
            }

            if availability == .available, let status = inboxes.status {
                NoticeLabel(
                    status,
                    systemImage: inboxes.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: inboxes.isReady ? Palette.ok : Palette.warning
                )
                .font(.subheadline)
            }
        } header: {
            Text("Nursery monitor")
        } footer: {
            Text("Leave an old iPhone or iPad by the crib, plugged in. It listens for crying, can play white noise and a night light, and alerts the parent on duty through your family's own iCloud. Audio never leaves the device.")
        }
    }
}
