//
//  Crawler.swift
//  WebCrawler
//
//  Created by Harry Wright on 08/03/2018.
//

import Foundation
import Regex

extension Collection {
    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Iterator.Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// <#Description#>
public class Crawler {

    /// The URL that we started at
    public var startURL: URL

    /// The configuration for the Crawler,
    /// holds the robots.txt rules and the
    /// user agent for us
    public var configuration: Configuration

    /// The DispatchSemaphore that is waiting
    /// for us to finish
    public var semaphore: DispatchSemaphore

    /// The links we are planning on visiting
    public var pagesToVisit: Set<URL>

    /// The pages we have visited
    public var pagesVisited: Set<URL>

    /// The time between requests
    public var timeInterval: Int

    /// The UUID for the crawler
    ///
    /// - note: More so used if we create spawn Crawlers
    public var identifier: String

    /// The limit we have to visit
    public var maxPagesToVist: Int

    public init(
        startURL: URL,
        userAgent: String,
        maxPagesToVist: Int,
        timeInterval: Int,
        semaphore: DispatchSemaphore
        )
    {
        self.startURL = startURL
        self.semaphore = semaphore /* This halts the run loop, so once we are finished call semaphore.signal() */
        self.pagesVisited = []
        self.pagesToVisit = [startURL]
        self.identifier = UUID().uuidString
        self.maxPagesToVist = maxPagesToVist
        self.timeInterval = timeInterval
        self.configuration = Configuration(userAgent: userAgent, rules: .unknown)
    }

    var isCrawling: Bool = false

    /* This method starts the crawl going */
    public func crawl() {
        if isCrawling { Log.error("Crawling cannot be called while the crawler is crawling"); semaphore.signal(); return }
        run()
    }

}

extension Crawler {

    internal func run() {
        guard self.configuration.rules != .disallowedForAll else {
            Log.default("Looks like \(self.startURL.host ?? "Unknown") does not want use snooping")
            semaphore.signal()
            return
        }

        guard pagesVisited.count < self.maxPagesToVist else {
            Log.default("Max pages reached")
            semaphore.signal()
            return
        }

        guard let next = self.next() else {
            Log.default("No more pages left to visit")
            semaphore.signal()
            return
        }

        Log.info("Getting ready to vist: \(next)")
        self.isCrawling = true
        if next == startURL && !self.configuration.rules.robotsHasBeenChecked {
            self.visitRobots(for: next)
        } else {
            if pagesVisited.contains(next) {
                run()
            } else {
                let queue = DispatchQueue(label: "webcraler.\(UUID().uuidString.lowercased())")
                queue.asyncAfter(deadline: .now() + .milliseconds(crawler.timeInterval)) { [weak self] () in
                    self?.visit(next)
                }
            }
        }
    }

    /* Only validation here is that the host's are the same */
    func next() -> URL? {
        let next = self.pagesToVisit.popFirst()
        return next?.host == self.startURL.host ? next : nil /* Don't leave the host */
    }

    func visit(_ url: URL) {
        Log.default("Going to visit \(url)")

        self.pagesVisited.insert(url)
        Web(url: url, crawler: self).fetch { [weak self] (resp, data, error) in
            guard let strongSelf = self else { return }

            defer { strongSelf.run() }
            
            guard let data = data, let resp = resp else {
                Log.error(error?.localizedDescription ?? "Unkown error")
                return
            }

            do {
                let rawPage = try RawPage(response: resp, data: data)
                let parsedPage = try Page(page: rawPage)

                guard let links = parsedPage.links() else { return }

                var urls: [URL] = []
                for link in links {
                    let _link = _Link(base: strongSelf.startURL, href: link)
                    guard let url = _link.buildValidURL(with: strongSelf.configuration.rules) else { continue }
                    urls.append(url)
                }

                for url in urls where !strongSelf.pagesVisited.contains(url) {
                    strongSelf.pagesToVisit.insert(url)
                }

                Log.default("Visted \(url)\n")
            } catch {
                Log.error(error.localizedDescription)
                strongSelf.semaphore.signal()
                return
            }
        }
    }

    func visitRobots(for url: URL) {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/robots.txt"

        guard let _url = comps?.url else {
            Log.error("URLComponents could not create valid URL")
            exit(EXIT_FAILURE)
        }

        Log.default("First things, we need to check robot.txt")
        Log.debug("Visting robots.txt for \(url.host ?? url.description))")
        Web(url: _url, crawler: self).fetch { [weak self] (_, data, error) in
            guard let strongSelf = self else { return }
            guard let data = data else {
                Log.error(error?.localizedDescription ?? "Unkown error")
                exit(EXIT_FAILURE)
            }

            guard let string = String(data: data, encoding: .utf8) else {
                Log.error(_Error.couldNotDecodeData(url).localizedDescription)
                exit(EXIT_FAILURE)
            }

            Log.debug("Decoded the robots.txt, working out where we stand with the website")
            let robots = Robots(rawData: string.components(separatedBy: "\n").filter { !$0.isEmpty })
            robots.rules.forEach { info in
                /* Specific for our user-agent */
                if info.userAgent == baseUserAgent {
                    strongSelf.configuration.rules = info.rule
                } else if info.userAgent == "*" {
                    strongSelf.configuration.rules = info.rule
                }
            }

            switch strongSelf.configuration.rules {
            case .allowed, .disallowedForSome:
                Log.default("The robot's overloads have been kind and granted us access\n")
            default:
                break
            }

            /* Make sure the orginal URL is valid for the request, if not the crawler will stop */
            let newLink = _Link(base: url, other: url)
            if let validURL = newLink.buildValidURL(with: strongSelf.configuration.rules) {
                strongSelf.pagesToVisit.insert(validURL)
            }

            strongSelf.run()
        }
    }

}

extension Crawler {

    enum  _Error: Error, CustomStringConvertible {
        case couldNotDecodeData(URL)

        var localizedDescription: String {
            switch self {
            case .couldNotDecodeData(let url):
                return "We could not convert the NSData to String from: (\(url))"
            }
        }

        var description: String {
            return self.localizedDescription
        }
    }
}

extension Crawler: CustomStringConvertible {
    public var description: String { return self.identifier }
}

extension Crawler {

    /* This is the connection for the Request */
    public struct Web {

        private var request: URLRequest!

        private var crawler: Crawler

        public init(url: URL, crawler: Crawler) {
            self.crawler = crawler
            self.request = buildRequest(from: url)
        }

        public func fetch(_ callback: @escaping (URLResponse?, Data?, Error?) -> Void) {
            let task = URLSession.shared.dataTask(with: self.request) { (data, resp, error) in
                Log.debug("Finished crawling *exhausted*")
                callback(resp, data, error)
            }

            Log.debug("Crawling...")
            task.resume()
        }

        private func buildRequest(from url: URL) -> URLRequest {
            var req = URLRequest(url: url)
            req.addValue(crawler.configuration.userAgent, forHTTPHeaderField: "User-Agent")
            req.addValue(crawler.identifier, forHTTPHeaderField: "X-Web-Crawler-ID")
            return req
        }
    }
}

extension Crawler {

    /* The configuration for the _crawl() */
    public struct Configuration {
        public var userAgent: String
        public var rules: Rules
    }

}

extension Crawler.Configuration {
    public static var mediaWikiAnnoyingLinkThings: [String] {
        /* Media-Wiki shit links */
        return ["redlink", "index.php", "Template:"]
    }
}

fileprivate extension Crawler {

    /// The full robots.txt decoded
    struct Robots {

        typealias Rule = (userAgent: String, rule: Crawler.Configuration.Rules)

        var rawData: [String]

        var rules: [Rule] {
            let rawRules = rawData.filter { !$0.contains("#") }.seperate()

            var rules: [Rule] = []
            for rule in rawRules {
                /* Get user agent from `User-agent: <UA>` */
                guard var agent = rule.key.components(separatedBy: ":").last else { continue }
                while agent.hasPrefix(" ") { agent.removeFirst() }

                /* Get the path for the dissalow from `Disallow: /`  */
                let disallow = rule.value.map { (path) -> String in
                    return path.replacingOccurrences(of: "Disallow: ", with: "").replacingOccurrences(of: " ", with: "")
                }

                /* Convert array to Crawler.Configuration.Rules */
                var _rule: Crawler.Configuration.Rules = .notFound
                if let first = disallow.first, first == "/" {
                    _rule = .disallowedForAll
                } else if let first = disallow.first, first.isEmpty {
                    _rule = .allowed
                } else {
                    _rule = .disallowedForSome(disallow)
                }

                rules.append((userAgent: agent, rule: _rule))
            }
            return rules
        }
    }
}

extension Crawler.Configuration {

    /* The rules we have found in the robots.txt */
    public enum Rules {
        case disallowedForAll
        case disallowedForSome([String])
        case allowed
        case notFound /* We will still run */
        case unknown

        var robotsHasBeenChecked: Bool {
            switch self {
            case .unknown: return false
            default: return true
            }
        }
    }
}

extension Crawler.Configuration.Rules: Equatable {

    public static func ==(
        lhs: Crawler.Configuration.Rules,
        rhs: Crawler.Configuration.Rules
        ) -> Bool
    {
        switch (lhs, rhs) {
        case (.allowed, .allowed):
            return true
        case (.unknown, .unknown):
            return true
        case (.disallowedForAll, .disallowedForAll):
            return true
        case (.disallowedForSome, .disallowedForSome):
            return true
        case (.notFound, notFound):
            return true
        case (.notFound, _),
             (.unknown, _),
             (.allowed, _),
             (.disallowedForAll, _),
             (.disallowedForSome, _):
            return false
        }
    }

}

extension String {
    func contains(_ find: String, options: String.CompareOptions) -> Bool {
        return self.range(of: find, options: options) != nil
    }
}

extension Array where Element == String {

    func seperate() -> Dictionary<String, [String]> {
        var dict: [String:[String]] = [:]

        var currentUserAgent: String?
        var currentPaths: [String] = []
        for value in self {
            if value.contains("User-Agent:", options: .caseInsensitive) {
                if let userAgent = currentUserAgent {
                    dict.updateValue(currentPaths, forKey: userAgent);
                    currentPaths.removeAll()
                }
                currentUserAgent = value
            } else if value.contains("Disallow:", options: .caseInsensitive) {
                currentPaths.append(value)
            }
        }
        return dict
    }
}

enum DisallowType {
    case anyQuery(key: String)
    case valuedQuery(key: String, value: String)
    case path(String)

    init(_ value: String) {
        let regex = Regex("\\/\\*(&|\\?)?\\w*=[\\w\\d\\*]*")
        if regex.matches(value) {
            var newValue = value
            while newValue.hasPrefix("/") { newValue.removeFirst() }

            let values = newValue.components(separatedBy: "=")
            var key = values[0]; let value = values[1]

            if key.hasPrefix("*") { key.removeFirst() }
            if value == "*" {
                self = .anyQuery(key: key)
            } else {
                self = .valuedQuery(key: key, value: value)
            }
        } else {
            self = .path(value)
        }
    }
}

/// Struct to handle the creation of the new URL's from links
public struct _Link {

    var base: URL

    var hrefToNext: String

    public init(base: URL, href: String) {
        self.base = base
        self.hrefToNext = href
    }

    public init(base: URL, href: String?) {
        self.init(base: base, href: "")
    }

    public init(base: URL, other: URL) {
        let href = other.query != nil ? other.path + "?\(other.query!)" : other.path
        self.init(base: base, href: href)
    }

    public func buildValidURL(with rules: Crawler.Configuration.Rules) -> URL? {
        guard !hrefToNext.isEmpty, rules != .disallowedForAll else { return nil }

        switch rules {
        case .disallowedForSome(let invalids):
            let types = invalids.map { DisallowType($0) }
            for type in types where !isPathValidWithType(type) {
                return nil
            }
        case .allowed:
            break
        default:
            return nil
        }

        /* Things that aren't in the Robots.txt but are annoying to deal with */
        for link in Crawler.Configuration.mediaWikiAnnoyingLinkThings where hrefToNext.contains(link) {
            return nil
        }

        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }

        var href = hrefToNext
        while !href.hasPrefix("/") { href.insert("/", at: href.startIndex) }
        comps.path = href.withoutQuery
        comps.query = href.query

        return comps.url
    }

    private func isPathValidWithType(_ type: DisallowType) -> Bool {
        switch type {
        case .path(let _path):
            if _path.hasSuffix("*") { return !hrefToNext.contains(_path) }
            return hrefToNext != _path
        case .valuedQuery(let key, let value):
            return refContainsQuery((key, value))
        case .anyQuery(let key):
            return refContainsQuery((key, nil))
        }
    }

    func refContainsQuery(_ queryItem: (String, String?)) -> Bool {
        guard let query = hrefToNext.query else {
            return true /* If the path has no query no need to test it as it's valid */
        }

        let value = queryItem.1
        var key = queryItem.0

        if key.hasPrefix("&") || key.hasPrefix("?") {
            key.removeFirst()
        }

        let queryItems = query.urlQueryItems
        return value == nil ?
            !queryItems.contains(where: { $0.name == key }) :
            !queryItems.contains(where: { $0.name == key && $0.value == value })
    }
}

/* These may not work, will maybe add some analytics tools to test them */
extension String {

    fileprivate var query: String? {
        if (self as NSString).lastPathComponent.contains("?") {
            return (self as NSString)
                .lastPathComponent
                .components(separatedBy: "?")[safe: 1]
        } else if (self as NSString).lastPathComponent.contains("%3F") {
            return (self as NSString)
                .lastPathComponent
                .components(separatedBy: "%3F")[safe: 1]
        }
        return nil

    }

    fileprivate var urlQueryItems: [URLQueryItem] {
        var mutableSelf = self
        while mutableSelf.hasSuffix("?") || mutableSelf.hasSuffix("%3F") { mutableSelf.removeFirst() }

        let queryItems = self.components(separatedBy: "&")
        return queryItems.map {
            URLQueryItem(name: $0.components(separatedBy: "=")[0], value: $0.components(separatedBy: "=")[safe: 1])
        }
    }

    /* Becasue of the href containing both the path and query, the `?` gets escaped and need to be removed and adjusted for */
    fileprivate var withoutQuery: String {
        var comps = self.components(separatedBy: "/")
        if var last = comps.popLast() {
            if last.contains("%3F") {
                last = last.components(separatedBy: "%3F")[0]
            } else if last.contains("&") {
                last = last.components(separatedBy: "?")[0]
            }

            comps.append(last)
        }

        return comps.joined(separator: "/")
    }
}

