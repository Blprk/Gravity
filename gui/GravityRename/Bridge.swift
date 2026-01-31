import Foundation

enum BridgeError: Error {
    case binaryNotFound
    case processFailed(String)
    case decodingFailed(Error)
}

struct PreviewItem: Codable, Identifiable {
    var id: String { original_path }
    let original_path: String
    let new_path: String
    let conflicts: [Conflict]
    let warnings: [String]
}

struct Conflict: Codable {
    let type: String
    let path: String?
    let name: String?
    
    var description: String {
        switch type {
        case "target_exists": return "Target already exists"
        case "collision": return "Name collision with another file"
        case "case_collision": return "Case collision (on case-insensitive FS)"
        case "reserved_name": return "Reserved OS filename"
        case "source_not_found": return "Source file moved or deleted"
        default: return "Unknown conflict"
        }
    }
}

class RenameBridge {
    static let shared = RenameBridge()
    
    // Find the rust binary. In production, this would be bundled.
    // For development, we'll assume it's in a known location or built via cargo.
    private var binaryPath: String {
        return Bundle.module.path(forResource: "gravity-cli", ofType: nil) ?? "/usr/local/bin/gravity-cli"
    }

    func runPreview(files: [URL], rules: [Rule]) async throws -> [PreviewItem] {
        let rulesURL = try saveTemporaryRules(rules)
        let filePaths = files.map { $0.path }
        
        let output = try await runBinary(arguments: ["preview", "--json", "--rules", rulesURL.path] + filePaths)
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode([PreviewItem].self, from: output)
        } catch {
            throw BridgeError.decodingFailed(error)
        }
    }

    var journalDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("GravityRename/Journals")
    }

    func listJournals() throws -> [URL] {
        let folder = journalDirectory
        if !FileManager.default.fileExists(atPath: folder.path) { return [] }
        
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [URLResourceKey.creationDateKey])
        return files.filter { $0.pathExtension == "json" }
            .sorted { (a, b) -> Bool in
                let dateA = (try? a.resourceValues(forKeys: [URLResourceKey.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [URLResourceKey.creationDateKey]))?.creationDate ?? .distantPast
                return dateA > dateB
            }
    }

    func commit(files: [URL], rules: [Rule]) async throws -> String {
        let rulesURL = try saveTemporaryRules(rules)
        let filePaths = files.map { $0.path }
        
        let outputData = try await runBinary(arguments: [
            "--journal-dir", journalDirectory.path,
            "commit", "--rules", rulesURL.path
        ] + filePaths)
        
        let outputString = String(data: outputData, encoding: .utf8) ?? ""
        
        // Extract journal path for persistence if needed
        if let range = outputString.range(of: "Journal saved to ") {
            let journalPath = outputString[range.upperBound...].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            UserDefaults.standard.set(journalPath, forKey: "LastJournalPath")
        }
        
        return outputString
    }

    func undo(journalURL: URL? = nil) async throws -> String {
        let actualURL: URL
        if let url = journalURL {
            actualURL = url
        } else if let lastPath = UserDefaults.standard.string(forKey: "LastJournalPath") {
            actualURL = URL(fileURLWithPath: lastPath)
        } else {
            throw BridgeError.processFailed("No journal file found to undo. Please select one manually.")
        }
        
        let output = try await runBinary(arguments: ["undo", "--journal", actualURL.path])
        return String(data: output, encoding: .utf8) ?? "Undo Success"
    }

    private func runBinary(arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: data)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown stderr"
                    print("RUST ERROR: \(errorMessage)")
                    continuation.resume(throwing: BridgeError.processFailed(errorMessage))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func saveTemporaryRules(_ rules: [Rule]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID().uuidString).json")
        let data = try JSONEncoder().encode(rules)
        try data.write(to: url)
        return url
    }
}

// Mirroring the Rust Rule enum
struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: RuleType
    var params: [String: String]
    
    enum RuleType: String, Codable, CaseIterable {
        case strip_prefix
        case strip_suffix
        case regex_replace
        case case_transform
        case counter
        case literal
        case date_insertion
    }
    
    // Manual CodingKeys to handle the "flat" JSON from Rust
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int?
        init?(intValue: Int) { return nil }
    }

    enum StaticCodingKeys: String, CodingKey {
        case type
    }

    init(type: RuleType, params: [String: String] = [:]) {
        self.type = type
        self.params = params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StaticCodingKeys.self)
        type = try container.decode(RuleType.self, forKey: .type)
        
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var allParams: [String: String] = [:]
        
        for key in dynamicContainer.allKeys {
            if key.stringValue != "type" {
                if let value = try? dynamicContainer.decode(String.self, forKey: key) {
                    allParams[key.stringValue] = value
                } else if let intValue = try? dynamicContainer.decode(Int.self, forKey: key) {
                    allParams[key.stringValue] = String(intValue)
                }
            }
        }
        params = allParams
    }

    func encode(to encoder: Encoder) throws {
        var container = try encoder.container(keyedBy: DynamicCodingKeys.self)
        try container.encode(type.rawValue, forKey: DynamicCodingKeys(stringValue: "type")!)
        
        for (key, value) in params {
            if let k = DynamicCodingKeys(stringValue: key) {
                // Paranoid sanitization: ensure numeric keys are always Ints
                let numericKeys = ["start", "padding", "step", "index"]
                if numericKeys.contains(key) {
                    let intVal = Int(value) ?? (key == "padding" ? 3 : 1)
                    try container.encode(intVal, forKey: k)
                } else {
                    try container.encode(value, forKey: k)
                }
            }
        }
    }
    
    static func == (lhs: Rule, rhs: Rule) -> Bool {
        lhs.type == rhs.type && lhs.params == rhs.params
    }

    func defaultParams(for type: RuleType) -> [String: String] {
        switch type {
        case .strip_prefix: return ["prefix": ""]
        case .strip_suffix: return ["suffix": ""]
        case .regex_replace: return ["pattern": "", "replacement": ""]
        case .case_transform: return ["transform": "lowercase"]
        case .counter: return ["start": "1", "padding": "3", "step": "1", "separator": "_"]
        case .literal: return ["text": "", "position": "start"]
        case .date_insertion: return ["format": "%Y-%m-%d", "source": "current"]
        }
    }
}
