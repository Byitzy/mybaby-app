import SwiftUI

/// A date row like a compact `DatePicker`, except the calendar closes as soon as a day is tapped,
/// since that's when people are done. Paging months or changing the month and year keeps it open.
/// With `includesTime`, the time stays its own button next to the date, as in `DatePicker`.
///
/// Takes the same arguments as `DatePicker`, so it's a drop-in replacement in forms. Like
/// `DatePicker`, a literal title is looked up in the String Catalog; a `String` is shown as it is.
struct DateField: View {
    private let title: Text
    @Binding private var selection: Date
    private let range: ClosedRange<Date>
    private let includesTime: Bool

    @State private var showingCalendar = false
    @State private var showingTime = false

    init(_ title: LocalizedStringKey, selection: Binding<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: nil, latest: nil, includesTime: includesTime)
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: range.lowerBound, latest: range.upperBound, includesTime: includesTime)
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: nil, latest: range.upperBound, includesTime: includesTime)
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: range.lowerBound, latest: nil, includesTime: includesTime)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, selection: Binding<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: nil, latest: nil, includesTime: includesTime)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: ClosedRange<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: range.lowerBound, latest: range.upperBound, includesTime: includesTime)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeThrough<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: nil, latest: range.upperBound, includesTime: includesTime)
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: PartialRangeFrom<Date>, includesTime: Bool = true) {
        self.init(label: Text(title), selection: selection, earliest: range.lowerBound, latest: nil, includesTime: includesTime)
    }

    private init(label title: Text, selection: Binding<Date>, earliest: Date?, latest: Date?, includesTime: Bool) {
        self.title = title
        _selection = selection
        let lower = earliest ?? .distantPast
        // A range that ends before it starts would crash; keep the latest at or after the earliest.
        self.range = lower...max(latest ?? .distantFuture, lower)
        self.includesTime = includesTime
    }

    var body: some View {
        LabeledContent {
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
                .accessibilityLabel(Text(joining: [title, Text(verbatim: selection.formatted(date: .complete, time: .omitted))], separator: ", "))
                .accessibilityHint("Opens a calendar")
                .popover(isPresented: $showingCalendar) {
                    DayCalendar(selection: $selection, range: range) {
                        showingCalendar = false
                    }
                    .presentationCompactAdaptation(.popover)
                }

                if includesTime {
                    // Its own button too: a compact time picker next to the date button in a form row
                    // didn't open when tapped.
                    Button {
                        showingTime = true
                    } label: {
                        Text(selection, format: .dateTime.hour().minute())
                            .foregroundStyle(showingTime ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("\(title) time, \(selection.formatted(date: .omitted, time: .shortened))", comment: "VoiceOver: a date field's time button, e.g. \"Birthday time, 3:10 PM\""))
                    .accessibilityHint("Opens a time picker")
                    .popover(isPresented: $showingTime) {
                        TimeWheel(selection: $selection, range: range) {
                            showingTime = false
                        }
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
        } label: {
            title
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

/// The time wheel inside the popover, with Done, since a wheel has no moment when it's "picked".
private struct TimeWheel: View {
    @Binding var selection: Date
    let range: ClosedRange<Date>
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s) {
            DatePicker("", selection: $selection, in: range, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Button("Done", action: onDone)
                .font(.headline)
        }
        .frame(minWidth: 260)
        .padding()
    }
}
