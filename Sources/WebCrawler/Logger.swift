//
//  Logger.swift
//  WebCrawler
//
//  Created by Harry Wright on 08/03/2018.
//

import Foundation
import os.log

internal struct Logger {

    internal static var global: Logger = Logger()

    internal var verbose: Bool = false

    func logMessage(_ msg: String, type: LogType, file: String, fn: String, line: UInt) {
        if !verbose && (type == .info || type == .debug) {
            return
        }

        /* For the command line this doesn't show up, so we print at the end */
        if #available(OSX 10.12, *) {
            let fmt: StaticString = type.showFunctionInfo ? "[%@:%@:%lu] %@" : "%@"

            let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "WebCrawler", category: "Networking")
            if type.showFunctionInfo {
                os_log(fmt, log: log, type: type.os_log_type, (file as NSString).lastPathComponent, fn, line, msg)
            } else {
                os_log(fmt, log: log, type: type.os_log_type, msg)
            }
        } else { fatalError("Invalid OS") }

        if ProcessInfo.processInfo.environment["WCXcode"] != nil { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-YYYY hh:mm:ssZ"
        let date = formatter.string(from: Date())

        let fmt = type.showFunctionInfo ? "%@ [%@:%@:%lu] %@" : "%@ %@"
        let message = type.showFunctionInfo ?
            String(format: fmt, date, (file as NSString).lastPathComponent, fn, line, msg) :
            String(format: fmt, date, msg)
        
        print(message)
    }

    enum LogType: Int {
        case `default` = 0
        case info
        case debug
        case error
        case fault

        var showFunctionInfo: Bool {
            switch self {
            case .default, .info: return false
            default: return true
            }
        }

        @available(OSX 10.12, *)
        var os_log_type: OSLogType {
            switch self {
            case .default: return .default
            case .info: return .info
            case .debug: return .debug
            case .error: return .error
            case .fault: return .fault
            }
        }
    }
}

public class Log {

    static func debug(
        _ msg: String,
        file: String = #file,
        fn: String = #function,
        line: UInt = #line
        )
    {
        Logger.global.logMessage(msg, type: .debug, file: file, fn: fn, line: line)
    }

    static func info(
        _ msg: String,
        file: String = #file,
        fn: String = #function,
        line: UInt = #line
        )
    {
        Logger.global.logMessage(msg, type: .info, file: file, fn: fn, line: line)
    }

    static func error(
        _ msg: String,
        file: String = #file,
        fn: String = #function,
        line: UInt = #line
        )
    {
        Logger.global.logMessage(msg, type: .error, file: file, fn: fn, line: line)
    }

    static func `default`(
        _ msg: String,
        file: String = #file,
        fn: String = #function,
        line: UInt = #line
        )
    {
        Logger.global.logMessage(msg, type: .default, file: file, fn: fn, line: line)
    }

    static func fault(
        _ msg: String,
        file: String = #file,
        fn: String = #function,
        line: UInt = #line
        )
    {
        Logger.global.logMessage(msg, type: .fault, file: file, fn: fn, line: line)
    }
}

