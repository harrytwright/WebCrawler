
//
//  Defaults.swift
//  WebCrawler
//
//  Created by Harry Wright on 09/03/2018.
//

import Foundation
import SystemConfiguration

// TODO: ME
/* Clean this up */

public let kTimeTakenKey = "io.webcrawler.previous.time_taken"
public let kProcessedAmount = "io.webcrawler.previous.time_taken"
public let kUserDefault = UserDefaults.standard

func platform() -> String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0,  count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
}

internal let baseUserAgent = "eSportsCrawler"
private let crawlerVersion = "0.1"
private let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
#if os(Linux)
public let kDefaultUserAgent = "\(baseUserAgent)/\(crawlerVersion) (Linux;\(platform());\(osVersion))"
#else
public let kDefaultUserAgent = "\(baseUserAgent)/\(crawlerVersion) (Macintosh;\(platform());\(osVersion))"
#endif

class Value<Object: Codable>: NSCoding, Codable {

    var value: Object

    var dataSelf: Data {
        return try! JSONEncoder().encode(self.value)
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(dataSelf, forKey: "io.value.\(type(of: value))")
    }

    required init?(coder aDecoder: NSCoder) {
        guard let data = aDecoder.decodeData() else { return nil }
        do { self.value = try JSONDecoder().decode(Object.self, from: data) }
        catch { Log.error(error.localizedDescription); return nil }
    }

}

extension UserDefaults {
    func set<O>(_ value: Value<O>, forKey key: String) {
        self.set(value, forKey: key)
    }

    func value<O: Codable>(of type: O.Type, forKey key: String) -> Value<O>? {
        return self.object(forKey: key) as? Value<O>
    }

    func exists(_ key: String) -> Bool {
        return UserDefaults.standard.object(forKey: key) != nil
    }
}
