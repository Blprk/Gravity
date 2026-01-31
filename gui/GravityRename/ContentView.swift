import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var files: [URL] = []
    @State private var rules: [Rule] = [
        Rule(type: .literal, params: ["text": "final_", "position": "start"])
    ]
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var previewItems: [PreviewItem] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var previewTask: Task<Void, Never>?
    @State private var showingConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var showingHistory = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RuleStackView(
                rules: $rules,
                addRule: addRule,
                saveRules: saveRules,
                loadRules: loadRules
            )
            .navigationTitle("Rules")
        } detail: {
            DetailView(
                files: $files,
                rules: $rules,
                previewItems: $previewItems,
                errorMessage: $errorMessage,
                showingConfirmation: $showingConfirmation,
                alertMessage: $alertMessage,
                showingAlert: $showingAlert,
                showingHistory: $showingHistory,
                executeRename: executeRename,
                undoLastRename: undoLastRename,
                updatePreview: updatePreview
            )
        }
        .onChange(of: rules) { _, _ in updatePreview() }
        .onChange(of: files) { _, _ in updatePreview() }
    }

    func addRule(_ type: Rule.RuleType) {
        let rule = Rule(type: type)
        rules.append(Rule(type: type, params: rule.defaultParams(for: type)))
    }

    func saveRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Rules.gravity"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try JSONEncoder().encode(rules)
                try data.write(to: url)
            } catch {
                alertMessage = "Failed to save: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    func loadRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                rules = try JSONDecoder().decode([Rule].self, from: data)
            } catch {
                alertMessage = "Failed to load: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }

    func undoLastRename() {
        Task {
            do {
                let result = try await RenameBridge.shared.undo()
                alertMessage = "Undo Successful: \(result)"
                showingAlert = true
            } catch {
                alertMessage = "No recent rename found. Use history to select manually."
                showingAlert = true
            }
        }
    }

    func updatePreview() {
        previewTask?.cancel()
        previewTask = Task {
            await MainActor.run { isProcessing = true }
            // Debounce: 150ms is perfect for the new parallel engine
            try? await Task.sleep(nanoseconds: 150_000_000) 
            if Task.isCancelled { return }
            
            do {
                let items = try await RenameBridge.shared.runPreview(files: files, rules: rules)
                if !Task.isCancelled {
                    await MainActor.run {
                        self.previewItems = items
                        self.errorMessage = nil
                        self.isProcessing = false
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isProcessing = false
                    }
                }
            }
        }
    }

    func executeRename() {
        Task {
            do {
                _ = try await RenameBridge.shared.commit(files: files, rules: rules)
                await MainActor.run {
                    files.removeAll()
                    previewItems.removeAll()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct DetailView: View {
    @Binding var files: [URL]
    @Binding var rules: [Rule]
    @Binding var previewItems: [PreviewItem]
    @Binding var errorMessage: String?
    @Binding var showingConfirmation: Bool
    @Binding var alertMessage: String?
    @Binding var showingAlert: Bool
    @Binding var showingHistory: Bool
    let executeRename: () -> Void
    let undoLastRename: () -> Void
    let updatePreview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                EmptyStateView(files: $files)
            } else {
                PreviewTableView(items: previewItems)
            }
            
            Divider()
            
            // Premium Bottom Bar
            HStack(spacing: 20) {
                HStack(spacing: 12) {
                    Button(action: { showingHistory.toggle() }) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showingHistory, arrowEdge: .bottom) {
                        JournalHistoryPopover(alertMessage: $alertMessage, showingAlert: $showingAlert)
                    }
                    if !files.isEmpty {
                        Text("\(files.count) Items")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }

                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }
                }
                
                Spacer()
                
                Button("Clear") {
                    files.removeAll()
                    previewItems.removeAll()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(action: { showingConfirmation = true }) {
                    Text("Apply Changes")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty || previewItems.contains { !$0.conflicts.isEmpty })
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Gravity Rename")
        .confirmationDialog("Confirm Renaming?", isPresented: $showingConfirmation) {
            Button("Rename \(files.count) files", role: .destructive) {
                executeRename()
            }
        } message: {
            Text("Gravity will use the two-phase atomic engine to safely rename these files.")
        }
        .alert(alertMessage ?? "Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}

struct JournalHistoryPopover: View {
    @Binding var alertMessage: String?
    @Binding var showingAlert: Bool
    @State private var journals: [URL] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Transactions")
                .font(.headline)
                .padding()
            
            Divider()
            
            if journals.isEmpty {
                Text("No history found")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(width: 300)
            } else {
                List {
                    ForEach(journals, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                Text(formatDate(url))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Undo") {
                                performUndo(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(width: 350, height: 300)
            }
        }
        .onAppear {
            journals = (try? RenameBridge.shared.listJournals()) ?? []
        }
    }
    
    func formatDate(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func performUndo(_ url: URL) {
        Task {
            do {
                _ = try await RenameBridge.shared.undo(journalURL: url)
                alertMessage = "Transaction successfully reverted."
                showingAlert = true
            } catch {
                alertMessage = "Undo failed: \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

struct EmptyStateView: View {
    @Binding var files: [URL]
    @State private var isImporting = false
    
    var body: some View {
        VStack(spacing: 20) {
            if isImporting {
                ProgressView("Scanning files...")
            } else {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Drag and drop files here to begin")
                    .font(.headline)
                Button("Select Files") {
                    selectFiles()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task {
                            await importPaths([url])
                        }
                    }
                }
            }
            return true
        }
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            Task {
                await importPaths(panel.urls)
            }
        }
    }

    private func importPaths(_ urls: [URL]) async {
        await MainActor.run { isImporting = true }
        
        let uniqueFiles = await Task.detached(priority: .userInitiated) { () -> [URL] in
            var allFiles: [URL] = []
            let fileManager = FileManager.default
            
            for url in urls {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                            for case let fileURL as URL in enumerator {
                                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), resourceValues.isRegularFile == true {
                                    allFiles.append(fileURL)
                                }
                            }
                        }
                    } else {
                        allFiles.append(url)
                    }
                }
            }
            return Array(Set(allFiles)).sorted { $0.path < $1.path }
        }.value
        
        await MainActor.run {
            self.files = uniqueFiles
            self.isImporting = false
        }
    }
}

struct PreviewTableView: View {
    let items: [PreviewItem]
    
    var body: some View {
        Table(items) {
            TableColumn("Original") { item in
                Text(URL(fileURLWithPath: item.original_path).lastPathComponent)
            }
            TableColumn("New Name") { item in
                Text(URL(fileURLWithPath: item.new_path).lastPathComponent)
                    .foregroundColor(item.conflicts.isEmpty ? .primary : .red)
            }
            TableColumn("Status") { item in
                if item.conflicts.isEmpty {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading) {
                        ForEach(item.conflicts.indices, id: \.self) { i in
                            Text(item.conflicts[i].description)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}

struct RuleStackView: View {
    @Binding var rules: [Rule]
    let addRule: (Rule.RuleType) -> Void
    let saveRules: () -> Void
    let loadRules: () -> Void
    
    var body: some View {
        List {
            Section {
                HStack {
                    HStack(spacing: 12) {
                        Button(action: saveRules) {
                            Label("Save Rules", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.plain)

                        Button(action: loadRules) {
                            Label("Load Rules", systemImage: "folder")
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(.secondary)
                    .font(.caption2)
                }
                .padding(.vertical, 4)
            }
            
            Section("Pipeline") {
                HStack {
                    Menu {
                        Button("Strip Prefix") { addRule(.strip_prefix) }
                        Button("Strip Suffix") { addRule(.strip_suffix) }
                        Button("Filter Content") { addRule(.filter_content) }
                        Button("Regex Replace") { addRule(.regex_replace) }
                        Button("Literal Text") { addRule(.literal) }
                        Button("Counter") { addRule(.counter) }
                        Button("Case Transform") { addRule(.case_transform) }
                        Button("Date Insertion") { addRule(.date_insertion) }
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Button("Clear All", role: .destructive) {
                        rules.removeAll()
                    }
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.8))
                }
                .padding(.vertical, 4)

                ForEach(rules) { rule in
                    if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                        RuleRow(rule: $rules[index]) {
                            rules.remove(at: index)
                        }
                    }
                }
                .onMove { rules.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }
}

struct RuleRow: View {
    @Binding var rule: Rule
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Action", selection: Binding(
                    get: { rule.type },
                    set: { newType in
                        rule.type = newType
                        rule.params = rule.defaultParams(for: newType)
                    }
                )) {
                    ForEach(Rule.RuleType.allCases, id: \.self) { type in
                        Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Group {
                switch rule.type {
                case .strip_prefix:
                    TextField("Prefix to remove", text: parameterBinding("prefix"))
                case .strip_suffix:
                    TextField("Suffix to remove", text: parameterBinding("suffix"))
                case .literal:
                    HStack {
                        TextField("Text", text: parameterBinding("text"))
                        Picker("Position", selection: parameterBinding("position")) {
                            Text("Start").tag("start")
                            Text("End").tag("end")
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                case .regex_replace:
                    VStack(spacing: 4) {
                        TextField("Pattern (Regex)", text: parameterBinding("pattern"))
                        TextField("Replacement", text: parameterBinding("replacement"))
                    }
                case .counter:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Separator").font(.caption2)
                                TextField("_", text: parameterBinding("separator"))
                            }
                            VStack(alignment: .leading) {
                                Text("Start").font(.caption2)
                                TextField("1", text: parameterBinding("start"))
                            }
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Padding").font(.caption2)
                                TextField("3", text: parameterBinding("padding"))
                            }
                            VStack(alignment: .leading) {
                                Text("Step").font(.caption2)
                                TextField("1", text: parameterBinding("step"))
                            }
                        }
                    }
                case .case_transform:
                    Picker("Format", selection: parameterBinding("transform")) {
                        Text("lowercase").tag("lowercase")
                        Text("UPPERCASE").tag("uppercase")
                        Text("Title Case").tag("titlecase")
                    }
                    .labelsHidden()
                case .date_insertion:
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Format (e.g. %Y-%m-%d)", text: parameterBinding("format"))
                        Picker("Source", selection: parameterBinding("source")) {
                            Text("Current").tag("current")
                            Text("Created").tag("created")
                            Text("Modified").tag("modified")
                            Text("EXIF (Photo)").tag("exif")
                        }
                        .labelsHidden()
                    }
                case .filter_content:
                    Picker("Remove", selection: parameterBinding("filter")) {
                        Text("Numbers").tag("numbers")
                        Text("Letters").tag("letters")
                        Text("Whitespace").tag("whitespace")
                        Text("Symbols / Punctuation").tag("symbols")
                    }
                    .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func parameterBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { rule.params[key] ?? "" },
            set: { rule.params[key] = $0 }
        )
    }
}
