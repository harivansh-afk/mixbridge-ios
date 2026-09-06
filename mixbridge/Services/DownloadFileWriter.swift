import Foundation

/// Shared by the real URLSession byte stream and deterministic offline tests.
enum DownloadFileWriter {
    nonisolated static func write<Bytes: AsyncSequence>(
        _ bytes: Bytes, to destination: URL, expectedLength: Int64,
        progress: @Sendable (Double) async -> Void
    ) async throws where Bytes.Element == UInt8 {
        try Task.checkCancellation()
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var handle: FileHandle?
        do {
            let output = try FileHandle(forWritingTo: destination)
            handle = output
            var buffer = Data()
            buffer.reserveCapacity(128 * 1024)
            var received: Int64 = 0
            var lastProgress: Double = 0
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 128 * 1024 {
                    try Task.checkCancellation()
                    try output.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expectedLength > 0 {
                        let value = min(Double(received) / Double(expectedLength), 1)
                        if value - lastProgress >= 0.01 {
                            lastProgress = value
                            await progress(value)
                        }
                    }
                }
            }
            try Task.checkCancellation()
            if !buffer.isEmpty {
                try output.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }
            try output.close()
            if expectedLength > 0 && received != expectedLength {
                throw URLError(.networkConnectionLost)
            }
            guard received > 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? handle?.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
