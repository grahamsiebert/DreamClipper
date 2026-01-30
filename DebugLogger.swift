import Foundation

class DebugLogger {
    static let shared = DebugLogger()
    private let logURL: URL
    
    private init() {
        // Log to Desktop for easy access
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            logURL = desktop.appendingPathComponent("changecapture_debug.txt")
            // Create/Clear file
            try? "--- Log Started ---\n".write(to: logURL, atomically: true, encoding: .utf8)
        } else {
            logURL = URL(fileURLWithPath: "/tmp/changecapture_debug.txt")
        }
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        
        // Print to console as well
        print(line, terminator: "")
        
        // Write to file
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                // Fallback if file handle fails (e.g. first write)
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
