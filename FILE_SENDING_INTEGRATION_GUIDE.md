# WinDrop File Sending API - Integration Guide

## C++ DLL to C# to Swift File Sending Flow

This document explains the architecture and what the Swift backend needs to implement to receive files sent from Windows via the C++ DLL.

---

## Architecture Overview

```
Windows (C#)
    ↓
    └─→ C++ DLL (FileSendManager + FileSender)
            ↓
            └─→ TCP Connection (ASIO)
                    ↓
                    └─→ iOS/macOS Device (Swift)
```

### Data Flow:

1. **C# Frontend** calls `WD_SendFile(filepath, remoteHost, remotePort)`
2. **C++ DLL** (FileSendManager) validates file and initiates TCP connection
3. **FileSender** opens file and sends it via TCP/IP to remote address
4. **Swift Backend** (on iOS/macOS) listens on the specified port and receives the file

---

## C# Frontend Integration

The C# frontend should:

1. **Get the receiver endpoint from the remote device** (obtained via handshake/QR code)
   - Format: `"192.168.1.100:5050"` (IP:port)

2. **Call the file sending API:**
   ```csharp
   // Platform invoke declaration
   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern int WD_SendFile(string filePath, string host, ushort port);

   // Usage example:
   string filePath = @"C:\Users\User\Pictures\photo.jpg";
   string host = "192.168.1.100";
   ushort port = 5050;

   int result = WD_SendFile(filePath, host, port);
   // result: 0 = success, >0 = error code
   ```

3. **Monitor send progress and state:**
   ```csharp
   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern int WD_GetSendState();
   // Returns: 0=Idle, 1=Sending, 2=Completed, 3=Error

   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern int WD_IsSending();
   // Returns: 1 if sending, 0 otherwise

   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern int WD_GetSendProgress(
       out ulong bytesSent,
       out ulong totalBytes,
       StringBuilder filename, int filenameBufChars);
   ```

4. **Handle errors:**
   ```csharp
   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern int WD_GetSendError(StringBuilder buffer, int bufChars);

   [DllImport("WinDrop.dll", CallingConvention = CallingConvention.Cdecl)]
   public static extern void WD_ClearSendError();
   ```

---

## Swift Backend Implementation

The Swift backend (on iOS/macOS) must implement the **receiver side** to accept files. Here's what it needs to do:

### 1. **Listen on a TCP Port**

Create a TCP server that listens on the specified port (e.g., 5050):

```swift
import Foundation
import Network

class WinDropReceiver {
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 5050
    
    func startListening() throws {
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: port)
        
        listener?.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Listener ready on port \(self.port)")
            case .failed(let error):
                print("Listener failed: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { newConnection in
            self.handleNewConnection(newConnection)
        }
        
        listener?.start(queue: .main)
    }
    
    func stopListening() {
        listener?.cancel()
        listener = nil
    }
}
```

### 2. **Handle Incoming Connections**

When a connection arrives from Windows, perform the **handshake** and receive the file:

```swift
private func handleNewConnection(_ connection: NWConnection) {
    print("New connection from: \(connection.endpoint)")
    
    // The Windows side will send the file header first
    // We need to read and parse it
    receiveFileHeader(from: connection)
}

private func receiveFileHeader(from connection: NWConnection) {
    // Windows sends a simple text header before the file
    // Header format:
    // FILENAME:myfile.jpg\n
    // SIZE:123456\n
    // MIME:image/jpeg\n
    // ENDHEADER\n
    
    var headerData = Data()
    let queue = DispatchQueue(label: "com.windrop.receiver")
    
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            self.readData(from: connection, into: &headerData, queue: queue)
        case .failed(let error):
            print("Connection failed: \(error)")
        default:
            break
        }
    }
    
    connection.start(queue: queue)
}

private func readData(from connection: NWConnection, into data: inout Data, queue: DispatchQueue) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, context, isComplete, error in
        guard let self = self else { return }
        
        if let data = data, !data.isEmpty {
            // Parse header or accumulate file data
            if let headerEnd = self.parseHeader(data) {
                // Header received, start receiving file body
                self.receiveFileBody(from: connection, headerSize: headerEnd)
            } else if data.count < 1000 {
                // Still reading header, continue
                self.readData(from: connection, into: &data, queue: queue)
            }
        }
        
        if isComplete || error != nil {
            connection.cancel()
        }
    }
}
```

### 3. **Parse File Header**

Parse the header sent by Windows to extract filename, size, and MIME type:

```swift
private func parseHeader(_ data: Data) -> Int? {
    guard let headerString = String(data: data, encoding: .utf8) else {
        return nil
    }
    
    let lines = headerString.components(separatedBy: "\n")
    var filename: String?
    var fileSize: UInt64?
    var mimeType: String?
    var headerEndIndex: Int = 0
    
    for (index, line) in lines.enumerated() {
        if line.hasPrefix("FILENAME:") {
            filename = String(line.dropFirst("FILENAME:".count))
        } else if line.hasPrefix("SIZE:") {
            fileSize = UInt64(String(line.dropFirst("SIZE:".count)))
        } else if line.hasPrefix("MIME:") {
            mimeType = String(line.dropFirst("MIME:".count))
        } else if line.hasPrefix("ENDHEADER") {
            headerEndIndex = index
            break
        }
    }
    
    guard let fileName = filename, let size = fileSize else {
        return nil
    }
    
    // Store metadata for file being received
    currentReceivedFile = ReceivedFileMetadata(
        filename: fileName,
        size: size,
        mimeType: mimeType ?? "application/octet-stream"
    )
    
    // Return byte offset where file data starts
    return headerString.prefix(upTo: headerString.firstIndex(where: { _ in true })!).count
}

struct ReceivedFileMetadata {
    let filename: String
    let size: UInt64
    let mimeType: String
    var bytesReceived: UInt64 = 0
}
```

### 4. **Receive and Save File**

After header is parsed, receive the actual file data and save it:

```swift
private func receiveFileBody(from connection: NWConnection, headerSize: Int) {
    var totalBytesReceived: UInt64 = 0
    let queue = DispatchQueue(label: "com.windrop.file-receiver")
    
    let downloadURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    func receiveChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    self.fileReceiveCompleted()
                }
                return
            }
            
            // Write chunk to file
            let fileURL = downloadURL.appendingPathComponent(self.currentReceivedFile!.filename)
            
            if totalBytesReceived == 0 {
                // First chunk, create file
                try? data.write(to: fileURL)
            } else {
                // Append to existing file
                if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            }
            
            totalBytesReceived += UInt64(data.count)
            self.currentReceivedFile?.bytesReceived = totalBytesReceived
            
            print("Progress: \(totalBytesReceived) / \(self.currentReceivedFile?.size ?? 0)")
            
            if totalBytesReceived >= self.currentReceivedFile?.size ?? 0 {
                // File complete
                self.fileReceiveCompleted()
                connection.cancel()
            } else {
                // Request more data
                receiveChunk()
            }
        }
    }
    
    receiveChunk()
}

private func fileReceiveCompleted() {
    print("File received: \(currentReceivedFile?.filename ?? "unknown")")
    // Update UI, notify user, etc.
    currentReceivedFile = nil
}
```

---

## Wire Protocol Specification

### File Transfer Message Format

The Windows C++ DLL sends files using this simple text-based protocol:

```
[HEADER]
FILENAME:<filename>\n
SIZE:<file_size_in_bytes>\n
MIME:<mime_type>\n
ENDHEADER\n
[FILE_DATA]
<binary file content - exactly SIZE bytes>
```

### Example

For a JPEG file named `photo.jpg` (1234 bytes):

```
FILENAME:photo.jpg
SIZE:1234
MIME:image/jpeg
ENDHEADER
<1234 bytes of binary JPEG data>
```

---

## Key Implementation Details

### Port Selection
- Windows sends to port specified by remote device (typically from handshake/QR code)
- Swift backend must listen on the same port
- Example: If QR contains `192.168.1.100:5050`, Windows connects to that address

### File Path Storage
- Swift should save files to the app's **Documents** or **Downloads** directory
- Ensure proper permission handling for file system access

### Error Handling
- Validate file size before accepting (prevent disk space attacks)
- Handle connection drops gracefully
- Implement timeouts for inactive connections

### Threading
- Use DispatchQueue or async/await for network operations
- Keep UI responsive during file transfer

### MIME Type Support
The Windows DLL recognizes these MIME types:
- `image/jpeg` (.jpg, .jpeg)
- `image/png` (.png)
- `image/heic` (.heic, .heif)
- `video/quicktime` (.mov)
- `video/mp4` (.mp4)
- `video/x-msvideo` (.avi)
- `application/octet-stream` (all others)

Swift should use these MIME types to determine how to handle received files (image gallery, video library, etc.).

---

## Complete Swift Example (Simplified)

```swift
import Foundation
import Network

class WinDropServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port = 5050
    
    func start() throws {
        let parameters = NWParameters.tcp
        listener = try NWListener(using: parameters, on: port)
        listener?.newConnectionHandler = { connection in
            DispatchQueue(global()).async {
                self.handleConnection(connection)
            }
        }
        listener?.start(queue: .main)
        print("WinDrop listening on port \(port)")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(global()))
        
        // Read header (up to 1KB)
        var headerBuffer = Data()
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
            guard let data = data else { return }
            headerBuffer.append(data)
            
            if let headerInfo = self.parseHeader(Data(headerBuffer)) {
                self.receiveFileData(connection, fileInfo: headerInfo)
            }
        }
    }
    
    private func parseHeader(_ data: Data) -> (filename: String, size: UInt64)? {
        guard let str = String(data: data, encoding: .utf8),
              let filenameRange = str.range(of: "FILENAME:"),
              let sizeRange = str.range(of: "SIZE:"),
              let endRange = str.range(of: "ENDHEADER") else {
            return nil
        }
        
        let filename = String(str[filenameRange.upperBound...].prefix(while: { $0 != "\n" }))
        let sizeStr = String(str[sizeRange.upperBound...].prefix(while: { $0 != "\n" }))
        
        guard let size = UInt64(sizeStr) else { return nil }
        return (filename, size)
    }
    
    private func receiveFileData(_ connection: NWConnection, fileInfo: (filename: String, size: UInt64)) {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileInfo.filename)
        
        var totalBytes: UInt64 = 0
        
        let receiveMore = {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, _ in
                guard let data = data else { return }
                
                do {
                    if totalBytes == 0 {
                        try data.write(to: fileURL)
                    } else {
                        let handle = try FileHandle(forWritingTo: fileURL)
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try handle.close()
                    }
                    
                    totalBytes += UInt64(data.count)
                    print("Received \(totalBytes) / \(fileInfo.size) bytes")
                } catch {
                    print("Error writing file: \(error)")
                }
                
                if isComplete || totalBytes >= fileInfo.size {
                    connection.cancel()
                    print("File received: \(fileInfo.filename)")
                } else {
                    receiveMore()
                }
            }
        }
        
        receiveMore()
    }
}
```

---

## Summary

**Windows (C#) → C++ DLL → Network → Swift (iOS/macOS)**

The C++ DLL handles:
✅ File validation
✅ TCP connection establishment  
✅ File header formatting
✅ Binary file transmission

The Swift backend must handle:
✅ TCP server listening
✅ Header parsing
✅ Binary file reception
✅ File storage
✅ Progress tracking
✅ Error handling

This architecture allows seamless file transfer from Windows to iOS/macOS devices across the network.
