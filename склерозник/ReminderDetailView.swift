//
//  ReminderDetailView.swift
//  склерозник
//
//  Created by Tina on 06.05.2026.
//

import SwiftUI

struct ReminderDetailView: View {
    @Binding var reminder: ContentView.Reminder
    @State private var draftText: String = ""
    @State private var draftNotes: String = ""
    @State private var draftRepeatRule: ContentView.RepeatRule = .none
    @State private var draftDate = Date()
    @State private var draftTime = Date()
    @State private var didInitializeDraft = false

    private let deepGreen = Color(red: 0.08, green: 0.19, blue: 0.15)
    private let forestGreen = Color(red: 0.13, green: 0.31, blue: 0.24)
    private let softGreenSurface = Color(red: 0.16, green: 0.36, blue: 0.28)
    private let deepOrange = Color(red: 0.79, green: 0.43, blue: 0.19)
    private let whiteText = Color.white
    private let secondaryText = Color.white.opacity(0.82)
    private let successGreen = Color(red: 0.22, green: 0.58, blue: 0.32)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Текст напоминания", text: $draftText)
                    .font(.title2.bold())
                    .foregroundStyle(whiteText)
                    .tint(whiteText)
                    .padding(10)
                    .background(softGreenSurface.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                DatePicker("Дата", selection: $draftDate, displayedComponents: .date)
                    .tint(deepOrange)
                    .foregroundStyle(whiteText)
                    .padding(12)
                    .background(softGreenSurface.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text("Время")
                        .foregroundStyle(secondaryText)
                    Spacer()
                    DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(deepOrange)
                        .foregroundStyle(whiteText)
                }
                .padding(12)
                .background(softGreenSurface.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Только разовые «пропущено»: снимает оранжевую подсветку; дальше вкладки по дате (см. filteredReminderIndices).
                // Повторы сюда не попадают (isMissedUnacknowledged для них false) — их расписание не трогаем.
                if ContentView.isMissedUnacknowledged(reminder) {
                    Button {
                        reminder.acknowledgedAt = Date()
                    } label: {
                        Text("Поняла, вижу")
                            .font(.headline)
                            .foregroundStyle(whiteText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(deepOrange.opacity(0.95))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Повтор")
                        .font(.headline)
                        .foregroundStyle(whiteText)
                    Picker("Повтор", selection: $draftRepeatRule) {
                        ForEach(ContentView.RepeatRule.allCases) { rule in
                            Text(rule.localizedTitle).tag(rule)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(deepOrange)
                    .foregroundStyle(whiteText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(softGreenSurface.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Комментарий")
                    .font(.headline)
                    .foregroundStyle(whiteText)

                TextEditor(text: $draftNotes)
                    .padding(8)
                    .frame(minHeight: 180)
                    .scrollContentBackground(Visibility.hidden)
                    .background(softGreenSurface.opacity(0.95))
                    .foregroundStyle(whiteText)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    saveChanges()
                } label: {
                    Text("Сохранить изменения")
                        .font(.headline)
                        .foregroundStyle(whiteText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(successGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!hasUnsavedChanges)
                .opacity(hasUnsavedChanges ? 1 : 0.55)

                Text(hasUnsavedChanges ? "Есть несохраненные изменения." : "Все изменения сохранены.")
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background {
            LinearGradient(
                colors: [deepGreen, forestGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Детали")
        .onAppear {
            guard !didInitializeDraft else { return }
            draftText = reminder.text
            draftNotes = reminder.notes
            draftRepeatRule = reminder.repeatRule
            let cal = Calendar.current
            if let dayOnly = cal.date(from: cal.dateComponents([.year, .month, .day], from: reminder.date)) {
                draftDate = dayOnly
            } else {
                draftDate = reminder.date
            }
            draftTime = reminder.date
            didInitializeDraft = true
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var combinedDraftDate: Date {
        ContentView.combinedDateTime(date: draftDate, time: draftTime)
    }

    private var hasUnsavedChanges: Bool {
        draftText != reminder.text ||
        draftNotes != reminder.notes ||
        draftRepeatRule != reminder.repeatRule ||
        combinedDraftDate != reminder.date
    }

    private func saveChanges() {
        reminder.text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draftNotes
        reminder.repeatRule = draftRepeatRule
        reminder.date = combinedDraftDate
        // Сохранение в деталях = осознанное действие: снимает «пропущено» для вкладки «Будущие» / «Прошедшие».
        reminder.acknowledgedAt = Date()
    }
}

#Preview {
    NavigationStack {
        ReminderDetailView(
            reminder: .constant(
                ContentView.Reminder(
                    id: UUID(),
                    text: "Позвонить врачу",
                    date: Date(),
                    notes: "Уточнить результаты анализов."
                )
            )
        )
    }
}
