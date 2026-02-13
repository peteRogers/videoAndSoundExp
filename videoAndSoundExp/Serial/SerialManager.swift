import Foundation
import SwiftUI

enum SerialManagerError: Error {
    case noValueAtIndex
}

@MainActor
@Observable
class SerialManager {
    // MARK: - Public properties
    var availablePorts: [String] = []
    var connectedPort: String?
    var isConnected: Bool { handle != nil }
    var receivedText: String = ""
    var lastLine: String = "Waiting for data"
    var latestValueFromArduino: String = ""
    var errorMessage: String?
    
    // MARK: - Private properties
    private var handle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var updateContinuations: [UUID: AsyncStream<[Int: Float]>.Continuation] = [:]

     // 2) Change this property to notify listeners on change
     var latestValuesFromArduino: [Int: Float] = [:] {
         didSet {
             for c in updateContinuations.values {
                 c.yield(latestValuesFromArduino)
             }
         }
     }

     // 3) Add this continuous stream
    @MainActor
    var updates: AsyncStream<[Int: Float]> {
        AsyncStream { continuation in
            let id = UUID()

            // Register the continuation on the main actor
            Task { @MainActor in
                self.updateContinuations[id] = continuation
                // Optionally send current snapshot immediately
                continuation.yield(self.latestValuesFromArduino)
            }

            // Clean up on termination, on the main actor
            continuation.onTermination = { [weak self] _ in
                // hop safely to the main actor before touching self
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateContinuations[id] = nil
                }
            }
        }
    }
    
    // MARK: - Port management
    init(simulate: Bool = false) {
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        let isPreview = false
        #endif

        if simulate {
            print("🧩 Simulated SerialManager created — no real hardware.")
        } else if isPreview {
            print("👀 Detected SwiftUI Preview — skipping serial setup.")
        } else {
            refreshPorts()
            if let lastPort = availablePorts.last {
                connect(to: lastPort)
            }
        }
    }
    
    deinit {
        let disconnectCopy = self.disconnect
        Task.detached { @MainActor in
            print("💀 SerialManager deinitialized — closing connection.")
            disconnectCopy()
        }
    }
    
    func refreshPorts() {
        // macOS serial ports are usually under /dev/cu.*
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: "/dev")
            availablePorts = contents
                .filter { $0.hasPrefix("cu.") }
                .map { "/dev/" + $0 }
                .sorted()
        } catch {
            errorMessage = "Could not list serial ports: \(error.localizedDescription)"
        }
    }
    
    func connect(to path: String, baudRate: Int = 9600) {
        print("🔧 Attempting connection to \(path)...")
        
        // Prevent multiple connections
        if isConnected {
            print("⚠️ Already connected to \(connectedPort ?? path), skipping reconnect.")
            return
        }
        
        print("🔌 Disconnecting any previous connection before reconnect...")
        disconnect()
        
        let file = FileHandle(forUpdatingAtPath: path)
        guard let file else {
            errorMessage = "Failed to open \(path)"
            print("❌ Could not open \(path)")
            return
        }
        
        handle = file
        connectedPort = path
        print("✅ Connected to \(path), waiting for Arduino to reset...")
        
        // Wait briefly for Arduino reset before reading
        Task {
            try? await Task.sleep(for: .seconds(1))
            self.startReading()
        }
    }
    
    func disconnect() {
        print("🔻 Disconnect called — closing serial port.")
        readerTask?.cancel()
        readerTask = nil
        try? handle?.close()
        handle = nil
        connectedPort = nil
    }
    
    // MARK: - Reading and writing
    
    private func startReading() {
        guard readerTask == nil else {
            print("⚠️ Already reading — skipping new task")
            return
        }
        guard let handle else { return }
        
        print("🚀 Starting serial read loop...")
        
        readerTask = Task { [weak self] in
            guard let self else { return }
            
            var buffer = Data()
            let newline: UInt8 = 10 // '\n'
            
            do {
                for try await chunk in handle.bytes {
                    buffer.append(chunk)
                    
                    while let newlineIndex = buffer.firstIndex(of: newline) {
                        let lineData = buffer[..<newlineIndex]
                        buffer.removeSubrange(..<buffer.index(after: newlineIndex))

                        guard var line = String(data: lineData, encoding: .utf8) else { continue }
                        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }

                        await MainActor.run {
                            self.receivedText += line + "\n"
                            self.lastLine = line
                            print(self.lastLine)
                            // ✅ Parse "id:value" (e.g. "0:100")
                            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                            guard parts.count == 2 else { return }

                            let idStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            let valStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

                            guard let id = Int(idStr),
                                  let value = Float(valStr)
                            else { return }

                            self.latestValuesFromArduino[id] = value   // ✅ accepts new IDs automatically
                            self.latestValueFromArduino = String(value)
                        }
                    }
                    
                    if buffer.count > 4096 {
                        print("⚠️ Discarding oversized buffer of \(buffer.count) bytes")
                        buffer.removeAll()
                    }
                }
                
                print("🛑 Serial stream ended.")
            } catch {
                await MainActor.run {
                    self.errorMessage = "Read error: \(error.localizedDescription)"
                }
                print("❌ Serial read error: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                self.readerTask = nil
                print("🔚 Reader task cleaned up.")
            }
        }
    }
    
    func send(_ string: String) {
        guard let handle else { return }
        guard let data = (string + "\n").data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            errorMessage = "Write failed: \(error.localizedDescription)"
        }
    }
    
    // Map using value at given index in latestValuesFromArduino, throws if missing
    func mapRange(index: Int, inMin: Float, inMax: Float, outMin: Float, outMax: Float) throws -> Float {
        guard let value = latestValuesFromArduino[index] else {
            throw SerialManagerError.noValueAtIndex
        }
        let clampedValue = min(max(value, inMin), inMax)
        let inRange = inMax - inMin
        let outRange = outMax - outMin
        let scaled = (clampedValue - inMin) / inRange
        return outMin + (scaled * outRange)
    }
    
    // Optionally keep the old function for direct mapping
    func mapRange(value: Float, inMin: Float, inMax: Float, outMin: Float, outMax: Float) -> Float {
        let clampedValue = min(max(value, inMin), inMax)
        let inRange = inMax - inMin
        let outRange = outMax - outMin
        let scaled = (clampedValue - inMin) / inRange
        return outMin + (scaled * outRange)
    }
    
    
    
}

extension Float {
    func mapped(from inMin: Float, _ inMax: Float, to outMin: Float, _ outMax: Float) -> Float {
        let clamped = min(max(self, inMin), inMax)
        let inRange = inMax - inMin
        let outRange = outMax - outMin
        let scaled = (clamped - inMin) / inRange
        return outMin + (scaled * outRange)
    }
}





// In SerialManager.swift (or its own file)
@MainActor
@Observable
final class MockSerialManager: SerialManager {

    init() {                     // <-- No 'override' here
        super.init(simulate: true)
        simulateIncomingValues()
    }

    private func simulateIncomingValues() {
        Task { [weak self] in
            var v: Int = 0
            while let self = self {
                try? await Task.sleep(for: .milliseconds(300))
                v = (v + Int.random(in: 1...25)) % 1024
                // Update whatever properties your UI reads:
                self.latestValueFromArduino = String(v)
                self.lastLine = "VAL:\(v)"
                // If you keep a dictionary:
                self.latestValuesFromArduino[0] = Float(v)
            }
        }
    }
}
