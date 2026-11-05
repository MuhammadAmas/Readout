import os

enum Log {
    static let capture = Logger(subsystem: "dev.readout.Readout", category: "capture")
    static let speech = Logger(subsystem: "dev.readout.Readout", category: "speech")
}
