//
//  ContentView.swift
//  склерозник
//
//  Created by Tina on 06.05.2026.
//

import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

private enum RemindersHomeColors {
    static let deepGreen = Color(red: 0.08, green: 0.19, blue: 0.15)
    static let forestGreen = Color(red: 0.13, green: 0.31, blue: 0.24)
    static let softGreenSurface = Color(red: 0.16, green: 0.36, blue: 0.28)
    static let missedAmber = Color(red: 0.92, green: 0.62, blue: 0.22)
    static let whiteText = Color.white
    static let secondaryText = Color.white.opacity(0.82)
}

struct ContentView: View {
    private struct ReminderBackupDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }
        var data: Data

        init(reminders: [Reminder]) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(reminders)
        }

        init(configuration: ReadConfiguration) throws {
            guard let fileData = configuration.file.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            data = fileData
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }

    private enum ImportApplyMode {
        case replace
        case merge
    }

    private struct ImportSuccessPayload {
        let importedCount: Int
        let totalCount: Int
        let mode: ImportApplyMode
    }

    enum ReminderFilter: String, CaseIterable, Identifiable {
        case past = "Прошедшие"
        case future = "Будущие"

        var id: String { rawValue }
    }

    /// Как система должна повторять локальное уведомление.
    enum RepeatRule: String, Codable, CaseIterable, Identifiable, Equatable {
        case none = "none"
        case daily = "daily"
        case weekly = "weekly"
        case yearly = "yearly"

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .none: return "Не повторять"
            case .daily: return "Каждый день"
            case .weekly: return "Каждую неделю"
            case .yearly: return "Каждый год"
            }
        }
    }

    struct Reminder: Identifiable, Codable, Equatable {
        let id: UUID
        var text: String
        var date: Date
        var notes: String = ""
        var isCompleted: Bool = false
        /// Повтор уведомления в одно и то же время по календарю (можно менять в деталях).
        var repeatRule: RepeatRule
        /// Когда пользователь явно подтвердила просмотр после пропуска по времени (кнопка «Поняла» или «Сохранить» в деталях). nil = ещё не подтверждено.
        var acknowledgedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, text, date, notes, isCompleted, repeatRule, acknowledgedAt
        }

        init(id: UUID, text: String, date: Date, notes: String = "", isCompleted: Bool = false, repeatRule: RepeatRule = .none, acknowledgedAt: Date? = nil) {
            self.id = id
            self.text = text
            self.date = date
            self.notes = notes
            self.isCompleted = isCompleted
            self.repeatRule = repeatRule
            self.acknowledgedAt = acknowledgedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            text = try c.decode(String.self, forKey: .text)
            date = try c.decode(Date.self, forKey: .date)
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
            repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none
            acknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encode(date, forKey: .date)
            try c.encode(notes, forKey: .notes)
            try c.encode(isCompleted, forKey: .isCompleted)
            try c.encode(repeatRule, forKey: .repeatRule)
            try c.encodeIfPresent(acknowledgedAt, forKey: .acknowledgedAt)
        }
    }

    /// Разовое напоминание: время прошло, не выполнено, пользователь не подтвердила просмотр — остаётся во «Будущие» с подсветкой «Пропущено».
    static func isMissedUnacknowledged(_ r: Reminder, now: Date = Date()) -> Bool {
        guard !r.isCompleted, r.acknowledgedAt == nil, r.repeatRule == .none else { return false }
        return r.date < now
    }

    @Environment(\.reminderNotificationAttach) private var notificationAttach
    @ObservedObject var notificationRouter: NotificationRouter

    @State private var reminders: [Reminder] = []
    @State private var filter: ReminderFilter = .future
    @State private var showAddSheet = false
    @State private var navigationPath = NavigationPath()
    @State private var showExportPicker = false
    @State private var exportDocument: ReminderBackupDocument?
    @State private var exportFilename = "reminders-backup.json"
    @State private var showImportPicker = false
    @State private var pendingImportedReminders: [Reminder] = []
    @State private var showImportModeDialog = false
    @State private var importSuccessPayload: ImportSuccessPayload?
    @State private var importErrorMessage: String?
    @AppStorage("didRequestNotificationsPermission") private var didRequestNotificationsPermission = false
    private let remindersStorageKey = "savedReminders"

    var body: some View {
        navigationStackRoot
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showAddSheet) {
                addReminderSheet()
            }
            .fileExporter(
                isPresented: $showExportPicker,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    importErrorMessage = "Не удалось экспортировать файл: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
            }
            .confirmationDialog(
                "Как импортировать данные?",
                isPresented: $showImportModeDialog,
                titleVisibility: .visible
            ) {
                Button("Заменить текущие") {
                    applyImportedReminders(mode: .replace)
                }
                Button("Объединить без дублей") {
                    applyImportedReminders(mode: .merge)
                }
                Button("Отмена", role: .cancel) {
                    pendingImportedReminders = []
                }
            } message: {
                Text("Найдено \(pendingImportedReminders.count) напоминаний в файле.")
            }
            .alert(
                "Импорт завершён",
                isPresented: Binding(
                    get: { importSuccessPayload != nil },
                    set: { if !$0 { importSuccessPayload = nil } }
                ),
                presenting: importSuccessPayload
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { payload in
                if payload.mode == .replace {
                    Text("Заменено \(payload.importedCount) напоминаний.")
                } else {
                    Text("Добавлено \(payload.importedCount) напоминаний. Всего: \(payload.totalCount).")
                }
            }
            .alert(
                "Ошибка",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "Неизвестная ошибка")
            }
            .onAppear(perform: onRootAppear)
            .onChange(of: notificationRouter.pendingOpenReminderId) { _, newId in
                guard newId != nil else { return }
                DispatchQueue.main.async {
                    applyPendingOpenFromNotification()
                }
            }
            .onChange(of: reminders) { _, _ in
                saveReminders()
                writeLocalBackupFile()
                DispatchQueue.main.async {
                    refreshScheduledNotificationsFromReminders()
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var navigationStackRoot: some View {
        NavigationStack(path: $navigationPath) {
            remindersHome
                .navigationDestination(for: UUID.self, destination: navigationDestinationView)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Экспорт") {
                                prepareExport()
                            }
                            Button("Импорт") {
                                showImportPicker = true
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(RemindersHomeColors.whiteText)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(RemindersHomeColors.whiteText)
                        }
                        .accessibilityLabel("Добавить напоминание")
                    }
                }
        }
    }

    private var remindersHome: some View {
        ZStack {
            LinearGradient(
                colors: [RemindersHomeColors.deepGreen, RemindersHomeColors.forestGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // List внутри VStack без явного maxHeight на части устройств/версий iOS даёт
            // неопределённую вертикальную вёрстку и пустой (чёрный) контент до первого жеста.
            VStack(spacing: 16) {
                Text("Напоминания")
                    .font(.largeTitle.bold())
                    .foregroundStyle(RemindersHomeColors.whiteText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("", selection: $filter) {
                    ForEach(ReminderFilter.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .colorScheme(.dark)

                remindersList
                    .scrollContentBackground(Visibility.hidden)
                    .background(RemindersHomeColors.forestGreen.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
        }
    }

    private var remindersList: some View {
        List {
            ForEach(filteredReminderIndices, id: \.self) { index in
                let reminder = reminders[index]
                let missed = Self.isMissedUnacknowledged(reminder)
                ReminderListRow(reminder: reminder, missed: missed, filter: filter) {
                    deleteReminder(id: reminders[index].id)
                }
            }
        }
    }

    @ViewBuilder
    private func navigationDestinationView(id: UUID) -> some View {
        if let idx = reminders.firstIndex(where: { $0.id == id }) {
            ReminderDetailView(reminder: $reminders[idx])
        } else {
            deletedReminderPlaceholder
        }
    }

    private var deletedReminderPlaceholder: some View {
        Text("Напоминание удалено")
            .foregroundStyle(RemindersHomeColors.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [RemindersHomeColors.deepGreen, RemindersHomeColors.forestGreen],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    @ViewBuilder
    private func addReminderSheet() -> some View {
        AddReminderSheet(onSave: { newReminders in
            for newReminder in newReminders {
                scheduleNotification(
                    for: newReminder.text,
                    date: newReminder.date,
                    identifier: newReminder.id.uuidString,
                    reminderId: newReminder.id,
                    repeatRule: newReminder.repeatRule
                )
            }
            reminders.append(contentsOf: newReminders)
        })
        .preferredColorScheme(.dark)
    }

    private func onRootAppear() {
        notificationAttach?.attach(router: notificationRouter)
        requestNotificationPermission()
        loadReminders()
        DispatchQueue.main.async {
            refreshScheduledNotificationsFromReminders()
            applyPendingOpenFromNotification()
        }
    }

    /// Сборка даты и времени как при добавлении напоминания (доступно для ReminderDetailView).
    static func combinedDateTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute

        return calendar.date(from: dateComponents) ?? date
    }

    /// Вкладки без дублирования одной карточки.
    ///
    /// «Поняла, вижу» / `acknowledgedAt` снимает только «пропущено» (`isMissedUnacknowledged`).
    /// Разовое (`repeatRule == .none`) с датой в прошлом после подтверждения попадает во «Прошедшие»
    /// (ветка `date < now`, не completed), во «Будущие» — нет.
    ///
    /// Повторяющиеся (daily/weekly/yearly): карточка «Пропущено» не используется (`isMissedUnacknowledged` всегда false).
    /// Они остаются во «Будущие»; «Поняла» для них не меняет вкладку и не отменяет будущие срабатывания UN.
    private var filteredReminderIndices: [Int] {
        let now = Date()
        let filteredIndices = reminders.indices.filter { index in
            let r = reminders[index]
            switch filter {
            case .future:
                if Self.isMissedUnacknowledged(r, now: now) { return true }
                if r.isCompleted { return r.date >= now }
                if r.repeatRule != .none { return true }
                return r.date >= now
            case .past:
                if Self.isMissedUnacknowledged(r, now: now) { return false }
                if r.isCompleted { return r.date < now }
                if r.repeatRule != .none { return false }
                return r.date < now
            }
        }

        return filteredIndices.sorted { lhs, rhs in
            let l = reminders[lhs]
            let r = reminders[rhs]
            let lm = Self.isMissedUnacknowledged(l, now: now)
            let rm = Self.isMissedUnacknowledged(r, now: now)

            switch filter {
            case .future:
                if lm != rm { return lm && !rm }
                return l.date < r.date
            case .past:
                return l.date > r.date
            }
        }
    }

    private func requestNotificationPermission() {
        guard !didRequestNotificationsPermission else { return }
        didRequestNotificationsPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func applyPendingOpenFromNotification() {
        guard let id = notificationRouter.pendingOpenReminderId else { return }
        if reminders.contains(where: { $0.id == id }) {
            notificationRouter.pendingOpenReminderId = nil
            navigationPath = NavigationPath()
            navigationPath.append(id)
        } else {
            notificationRouter.pendingOpenReminderId = nil
        }
    }

    private func scheduleNotification(for text: String, date: Date, identifier: String, reminderId: UUID, repeatRule: RepeatRule = .none) {
        let content = UNMutableNotificationContent()
        content.title = "Напоминание"
        content.body = text
        content.sound = UNNotificationSound.default
        content.userInfo = [ReminderNotificationPayload.reminderIdKey: reminderId.uuidString]

        let calendar = Calendar.current
        let dateComponents: DateComponents
        let repeats: Bool

        switch repeatRule {
        case .none:
            dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            repeats = false
        case .daily:
            dateComponents = calendar.dateComponents([.hour, .minute], from: date)
            repeats = true
        case .weekly:
            dateComponents = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            repeats = true
        case .yearly:
            dateComponents = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            repeats = true
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeats)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification scheduling error: \(error.localizedDescription)")
            }
        }
    }

    private func deleteReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    private func refreshScheduledNotificationsFromReminders() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        for reminder in reminders where !reminder.isCompleted {
            if reminder.repeatRule == .none {
                guard reminder.date > Date() else { continue }
            }
            scheduleNotification(
                for: reminder.text,
                date: reminder.date,
                identifier: reminder.id.uuidString,
                reminderId: reminder.id,
                repeatRule: reminder.repeatRule
            )
        }
    }

    private func saveReminders() {
        do {
            let data = try JSONEncoder().encode(reminders)
            UserDefaults.standard.set(data, forKey: remindersStorageKey)
        } catch {
            print("Failed to save reminders: \(error.localizedDescription)")
        }
    }

    private func prepareExport() {
        do {
            exportDocument = try ReminderBackupDocument(reminders: reminders)
            exportFilename = "reminders-backup-\(Self.backupDateFormatter.string(from: Date())).json"
            showExportPicker = true
        } catch {
            importErrorMessage = "Не удалось подготовить экспорт: \(error.localizedDescription)"
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([Reminder].self, from: data)
                pendingImportedReminders = decoded
                showImportModeDialog = true
            } catch {
                importErrorMessage = "Не удалось прочитать файл или неверный формат JSON."
            }
        case .failure:
            importErrorMessage = "Не удалось выбрать файл."
        }
    }

    private func applyImportedReminders(mode: ImportApplyMode) {
        let importedCount: Int
        switch mode {
        case .replace:
            reminders = pendingImportedReminders
            importedCount = pendingImportedReminders.count
        case .merge:
            var existingIds = Set(reminders.map(\.id))
            let additions = pendingImportedReminders.filter { existingIds.insert($0.id).inserted }
            reminders.append(contentsOf: additions)
            importedCount = additions.count
        }

        pendingImportedReminders = []
        saveReminders()
        writeLocalBackupFile()
        refreshScheduledNotificationsFromReminders()
        importSuccessPayload = ImportSuccessPayload(importedCount: importedCount, totalCount: reminders.count, mode: mode)
    }

    private func writeLocalBackupFile() {
        do {
            let doc = try ReminderBackupDocument(reminders: reminders)
            let url = try Self.latestBackupFileURL()
            try doc.data.write(to: url, options: [.atomic])
        } catch {
            // Автобэкап аварийный: не блокируем UX, если не удалось записать файл.
        }
    }

    private static func latestBackupFileURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return docs.appendingPathComponent("latest-reminders-backup.json")
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: remindersStorageKey) else { return }

        do {
            reminders = try JSONDecoder().decode([Reminder].self, from: data)
        } catch {
            print("Failed to load reminders: \(error.localizedDescription)")
        }
    }
}

// MARK: - Строка списка (облегчает type-check основного body)

private struct ReminderListRow: View {
    let reminder: ContentView.Reminder
    let missed: Bool
    let filter: ContentView.ReminderFilter
    let onDelete: () -> Void

    private var isPastTab: Bool { filter == .past }
    private var showsMissedBadge: Bool { filter == .future && missed }
    private var topRightBadgeTitle: String? {
        guard filter == .future else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(reminder.date) { return "Сегодня" }
        if calendar.isDateInTomorrow(reminder.date) { return "Завтра" }
        return nil
    }
    private var textColor: Color {
        isPastTab ? RemindersHomeColors.secondaryText : (reminder.isCompleted ? RemindersHomeColors.secondaryText : RemindersHomeColors.whiteText)
    }
    private var rowOpacity: Double {
        isPastTab ? 0.78 : (reminder.isCompleted ? 0.78 : 1)
    }

    var body: some View {
        ZStack {
            rowCard
            NavigationLink(value: reminder.id) {
                EmptyView()
            }
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
            .opacity(0)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(Visibility.hidden)
        .swipeActions(edge: HorizontalEdge.trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private var rowCard: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 6) {
            HStack(alignment: VerticalAlignment.center, spacing: 8) {
                if isPastTab || reminder.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(RemindersHomeColors.secondaryText)
                }

                Text(reminder.text)
                    .font(.headline)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)

                if let topRightBadgeTitle {
                    Text(topRightBadgeTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RemindersHomeColors.missedAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RemindersHomeColors.missedAmber.opacity(0.22))
                        .clipShape(Capsule())
                } else if showsMissedBadge {
                    Text("Пропущено")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RemindersHomeColors.missedAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RemindersHomeColors.missedAmber.opacity(0.22))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                Label(
                    reminder.date.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
                .foregroundColor(.white)
                Label(
                    reminder.date.formatted(date: .omitted, time: .shortened),
                    systemImage: "clock"
                )
                .foregroundColor(.white)
            }
            .font(.subheadline)
            .foregroundStyle(isPastTab ? RemindersHomeColors.secondaryText.opacity(0.75) : (reminder.isCompleted ? RemindersHomeColors.secondaryText.opacity(0.75) : RemindersHomeColors.secondaryText))

            if reminder.repeatRule != .none {
                Label(reminder.repeatRule.localizedTitle, systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(RemindersHomeColors.secondaryText.opacity(0.9))
            }
        }
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
        .opacity(rowOpacity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(RemindersHomeColors.softGreenSurface.opacity(showsMissedBadge ? 0.88 : 0.92))
                .overlay {
                    if showsMissedBadge {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(RemindersHomeColors.missedAmber.opacity(0.12))
                    }
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(showsMissedBadge ? RemindersHomeColors.missedAmber : Color.white.opacity(0.08), lineWidth: showsMissedBadge ? 2 : 1)
        )
    }
}

// MARK: - Добавление напоминания (sheet)

private struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: ([ContentView.Reminder]) -> Void

    @State private var noteText = ""
    @State private var selectedDates: Set<Date> = []
    @State private var selectedTime = Date()
    @State private var selectedRepeatRule: ContentView.RepeatRule = .none
    @State private var didSeedInitialDate = false

    private let forestGreen = Color(red: 0.13, green: 0.31, blue: 0.24)
    private let softGreenSurface = Color(red: 0.16, green: 0.36, blue: 0.28)
    private let deepOrange = Color(red: 0.79, green: 0.43, blue: 0.19)
    private let whiteText = Color.white
    private let secondaryText = Color.white.opacity(0.82)

    private var trimmedNoteText: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedNoteText.isEmpty && !selectedDates.isEmpty
    }

    private var repeatPickerDisabled: Bool {
        selectedDates.count > 1
    }

    private var sortedSelectedDates: [Date] {
        selectedDates.sorted()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.19, blue: 0.15),
                        forestGreen,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        TextField("Что напомнить?", text: $noteText)
                            .foregroundStyle(whiteText)
                            .tint(deepOrange)
                            .padding(12)
                            .background(softGreenSurface.opacity(0.95))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Даты")
                                .font(.subheadline)
                                .foregroundStyle(secondaryText)

                            #if os(iOS)
                            MultiDateCalendarPicker(
                                selectedDates: $selectedDates,
                                accentColor: UIColor(deepOrange)
                            )
                            .frame(minHeight: 320)
                            #endif

                            if !selectedDates.isEmpty {
                                Text("Выбрано: \(selectedDates.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(whiteText)
                                Text(Self.formattedSelectedDatesSummary(sortedSelectedDates))
                                    .font(.caption)
                                    .foregroundStyle(secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(softGreenSurface.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack {
                            Text("Время")
                                .foregroundStyle(secondaryText)
                            Spacer()
                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(deepOrange)
                                .foregroundStyle(whiteText)
                        }
                        .padding(12)
                        .background(softGreenSurface.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Повтор")
                                .font(.subheadline)
                                .foregroundStyle(secondaryText)
                            if repeatPickerDisabled {
                                Text("При нескольких датах — без повтора")
                                    .font(.caption)
                                    .foregroundStyle(secondaryText)
                            }
                            Picker("Повтор", selection: $selectedRepeatRule) {
                                ForEach(ContentView.RepeatRule.allCases) { rule in
                                    Text(rule.localizedTitle).tag(rule)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(deepOrange)
                            .foregroundStyle(whiteText)
                            .disabled(repeatPickerDisabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(repeatPickerDisabled ? 0.55 : 1)
                        .padding(12)
                        .background(softGreenSurface.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            submit()
                        } label: {
                            Text("Добавить")
                                .font(.headline)
                                .foregroundStyle(whiteText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(deepOrange.opacity(canSubmit ? 1 : 0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canSubmit)
                    }
                    .padding()
                    .padding(.bottom, 8)
                    .background(forestGreen.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding()
                }
            }
            .navigationTitle("Новое напоминание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(whiteText)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                guard !didSeedInitialDate else { return }
                didSeedInitialDate = true
                selectedDates = [Calendar.current.startOfDay(for: Date())]
            }
            .onChange(of: selectedDates.count) { _, count in
                if count > 1 {
                    selectedRepeatRule = .none
                }
            }
        }
    }

    private static func formattedSelectedDatesSummary(_ dates: [Date]) -> String {
        guard !dates.isEmpty else { return "" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        if dates.count > 1, areConsecutiveDays(dates, calendar: calendar) {
            let first = dates[0]
            let last = dates[dates.count - 1]
            if calendar.isDate(first, equalTo: last, toGranularity: .month),
               calendar.isDate(first, equalTo: last, toGranularity: .year) {
                formatter.setLocalizedDateFormatFromTemplate("d")
                let startDay = formatter.string(from: first)
                formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
                return "\(startDay)–\(formatter.string(from: last))"
            }
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
        }

        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return dates.map { formatter.string(from: $0) }.joined(separator: ", ")
    }

    private static func areConsecutiveDays(_ dates: [Date], calendar: Calendar) -> Bool {
        guard dates.count > 1 else { return false }
        for index in 1..<dates.count {
            guard let expected = calendar.date(byAdding: .day, value: 1, to: dates[index - 1]),
                  calendar.isDate(expected, inSameDayAs: dates[index]) else {
                return false
            }
        }
        return true
    }

    private func submit() {
        guard canSubmit else { return }

        let repeatRule: ContentView.RepeatRule = selectedDates.count > 1 ? .none : selectedRepeatRule
        let newReminders = sortedSelectedDates.map { day in
            ContentView.Reminder(
                id: UUID(),
                text: trimmedNoteText,
                date: ContentView.combinedDateTime(date: day, time: selectedTime),
                notes: "",
                isCompleted: false,
                repeatRule: repeatRule
            )
        }

        onSave(newReminders)
        dismiss()
    }
}

#Preview {
    ContentView(notificationRouter: NotificationRouter())
}
