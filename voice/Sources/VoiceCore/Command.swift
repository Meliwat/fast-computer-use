import Foundation
public enum Action: String, Codable, CaseIterable, Sendable {
    case openApp, createNote, titleNote, searchWeb, openURL, takePhoto
    case newChat, newTab, newDocument
    case typeText, clickControl, focusControl, dismissMenu, sendDraft, browserAction
}
public struct Command: Equatable, Codable, Sendable {
    public let action: Action
    public let value: String
    public init(_ action: Action, _ value: String = "") { self.action = action; self.value = value }
}
public enum Parser {
    public static let defaultApps = ["codex":"com.openai.codex", "notes":"com.apple.Notes", "photo booth":"com.apple.PhotoBooth", "photobooth":"com.apple.PhotoBooth", "safari":"com.apple.Safari", "arc":"company.thebrowser.Browser", "chrome":"com.google.Chrome", "google chrome":"com.google.Chrome", "calculator":"com.apple.calculator", "textedit":"com.apple.TextEdit", "text edit":"com.apple.TextEdit"]
    private enum Rule: String, CaseIterable {
        case split = #"(?:[,;]?\s+(?:and then|then|and)\s+|[.!?]\s+)(?=(?:can you |please |let's )?(?:open|launch|start|create|make|search|google|take|set|visit|go to|navigate|new|type|dictate|click|press|focus|send|submit|fill|select|choose|check|uncheck|scroll|close|dismiss|cancel|show|expand|copy|convert|change|uppercase|lowercase)\b)"#
        case fill = #"^fill\s+(?:the\s+)?(.+?)\s+(?:with|to)\s+(.+)$"#
        case copyText = #"^copy\s+(?:the\s+)?(?:text\s+(?:from|in)\s+(?:the\s+)?)?(.+?)\s+(?:into|to)\s+(?:the\s+)?(.+?)[.!?]?$"#
        case changeCase = #"^(?:make|convert|change)\s+(?:the\s+)?(?:text\s+in\s+(?:the\s+)?)?(.+?)\s+(?:to\s+)?(?:all\s+)?(upper\s*case|lower\s*case)[.!?]?$"#
        case caseFirst = #"^(uppercase|lowercase)\s+(?:the\s+)?(?:text\s+in\s+(?:the\s+)?)?(.+?)[.!?]?$"#
        case openMenu = #"^(?:open|show|expand)\s+(?:the\s+)?(.+?\s+menu)[.!?]?$"#
        case dismissMenu = #"^(?:close|dismiss|cancel)\s+(?:the\s+)?menu[.!?]?$"#
        case focus = #"^focus\s+(?:on\s+)?(?:the\s+)?(.+?)[.!?]?$"#
        case select = #"^(?:select|choose)\s+(.+?)\s+(?:from|in)\s+(?:the\s+)?(.+?)(?:\s+(?:dropdown|menu))?[.!?]?$"#
        case check = #"^(check|uncheck)\s+(?:the\s+)?(.+?)(?:\s+(?:checkbox|box))?[.!?]?$"#
        case siteSearch = #"^search\s+(?:this|the)\s+(?:site|page|website)\s+for\s+(.+)$"#
        case scroll = #"^scroll\s+(up|down)[.!?]?$"#
        case switchTab = #"^(?:switch to (?:the )?)?(next|previous)\s+tab[.!?]?$"#
        case dictationStart = #"^(?:type|dictate)(?:\s|$)"#
        case dictation = #"^(?:type|dictate)(?:\s+(?:this|the following)\s*:\s*|\s+)(.+)$"#
        case browserClick = #"^(?:click|press)\s+(?:the\s+)?(.+?)[.!?]?$"#
        case click = #"^(?:click|press)\s+(?:the\s+)?(.+?)(?:\s+button)?[.!?]?$"#
        case send = #"^(?:send (?:it|that|the message)|submit (?:it|the prompt))[.!?]?$"#
        case punctuation = #"^[.,!?]+\s*"#
        case polite = #"^(?:(?:alright|okay|ok|great|now)[,.]?\s+)*(?:(?:can|could|would) you\s+)?(?:please\s+)?(?:let's\s+)?"#
        case negative = #"\b(?:don't|do not|never|actually)\b"#
        case chat = #"^(?:(?:open|start|create|make)\s+)?(?:a\s+)?(?:new|fresh)\s+(?:chat|conversation|thread)(?:\s+(?:in|on)\s+(.+?))?[.!?]?$"#
        case tab = #"^(?:(?:open|start|create|make)\s+)?(?:a\s+)?new\s+tab(?:\s+in\s+(.+?))?[.!?]?$"#
        case document = #"^(?:(?:open|start|create|make)\s+)?(?:a\s+)?new\s+(?:document|text file)(?:\s+in\s+(.+?))?[.!?]?$"#
        case website = #"^(?:visit|go to|navigate to|take me to|browse to|open (?:the )?(?:website|site))\s+(.+?)[.!?]?$"#
        case app = #"^(?:open|launch|switch to|bring up|pull up)\s+(?:up\s+)?(?:the\s+)?(.+?)(?:\s+app|\s+browser)?(?:\s+for me)?[.!?]?$"#
        case note = #"^(?:create|make)\s+(?:a\s+)?(?:new\s+)?note(?:\s+(?:called|titled|named|with (?:the )?title)\s+(.+?))?[.!?]?$"#
        case title = #"^(?:set (?:the )?title to|make (?:the )?title (?:say|be)|title (?:it|the note))\s+(.+)$"#
        case search = #"^(?:google(?: search)?|search(?: (?:google|the web))?(?: for)?|look up)\s+(.+)$"#
        case photo = #"^(?:take|snap)\s+(?:a\s+)?(?:picture|photo)(?:\s+of me)?[.!?]?$"#
    }
    // Immutable compiled patterns are shared across utterances.
    private static let regex = Dictionary(uniqueKeysWithValues: Rule.allCases.map { ($0, try! NSRegularExpression(pattern: $0.rawValue, options: .caseInsensitive)) })
    private static func replace(_ rule: Rule, _ text: String, _ replacement: String = "") -> String {
        regex[rule]!.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
    private static func match(_ rule: Rule, _ text: String) -> [String]? {
        guard let m = regex[rule]!.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
    public static func parts(_ input: String) -> [String] {
        var remaining = replace(.punctuation, input.trimmingCharacters(in: .whitespacesAndNewlines))
        var pieces: [String] = []
        while !remaining.isEmpty {
            // Dictation consumes the rest literally, even “and send it”. Submission
            // must be a separate utterance, never inferred from dictated content.
            if [.dictation, .fill, .siteSearch, .search].contains(where: { match($0, replace(.polite, remaining)) != nil }) { pieces.append(remaining); break }
            guard let delimiter = regex[.split]!.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                  let range = Range(delimiter.range, in: remaining) else { pieces.append(remaining); break }
            pieces.append(String(remaining[..<range.lowerBound]))
            remaining = String(remaining[range.upperBound...])
        }
        return pieces
    }
    public static func hasDictation(_ input: String) -> Bool {
        parts(input).contains { part in
            let text = replace(.polite, part)
            return [.dictationStart, .fill, .siteSearch, .search].contains { match($0, text) != nil }
        }
    }
    public static func parse(_ input: String, apps: [String: String] = defaultApps, browserContext: Bool = false) -> [Command] {
        let pieces = parts(input)
        let commands = pieces.compactMap { single($0, apps: apps, browserContext: browserContext) }
        // Never silently execute the supported half of an unsupported sequence.
        guard commands.count == pieces.count else { return [] }
        var target: String?
        return commands.map { command in
            if command.action == .openApp { target = command.value }
            if command.value.isEmpty, [.newChat, .newTab, .newDocument].contains(command.action), let target {
                return Command(command.action, target)
            }
            return command
        }
    }
    private static func single(_ raw: String, apps: [String: String], browserContext: Bool) -> Command? {
        let text = replace(.polite, replace(.punctuation, raw.trimmingCharacters(in: .whitespacesAndNewlines)))
        if let m = match(.dictation, text) { return Command(.typeText, m[0]) }
        if let m = match(.fill,text) { return BrowserCommand(op:"fill",target:m[0],value:m[1]).command }
        if let m = match(.siteSearch,text) { return BrowserCommand(op:"search",value:m[0]).command }
        guard match(.negative, text) == nil else { return nil }
        if let m=match(.copyText,text) {
            let command=BrowserCommand(op:"copyText",target:m[1],source:m[0])
            return (try? ExistingTextOperation(command:command)) != nil ? command.command : nil
        }
        if let m=match(.changeCase,text) {
            let command=BrowserCommand(op:"changeCase",target:m[0],value:m[1].lowercased().replacingOccurrences(of:" ",with:""))
            return (try? ExistingTextOperation(command:command)) != nil ? command.command : nil
        }
        if let m=match(.caseFirst,text) {
            let command=BrowserCommand(op:"changeCase",target:m[1],value:m[0].lowercased())
            return (try? ExistingTextOperation(command:command)) != nil ? command.command : nil
        }
        if !browserContext,match(.dismissMenu,text) != nil {return Command(.dismissMenu)}
        if !browserContext,let m=match(.openMenu,text) {return Command(.clickControl,m[0])}
        if !browserContext,let m=match(.focus,text) {return Command(.focusControl,m[0])}
        if let m = match(.select,text) { return BrowserCommand(op:"select",target:m[1],value:m[0]).command }
        if let m = match(.check,text) { return BrowserCommand(op:"check",target:m[1],checked:m[0].lowercased()=="check").command }
        if let m = match(.scroll,text) { return BrowserCommand(op:"scroll",value:m[0].lowercased()).command }
        if let m = match(.switchTab,text) { return BrowserCommand(op:m[0].lowercased()=="next" ? "nextTab" : "previousTab").command }
        if match(.send, text) != nil { return Command(.sendDraft) }
        if let m = match(browserContext ? .browserClick : .click, text) { return Command(.clickControl, m[0]) }
        for (rule, action) in [(Rule.chat, Action.newChat), (.tab, .newTab), (.document, .newDocument)] {
            if let m = match(rule, text) {
                if m[0].isEmpty { return Command(action) }
                guard let id = apps[m[0].lowercased()] else { return nil }
                return Command(action, id)
            }
        }
        if let m = match(.website, text), let url = WebDestination.resolve(m[0]) { return Command(.openURL, url) }
        if let m = match(.app, text) {
            let name = m[0].lowercased().trimmingCharacters(in: .whitespaces)
            if let id = apps[name] { return Command(.openApp, id) }
            if ["browser", "my browser", "web browser"].contains(name) { return Command(.openURL, "https://www.google.com") }
            if let url = WebDestination.resolve(m[0]) { return Command(.openURL, url) }
            return nil
        }
        if let m = match(.note, text) { return Command(.createNote, m[0]) }
        if let m = match(.title, text) { return Command(.titleNote, m[0]) }
        if let m = match(.search, text) {
            let explicitWeb = text.range(of:#"^(?:google|search (?:google|the web))\b"#,options:[.regularExpression,.caseInsensitive]) != nil
            return browserContext && !explicitWeb ? BrowserCommand(op:"search",value:m[0]).command : Command(.searchWeb,m[0])
        }
        if match(.photo, text) != nil { return Command(.takePhoto) }
        return nil
    }
}
/// Stable-prefix activation only; all mutations wait for a final transcript.
public struct Scheduler {
    private var candidate: Command?
    private var since: TimeInterval = 0
    private var early: [Command] = []
    public init() {}
    public mutating func reset() { candidate = nil; since = 0; early = [] }
    public mutating func update(_ text: String, final: Bool, now: TimeInterval, apps: [String: String] = Parser.defaultApps, browserContext: Bool = false) -> [Command] {
        let partial = final ? text : text.replacingOccurrences(of: #"\s+and(?:\s+.*)?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let commands = Parser.parse(partial, apps: apps, browserContext: browserContext)
        if final {
            var remaining = commands
            for item in early { if let i = remaining.firstIndex(of: item) { remaining.remove(at: i) } }
            reset(); return remaining
        }
        guard !text.lowercased().contains("actually"), let first = commands.first, first.action == .openApp, !early.contains(first) else { candidate = nil; return [] }
        if candidate != first { candidate = first; since = now; return [] }
        if now - since >= 0.45 { early.append(first); return [first] }
        return []
    }
}
