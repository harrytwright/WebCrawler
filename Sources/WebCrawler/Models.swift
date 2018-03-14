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

