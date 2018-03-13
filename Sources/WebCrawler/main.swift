import Foundation
import SystemConfiguration

// TODO: ME
/* Clean this up */

let s = DispatchSemaphore(value: 0)

/* Will look towards concurrency at one point */

let urlOption = StringOption("u", "url", true, "The URL for the Web Crawler to start on")
let verboseOption = BoolOption("v", "verbose", false, "Sets the logging tool - defaults to false")
let maxPagesOption = IntOption(nil, "max", false, "The max number of pages to be visited - defaults to Int.max")
let userAgentOption = StringOption(nil, "user", false, "The user agent to be used")
let intervalOption = IntOption("i", "interval", false, "The time (ms) between requests - defaults to 1000")

let commandLine = CommandLine()
commandLine.addOptions(urlOption, verboseOption, maxPagesOption, userAgentOption, intervalOption)
do {
    try commandLine.parse()
} catch {
    commandLine.printUsage()
    exit(EXIT_FAILURE)
}

var crawler: Crawler!

/**
 Final API

 ```bash
 webcrawler -u <url> -g Call-Of-Duty --season 2018 --user
 ```
 */
func run() {
    guard let urlValue = urlOption.value,
        let url = URL(string: urlValue)
        else { Log.error("The URL supplied is not valid"); exit(1) }

    let maxPages = maxPagesOption.value ?? Int.max
    Logger.global.verbose = verboseOption.value
    let ua = userAgentOption.value ?? kDefaultUserAgent
    let ti = intervalOption.value ?? 1000

    crawler = Crawler(startURL: url, userAgent: ua, maxPagesToVist: maxPages, timeInterval: ti, semaphore: s)

    Log.default(verboseOption.value ? "Starting to crawl as \(ua)\n" : "Starting to crawl\n")
    crawler.crawl()
}

let date = Date()
run()

s.wait()

let finish = Date().timeIntervalSince(date)
Log.default("Took \(finish) to complete, and processed \(crawler.pagesVisited.count) pages")

let previousFinishTime = kUserDefault.exists(kTimeTakenKey) ? kUserDefault.double(forKey: kTimeTakenKey) : 0
let previousProcessedAmount = kUserDefault.exists(kProcessedAmount) ? kUserDefault.integer(forKey: kProcessedAmount) : 0

kUserDefault.set(finish, forKey: kTimeTakenKey)
kUserDefault.set(crawler.pagesVisited.count, forKey: kProcessedAmount)

exit(EXIT_SUCCESS)

