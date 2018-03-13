//
//  Models.swift
//  WebCrawler
//
//  Created by Harry Wright on 08/03/2018.
//

import Foundation
//import SwiftSoup
import Kanna /* Kanna is faster as it used libxml to handle all the parsing (C is faster than swift)! */

// TODO: ME
/* Clean this up */

public struct RawPage: Hashable {

    public var url: URL

    public var document: HTMLDocument

    public init(response: URLResponse, data: Data) throws {
        guard let url = response.url else { throw _Error.missingURLFromResponse(response) }

        self.url = url
        self.document = try HTML(html: data, encoding: .utf8)
    }

    private enum _Error: Error {
        case missingURLFromResponse(URLResponse)
        case couldDataNotConvertToString(Data)
    }

    public var hashValue: Int {
        return url.hashValue
    }

    public static func ==(lhs: RawPage, rhs: RawPage) -> Bool {
        return lhs.url == rhs.url
    }
}

public class Page {

    public var url: URL

    public var rawTitle: String

    public var rawHead: Kanna.XMLElement

    public var rawBody: Kanna.XMLElement

    internal init(page: RawPage) throws {
        guard let head = page.document.head else { throw _Error("Missing HTML head") }
        guard let body = page.document.body else { throw _Error("Missing HTML body") }

        self.url = page.url
        self.rawHead = head
        self.rawBody = body
        self.rawTitle = page.document.title ?? page.url.absoluteString
    }

    public lazy var tableTags: [TableTag] = {
        let tags = rawBody.xpath("//table").map {
            TableTag(tag: $0)
        }
        return tags
    }()

    public func links() -> Set<String>? {
        guard let idx = self.tableTags.index(where: { $0.tag.className == "navbox" }) else { return nil }
        let navBox = self.tableTags[idx]

        /*
         For some reason when using the `naxBox.tag` there was more links than
         their should have been? So as a workaround we just decode and re-initalise
         a new HTML object
        */
        guard let text = navBox.tag.toHTML, let table = try? HTML(html: text, encoding: .utf8) else {
            return nil
        }

        // Search for nodes by XPath
        var urls: Set<String> = []
        for link in table.xpath("//a | //link") where link.className != "nowraplinks navbox-subgroup" {
            guard let href = link["href"] else { continue }
            urls.insert(href)
        }

        return !urls.isEmpty ? urls : nil
    }
}

extension Page {

    public struct MetaTag {

        public var key: String

        public var content: String?

        fileprivate init?(tag: XPathObject.Element) {
            guard let key = tag["name"] != nil ? tag["name"] : tag["property"] else { return nil }

            self.key = key
            self.content = tag["content"]
        }
    }

    public struct TableTag {

        public var tag: XPathObject.Element

        init(tag: XPathObject.Element) {
            self.tag = tag
        }

        public var childTables: [TableTag]? {
            let tables = self.tag.xpath("//table"); if tables.count < 1 { return nil }
            return tables.map { TableTag(tag: $0) }
        }
    }

    private struct _Error: Error {

        private var localizedDescription: String

        fileprivate init(_ desc: String) { self.localizedDescription = desc }
    }

}

extension NSDataDetector {

    convenience init(types: NSTextCheckingResult.CheckingType) throws {
        try self.init(types: types.rawValue)
    }
}

//public struct MetaTag {
//
//    public var key: String
//
//    public var content: String?
//
//    fileprivate init?(tag: Element) {
//        guard let key = tag.hasAttr("name") ? try? tag.attr("name") : try? tag.attr("property") else {
//            return nil
//        }
//
//        self.key = key
//        self.content = tag.hasAttr("content") ? try? tag.attr("content") : nil
//    }
//}
//
//// TODO: Parse this
//public struct TableTag {
//
//    var element: Element
//
//    var className: String? {
//        return try? element.className()
//    }
//
//    var internalTables: [TableTag] {
//        guard let internalTables = try? self.element.select("table") else { return [] }
//        return internalTables.map { return TableTag(element: $0) }
//    }
//}
//
///*
// Seems like on the MediaWiki the nav box has these classes inside that indeicate the links we need
//
// nowraplinks navbox-subgroup
// */
//
///*
// RawPage -> ParsedPage -> JSON
//
// * RawPage is just the URL and the SwiftSoup.Document
//
// * ParsedPage - [MetaTags], [TableElements], [ImportantInfo]
//
// * JSON, is the savable version of the Page
//
// */
//
//public class ParsedPage: CustomStringConvertible, Hashable {
//
//    private var rawValue: RawPage
//
//    private var rawTitle: String /* So we know its a valid WebPage */
//
//    private var rawMetaData: Elements? /* Meta tags on MediaWiki are helpful */
//
//    private var rawBody: Element?
//
//    public var metaTags: [MetaTag] {
//        guard let rawData = self.rawMetaData else { return [] }
//        return rawData.map { MetaTag(tag: $0) }.filter { $0 != nil }.flatMap { $0! }
//    }
//
//    public var tableTags: [TableTag] {
//        guard let body = self.rawBody else { return [] }
//        return (try? body.select("table").map { TableTag(element: $0) }) ?? []
//    }
//
//    public var navBox: TableTag? {
//        guard let idx = self.tableTags.index(where: { $0.className == "navbox" }) else { return nil }
//        return tableTags[idx]
//    }
//
//    public var actualTitle: String {
//        guard let idx = self.metaTags.index(where: { $0.key == "og:title" }) else { return rawTitle }
//        return self.metaTags[idx].content ?? rawTitle
//    }
//
//    public var isMediaWiki: Bool {
//        guard let idx = self.metaTags.index(where: { $0.key == "generator" }) else { return false }
//        return self.metaTags[idx].content?.contains("MediaWiki") ?? false
//    }
//
//    public var hasBody: Bool {
//        return rawBody != nil
//    }
//
//    internal init(rawValue: RawPage) throws {
//        self.rawValue = rawValue
//
//        self.rawTitle = try self.rawValue.document.title()
//        self.rawMetaData = try self.rawValue.document.head()?.select("meta")
//        self.rawBody = self.rawValue.document.body()
//    }
//
//    public func links() -> Set<String> {
//        let navboxSubgroup = self.navBox?.internalTables.filter { $0.className != "nowraplinks navbox-subgroup" }
//
//        /* Find all the links in the table */
//        var urls: [String] = []
//        navboxSubgroup?.forEach { table in
//            if let links = try? table.element.select("a") {
//                for link in links {
//                    guard let href = try? link.attr("href") else { continue }
//                    urls.append(href)
//                }
//            }
//        }
//
//        return Set<String>(urls)
//    }
//
//    public var description: String {
//        return self.actualTitle
//    }
//
//    public var hashValue: Int {
//        return self.rawValue.hashValue
//    }
//
//    public static func ==(lhs: ParsedPage, rhs: ParsedPage) -> Bool {
//        return lhs.rawValue == rhs.rawValue
//    }
//}
//
//func hrefIsValid(_ href: String) -> Bool {
//    return !(href.isEmpty && href.contains("redlink") || href.contains("index.php") || href.contains("Template:MLG_Navbox"))
//}
//
//// TODO: - Better Checks here
//func buildURL(from oldURL: URL, and href: String?) -> URL? {
//    guard let href = href,
//        hrefIsValid(href),
//        var comps = URLComponents(url: oldURL, resolvingAgainstBaseURL: true)
//        else {
//            return nil
//    }
//    comps.path = href
//    return comps.url
//}

