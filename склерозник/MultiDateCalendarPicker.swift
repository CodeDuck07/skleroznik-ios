//
//  MultiDateCalendarPicker.swift
//  склерозник
//

import SwiftUI

#if os(iOS)
import UIKit

/// Календарь с мультивыбором дней (UICalendarView).
struct MultiDateCalendarPicker: UIViewRepresentable {
    @Binding var selectedDates: Set<Date>
    var accentColor: UIColor
    var calendar: Calendar = .current

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let calendarView = UICalendarView()
        calendarView.calendar = calendar
        calendarView.locale = Locale(identifier: "ru_RU")
        calendarView.tintColor = accentColor
        calendarView.overrideUserInterfaceStyle = .dark
        calendarView.backgroundColor = .clear
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        calendarView.setContentCompressionResistancePriority(.required, for: .vertical)

        let selection = UICalendarSelectionMultiDate(delegate: context.coordinator)
        calendarView.selectionBehavior = selection
        context.coordinator.selection = selection
        context.coordinator.syncSelectionFromBinding()

        return calendarView
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        uiView.tintColor = accentColor
        context.coordinator.syncSelectionFromBinding()
    }

    final class Coordinator: NSObject, UICalendarSelectionMultiDateDelegate {
        var parent: MultiDateCalendarPicker
        weak var selection: UICalendarSelectionMultiDate?
        var isSyncingFromBinding = false

        init(parent: MultiDateCalendarPicker) {
            self.parent = parent
        }

        func syncSelectionFromBinding() {
            guard let selection else { return }
            let bindingDays = parent.selectedDates
            let uiDays = daySet(from: selection.selectedDates)
            guard bindingDays != uiDays else { return }

            isSyncingFromBinding = true
            selection.selectedDates = bindingDays.map {
                parent.calendar.dateComponents([.year, .month, .day], from: $0)
            }
            isSyncingFromBinding = false
        }

        func multiDateSelection(_ selection: UICalendarSelectionMultiDate, didSelectDate dateComponents: DateComponents) {
            applySelection(from: selection)
        }

        func multiDateSelection(_ selection: UICalendarSelectionMultiDate, didDeselectDate dateComponents: DateComponents) {
            applySelection(from: selection)
        }

        func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canSelectDate dateComponents: DateComponents) -> Bool {
            true
        }

        func multiDateSelection(_ selection: UICalendarSelectionMultiDate, canDeselectDate dateComponents: DateComponents) -> Bool {
            true
        }

        private func applySelection(from selection: UICalendarSelectionMultiDate) {
            guard !isSyncingFromBinding else { return }
            let newSet = daySet(from: selection.selectedDates)
            guard newSet != parent.selectedDates else { return }
            parent.selectedDates = newSet
        }

        private func daySet(from components: [DateComponents]) -> Set<Date> {
            Set(
                components.compactMap { parent.calendar.date(from: $0) }
                    .map { parent.calendar.startOfDay(for: $0) }
            )
        }
    }
}
#endif
