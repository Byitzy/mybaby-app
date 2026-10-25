import SwiftUI

/// A date row like a compact `DatePicker`, except the calendar closes as soon as a day is tapped,
/// since that's when people are done. Paging months or changing the month and year keeps it open.
/// With `includesTime`, the time stays its own button next to the date, as in `DatePicker`.
///
/// Takes the same arguments as `DatePicker`, so it's a drop-in replacement in forms.
struct DateField: View {
    private let title: String
    @Binding private var selection: Date
    private let range: ClosedRange<Date>
    private let includesTime: Bool

    @State private var showingCalendar = false

    init(_ title: String, selection: Binding<Date>, includesTime: Bool = true) {
        self.init(title, selection: selection, earliest: nil, latest: nil, includesTime: includesTime)
    }

    init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>, includesTime: Bool = true) {
        self.init(title, selection: selection, earliest: range.lowerBound, latest: range.upperBound, includesTime: includesTime)
    }

    init(_ title: String, selection: Binding<Date>, in range: PartialRangeThrough<Date>, includesTime: Bool = true) {
        self.init(title, selection: selection, earliest: nil, latest: range.upperBound, includesTime: includesTime)
    }

    init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>, includesTime: Bool = true) {
        self.init(title, selection: selection, earliest: range.lowerBound, latest: nil, includesTime: includesTime)
    }

    private init(_ title: String, selection: Binding<Date>, earliest: Date?, latest: Date?, includesTime: Bool) {
        self.title = title
        _selection = selection
        let lower = earliest ?? .distantPast
        // A range that ends before it starts would crash; keep the latest at or after the earliest.
        self.range = lower...max(latest ?? .distantFuture, lower)
        self.includesTime = includesTime
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Spacing.s) {
                Button {
                    showingCalendar = true
                } label: {
                    Text(selection, format: .dateTime.month(.abbreviated).day().year())
                        .foregroundStyle(showingCalendar ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(title), \(selection.formatted(date: .complete, time: .omitted))")
                .accessibilityHint("Opens a calendar")
                .popover(isPresented: $showingCalendar) {
                    DayCalendar(selection: $selection, range: range) {
                        showingCalendar = false
                    }
                    .presentationCompactAdaptation(.popover)
                }

                if includesTime {
                    DatePicker(title, selection: $selection, in: range, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
    }
}

/// The calendar inside the popover. Closes itself when the day changes.
private struct DayCalendar: View {
    @Binding var selection: Date
    let range: ClosedRange<Date>
    let onDayPicked: () -> Void

    var body: some View {
        DatePicker("", selection: $selection, in: range, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(minWidth: 320)
            .padding()
            .onChange(of: selection) { old, new in
                // Tapping a day changes the day. Choosing a month or year in the header can move the
                // date too, but keeps the day number, so that alone doesn't close the calendar.
                let calendar = Calendar.current
                if calendar.component(.day, from: old) != calendar.component(.day, from: new) {
                    onDayPicked()
                }
            }
    }
}
