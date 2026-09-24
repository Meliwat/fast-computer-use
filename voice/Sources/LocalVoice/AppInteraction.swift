import AppKit
import ApplicationServices
import VoiceCore

/// Native accessibility operations, scoped to one foreground app and window.
@MainActor final class AppInteraction {
    private struct Draft {
        let app: String
        let field: AXUIElement
        let value: String
        let window: AXUIElement
    }
    private var draft: Draft?
    private var previousField: AXUIElement?
    private var needsNewField = false
    private var prompted = false
    private let menus=NativeMenus()
    private var nativeBinding: (command:BrowserCommand,snapshot:NativeSnapshot)?
    private func fail(_ message: String) -> NSError { NSError(domain:"LocalVoiceControl", code:1, userInfo:[NSLocalizedDescriptionKey:message]) }
    func clearDraft() { draft = nil; nativeBinding=nil }
    func beginUtterance(app: String?) {
        if draft?.app != app { draft = nil }
        previousField = nil; needsNewField = false
        nativeBinding=nil
    }
    func beginNavigation() {
        draft = nil
        nativeBinding=nil
        previousField = focusedField()
        needsNewField = true
    }
    private func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func element(_ node: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = attribute(node, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func focusedField() -> AXUIElement? { element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) }
    private func ensureAccess() throws {
        guard AXIsProcessTrusted() else {
            if !prompted {
                prompted = true
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
            }
            throw fail("Enable Local Voice in System Settings → Privacy & Security → Accessibility")
        }
    }
    private func appRoot(_ id: String) throws -> AXUIElement {
        try ensureAccess()
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == id else { throw fail("App focus changed. Hold Option again in the intended app.") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        return root
    }
    private func editable(_ node: AXUIElement) -> Bool {
        let role = attribute(node,kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(node,kAXSubroleAttribute) as? String ?? ""
        return [kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role) && subrole != kAXSecureTextFieldSubrole && attribute(node,"AXProtectedContent") as? Bool != true
    }
    private func selectedRange(_ node: AXUIElement) -> NSRange? {
        guard let raw = attribute(node,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location:range.location, length:range.length)
    }
    private func canSet(_ node: AXUIElement, _ key: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(node,key as CFString,&settable) == .success && settable.boolValue
    }
    private func textLabels(_ node: AXUIElement) -> [String] {
        var values=labels(node)
        if let placeholder=attribute(node,"AXPlaceholderValue") as? String { values.append(placeholder) }
        if let title=element(node,"AXTitleUIElement"),attribute(title,kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
           attribute(title,"AXProtectedContent") as? Bool != true {
            values += [kAXTitleAttribute,kAXDescriptionAttribute].compactMap { attribute(title,$0) as? String }
            // AppKit can expose an explicitly linked caption as AXUnknown.
            // The label relation and read-only value matter, not its role name.
            if !canSet(title,kAXValueAttribute),let value=attribute(title,kAXValueAttribute) as? String {values.append(value)}
        }
        return values.filter {!$0.isEmpty}.map {String($0.prefix(300))}
    }
    private func visibleTextPoint(_ field: AXUIElement, window: AXUIElement) -> CGPoint? {
        guard attribute(field,"AXHidden") as? Bool != true,let rect=bounds(field),let frame=bounds(window) else { return nil }
        let visible=rect.intersection(frame)
        guard !visible.isNull,visible.width>1,visible.height>1 else { return nil }
        return CGPoint(x:visible.midX,y:visible.midY)
    }
    private func sameTextContext(_ field: AXUIElement, window: AXUIElement, app: String, stillValid: () -> Bool) -> Bool {
        guard stillValid(),(try? menus.hasActiveMenu(app:app)) == false,let root=try? appRoot(app),let currentWindow=element(root,kAXFocusedWindowAttribute),CFEqual(currentWindow,window),
              let focused=focusedField(),CFEqual(focused,field),editable(field),attribute(field,kAXEnabledAttribute) as? Bool != false,
              let point=visibleTextPoint(field,window:window),hitTest(field,point:point) else { return false }
        return true
    }
    private func verifyText(_ field: AXUIElement, window: AXUIElement, app: String, before: String, expected: String, stillValid: () -> Bool) async throws {
        var check=NativeTextVerification(before:before,expected:expected,startedAt:ProcessInfo.processInfo.systemUptime)
        while true {
            let context=sameTextContext(field,window:window,app:app,stillValid:stillValid)
            switch check.observe(value:context ? attribute(field,kAXValueAttribute) as? String : nil,sameContext:context,at:ProcessInfo.processInfo.systemUptime) {
            case .verified: return
            case .failed: throw fail("Text changed, focus moved, or insertion could not be verified; not retrying")
            case .waiting: try await Task.sleep(nanoseconds:20_000_000)
            }
        }
    }
    private func textSnapshot(app:String,stillValid:()->Bool) throws -> (root:AXUIElement,window:AXUIElement,nodes:[AXUIElement],candidates:[NativeTextTarget.Candidate]) {
        guard !InteractionRules.blockedTypingApps.contains(app) else { throw fail("Terminal dictation is not supported") }
        let root=try appRoot(app)
        guard try !menus.hasActiveMenu(app:app) else {throw fail("Close the menu before filling a field")}
        guard let window=element(root,kAXFocusedWindowAttribute) else { throw fail("No focused window") }
        let sheets=attribute(window,"AXSheets") as? [AXUIElement] ?? []
        guard sheets.count<=1 else { throw fail("Choose the intended dialog first") }
        var stack=[sheets.first ?? window],nodes=[AXUIElement](),candidates=[NativeTextTarget.Candidate](),visited=0
        let deadline=ProcessInfo.processInfo.systemUptime+0.35
        while let node=stack.popLast() {
            visited+=1
            guard stillValid(),visited<=2000,ProcessInfo.processInfo.systemUptime<deadline else { throw fail("Could not identify one native field quickly") }
            if attribute(node,"AXHidden") as? Bool == true { continue }
            let role=attribute(node,kAXRoleAttribute) as? String ?? ""
            if [kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role),!nodes.contains(where:{CFEqual($0,node)}) {
                nodes.append(node)
                let visible=visibleTextPoint(node,window:window).map {hitTest(node,point:$0)} ?? false
                candidates.append(.init(labels:textLabels(node),visible:visible,
                    enabled:attribute(node,kAXEnabledAttribute) as? Bool != false,secure:!editable(node),writable:canSet(node,kAXValueAttribute)))
            }
            stack.append(contentsOf:attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return (root,window,nodes,candidates)
    }
    /// Fill one current native field by its label. No key events, paste or submit.
    func fill(_ target: String, text: String, app: String, stillValid: () -> Bool) async throws -> String {
        let (root,window,nodes,candidates)=try textSnapshot(app:app,stillValid:stillValid)
        draft=nil
        guard let index=NativeTextTarget.uniqueIndex(target:target,candidates:candidates) else { throw fail("Could not identify one visible, writable field named ‘\(target)’") }
        let field=nodes[index]
        guard stillValid(),let currentWindow=element(root,kAXFocusedWindowAttribute),CFEqual(currentWindow,window),
              let point=visibleTextPoint(field,window:window),hitTest(field,point:point),
              let before=attribute(field,kAXValueAttribute) as? String else { throw fail("Native field is hidden or changed") }
        if let focused=focusedField(),CFEqual(focused,field) {} else {
            guard canSet(field,kAXFocusedAttribute),AXUIElementSetAttributeValue(field,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else { throw fail("This field could not receive focus") }
            let focusDeadline=ProcessInfo.processInfo.systemUptime+0.12
            while focusedField().map({CFEqual($0,field)}) != true && ProcessInfo.processInfo.systemUptime<focusDeadline {
                guard stillValid() else { throw fail("Cancelled before filling") }
                try await Task.sleep(nanoseconds:20_000_000)
            }
        }
        let current=NativeTextTarget.Candidate(labels:textLabels(field),visible:true,enabled:attribute(field,kAXEnabledAttribute) as? Bool != false,
                                             secure:!editable(field),writable:canSet(field,kAXValueAttribute))
        guard sameTextContext(field,window:window,app:app,stillValid:stillValid),
              NativeTextTarget.uniqueIndex(target:target,candidates:[current])==0,
              attribute(field,kAXValueAttribute) as? String==before else { throw fail("Field or focus changed before filling; no text sent") }
        if before != text {
            guard AXUIElementSetAttributeValue(field,kAXValueAttribute as CFString,text as CFString) == .success else { throw fail("Field refused the fill; not retrying") }
            if canSet(field,kAXSelectedTextRangeAttribute) {
                var cursor=CFRange(location:(text as NSString).length,length:0)
                if let value=AXValueCreate(.cfRange,&cursor) {_=AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,value)}
            }
        }
        try await verifyText(field,window:window,app:app,before:before,expected:text,stillValid:stillValid)
        needsNewField=false;previousField=nil
        draft=Draft(app:app,field:field,value:text,window:window)
        return before==text ? "Field already matches · text verified" : "Field filled · text verified"
    }
    func editExistingText(_ operation:ExistingTextOperation,app:String,stillValid:()->Bool) async throws -> String {
        let first=try textSnapshot(app:app,stillValid:stillValid)
        draft=nil
        guard let si=NativeTextTarget.uniqueIndex(target:operation.source,candidates:first.candidates,requireWritable:false),
              let ti=NativeTextTarget.uniqueIndex(target:operation.target,candidates:first.candidates) else {throw fail("Could not identify one source and one writable destination field")}
        let source=first.nodes[si],target=first.nodes[ti],window=first.window
        guard let original=attribute(source,kAXValueAttribute) as? String,
              let before=attribute(target,kAXValueAttribute) as? String,before.utf16.count<=16000 else {throw fail("The field text is unavailable or too long")}
        let expected=try operation.applying(to:original)
        let sourceLabels=textLabels(source),targetLabels=textLabels(target)
        guard stillValid() else {throw fail("Cancelled before editing")}
        if focusedField().map({CFEqual($0,target)}) != true {
            guard canSet(target,kAXFocusedAttribute),AXUIElementSetAttributeValue(target,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else {throw fail("The destination could not receive focus")}
            let deadline=ProcessInfo.processInfo.systemUptime+0.12
            while focusedField().map({CFEqual($0,target)}) != true && ProcessInfo.processInfo.systemUptime<deadline {
                guard stillValid() else {throw fail("Cancelled before editing")}
                try await Task.sleep(nanoseconds:20_000_000)
            }
        }
        let fresh=try textSnapshot(app:app,stillValid:stillValid)
        guard CFEqual(fresh.window,window),
              let sourceIndex=NativeTextTarget.uniqueIndex(target:operation.source,candidates:fresh.candidates,requireWritable:false),CFEqual(fresh.nodes[sourceIndex],source),
              let targetIndex=NativeTextTarget.uniqueIndex(target:operation.target,candidates:fresh.candidates),CFEqual(fresh.nodes[targetIndex],target),
              sameTextContext(target,window:window,app:app,stillValid:stillValid),
              attribute(source,kAXValueAttribute) as? String==original,attribute(target,kAXValueAttribute) as? String==before else {throw fail("Source or destination changed before editing; no text sent")}
        if before != expected {
            guard AXUIElementSetAttributeValue(target,kAXValueAttribute as CFString,expected as CFString) == .success else {throw fail("Destination refused the edit; not retrying")}
        }
        try await verifyText(target,window:window,app:app,before:before,expected:expected,stillValid:{
            guard stillValid(),self.textLabels(target)==targetLabels else {return false}
            if CFEqual(source,target) {return true}
            return self.editable(source) && self.attribute(source,kAXEnabledAttribute) as? Bool != false &&
                self.visibleTextPoint(source,window:window).map {self.hitTest(source,point:$0)} == true &&
                self.textLabels(source)==sourceLabels && self.attribute(source,kAXValueAttribute) as? String==original
        })
        needsNewField=false;previousField=nil
        return before==expected ? "Field already matches · text verified" : operation.kind == .copy ? "Field copied · text verified" : "Text made \(operation.kind.rawValue) · verified"
    }
    struct SearchKeyTarget {
        let field: AXUIElement
        let window: AXUIElement
        let bounds: CGRect
        let query: String
        let pid: pid_t
        let expires: TimeInterval
    }
    private func searchFieldIsValid(_ field: AXUIElement, query: String) -> Bool {
        guard editable(field),
              [kAXTextFieldRole,kAXComboBoxRole].contains(attribute(field,kAXRoleAttribute) as? String ?? ""),
              attribute(field,kAXEnabledAttribute) as? Bool != false,
              attribute(field,kAXValueAttribute) as? String == query else { return false }
        // Exclude browser chrome (including the address bar). Only a web field may submit.
        var node: AXUIElement? = field
        for _ in 0..<32 {
            guard let current=node else { break }
            if attribute(current,kAXRoleAttribute) as? String == "AXWebArea" { return true }
            node=element(current,kAXParentAttribute)
        }
        return false
    }
    func prepareSearchKey(query: String) throws -> SearchKeyTarget {
        let root=try appRoot("com.google.Chrome")
        guard let field=focusedField(),searchFieldIsValid(field,query:query),
              let window=element(root,kAXFocusedWindowAttribute),let rect=bounds(field),
              let pid=NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            throw fail("Search text is ready, but its focused web field could not be confirmed; press Enter manually")
        }
        return SearchKeyTarget(field:field,window:window,bounds:rect,query:query,pid:pid,expires:ProcessInfo.processInfo.systemUptime+1)
    }
    func submitSearchKey(_ target: SearchKeyTarget, stillValid: () -> Bool) throws {
        let root=try appRoot("com.google.Chrome")
        guard stillValid(),ProcessInfo.processInfo.systemUptime<target.expires,
              NSWorkspace.shared.frontmostApplication?.processIdentifier==target.pid,
              let window=element(root,kAXFocusedWindowAttribute),CFEqual(window,target.window),
              let field=focusedField(),CFEqual(field,target.field),bounds(field)==target.bounds,
              searchFieldIsValid(field,query:target.query),CGPreflightPostEventAccess(),
              let down=CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:true),
              let up=CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:false) else {
            throw fail("Search focus changed or keyboard access is unavailable; no Enter sent")
        }
        down.flags=[];up.flags=[]
        down.postToPid(target.pid);up.postToPid(target.pid)
    }
    func type(_ text: String, app: String, stillValid: () -> Bool) async throws -> String {
        try ensureAccess()
        guard !InteractionRules.blockedTypingApps.contains(app) else { throw fail("Terminal dictation is not supported") }
        try requireNoMenu(app:app)
        // After navigation, wait for a new field rather than writing into the old composer.
        let deadline = Date().addingTimeInterval(1.5)
        var field: AXUIElement?
        repeat {
            guard stillValid() else { throw fail("Cancelled") }
            _ = try appRoot(app)
            if let candidate = focusedField(), editable(candidate),
               !needsNewField || previousField == nil || !CFEqual(candidate, previousField!) { field = candidate; break }
            try await Task.sleep(nanoseconds:30_000_000)
        } while Date() < deadline
        guard let field else { throw fail("Click the intended text field, then say ‘type …’") }
        needsNewField = false; previousField = nil
        guard let before = attribute(field,kAXValueAttribute) as? String,
              let range = selectedRange(field), let expected = InteractionRules.inserting(text, into:before, selection:range) else { throw fail("This field does not expose its text and cursor position") }
        let root = try appRoot(app)
        guard let window = element(root,kAXFocusedWindowAttribute) else { throw fail("No focused window") }
        guard sameTextContext(field,window:window,app:app,stillValid:stillValid) else { throw fail("Focus changed or text field is hidden") }
        draft = nil
        var restoreClipboard: (() -> Void)?
        defer { restoreClipboard?() }
        if canSet(field,kAXSelectedTextAttribute) {
            guard AXUIElementSetAttributeValue(field,kAXSelectedTextAttribute as CFString,text as CFString) == .success else { throw fail("Field refused dictation") }
        } else if canSet(field,kAXValueAttribute) {
            guard AXUIElementSetAttributeValue(field,kAXValueAttribute as CFString,expected as CFString) == .success else { throw fail("Field refused dictation") }
            var cursor = CFRange(location:range.location + (text as NSString).length,length:0)
            if let value = AXValueCreate(.cfRange,&cursor) { _ = AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,value) }
        } else {
            restoreClipboard = try paste(text, root: root, app: app, field:field, window:window, stillValid:stillValid)
        }
        try await verifyText(field,window:window,app:app,before:before,expected:expected,stillValid:stillValid)
        draft = Draft(app:app,field:field,value:expected,window:window)
        return "Text inserted · say ‘send it’ to submit"
    }
    private func paste(_ text: String, root: AXUIElement, app: String, field:AXUIElement, window:AXUIElement, stillValid:()->Bool) throws -> () -> Void {
        guard let menu = element(root,kAXMenuBarAttribute) else { throw fail("This app does not expose a Paste command") }
        var stack = [menu], matches: [AXUIElement] = [], visited = 0
        let deadline = Date().addingTimeInterval(0.3)
        while let node = stack.popLast() {
            visited += 1
            guard visited <= 1200, Date() < deadline else { throw fail("Could not identify Paste quickly") }
            if attribute(node,kAXRoleAttribute) as? String == kAXMenuItemRole,
               attribute(node,kAXTitleAttribute) as? String == "Paste",
               attribute(node,kAXEnabledAttribute) as? Bool == true { matches.append(node) }
            stack.append(contentsOf: attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        guard matches.count == 1 else { throw fail("This field has no unique Paste command") }
        guard sameTextContext(field,window:window,app:app,stillValid:stillValid) else { throw fail("Focus changed before paste; no text sent") }
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues:item.types.compactMap { type in item.data(forType:type).map { (type,$0) } })
        }
        clipboard.clearContents(); clipboard.setString(text,forType:.string)
        let ownChange = clipboard.changeCount
        let result = AXUIElementPerformAction(matches[0],kAXPressAction as CFString)
        // Caller restores after insertion read-back, unless another app copied meanwhile.
        let restore = {
            guard clipboard.changeCount == ownChange else { return }
            let items = saved.map { values in
                let item = NSPasteboardItem()
                for (type,data) in values { item.setData(data,forType:type) }
                return item
            }
            clipboard.clearContents(); clipboard.writeObjects(items)
        }
        guard result == .success else { restore(); throw fail("Paste command refused the action") }
        return restore
    }
    private func controls(in root: AXUIElement, labels wanted: Set<String>) throws -> [AXUIElement] {
        var stack = [root], matches: [AXUIElement] = []
        var visited = 0
        let deadline = Date().addingTimeInterval(0.35)
        while let node = stack.popLast() {
            visited += 1
            guard visited <= 2000, Date() < deadline else { throw fail("Too many controls to identify a unique target quickly") }
            let role = attribute(node,kAXRoleAttribute) as? String ?? ""
            if [kAXButtonRole,"AXLink",kAXCheckBoxRole,kAXRadioButtonRole].contains(role),
               attribute(node,kAXEnabledAttribute) as? Bool != false {
                let labels = [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { attribute(node,$0) as? String }
                if !InteractionRules.matchingIndices(labels:[labels],enabled:[true],wanted:wanted).isEmpty { matches.append(node) }
            }
            stack.append(contentsOf: attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return matches
    }
    struct VisualSnapshot {
        let app: String
        let window: AXUIElement
        let bounds: CGRect
        let candidates: [VisualTargetPolicy.Candidate]
        let nodes: [String:AXUIElement]
    }
    struct NativeSnapshot {
        let app:String
        let window:AXUIElement?
        let scope:AXUIElement
        let menuSnapshot:NativeMenus.Snapshot
        let focused:AXUIElement?
        let frame:CGRect
        let capturedUptime:TimeInterval
        let observation:BrowserObservation
        let nodes:[String:AXUIElement]
    }
    private func supportsPress(_ node:AXUIElement) -> Bool {
        var actions:CFArray?
        return AXUIElementCopyActionNames(node,&actions) == .success && (actions as? [String] ?? []).contains(kAXPressAction)
    }
    /// Shared wire format with the browser worker; native element references never leave Swift.
    func nativeSnapshot(app:String,identities:[String:AXUIElement]=[:]) throws -> NativeSnapshot {
        guard app != "com.google.Chrome",!InteractionRules.blockedTypingApps.contains(app) else {throw fail("Use the existing action path in this app")}
        let captured=ProcessInfo.processInfo.systemUptime,root=try appRoot(app)
        let menuSnapshot=try menus.snapshot(app:app,identities:identities)
        let window=element(root,kAXFocusedWindowAttribute)
        let sheets=window.flatMap {attribute($0,"AXSheets") as? [AXUIElement]} ?? []
        guard sheets.count<=1 else {throw fail("Choose the intended dialog first")}
        guard let scope=sheets.first ?? window ?? menuSnapshot.bar ?? menuSnapshot.openMenus.first,
              let frame=window.flatMap({bounds($0)}) ?? bounds(scope) else {throw fail("No accessible window or menu")}
        let focused=focusedField()
        var stack=menuSnapshot.active || window==nil ? [] : [scope],visited=0
        var nodes=menuSnapshot.nodes,candidates=menuSnapshot.candidates
        guard candidates.count<=48 else {throw fail("Too many current controls for the local command model")}
        while let node=stack.popLast() {
            visited+=1
            guard visited<=2000,ProcessInfo.processInfo.systemUptime-captured<0.35 else {throw fail("Native observation was incomplete; no action sent")}
            if attribute(node,"AXHidden") as? Bool == true {continue}
            let role=attribute(node,kAXRoleAttribute) as? String ?? ""
            let isText=[kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role)
            let isControl=[kAXButtonRole,"AXLink",kAXCheckBoxRole,kAXRadioButtonRole,"AXPopUpButton","AXMenuButton"].contains(role)
            if (isText || isControl),!nodes.values.contains(where:{CFEqual($0,node)}),
               let window,let rect=bounds(node),let point=visibleTextPoint(node,window:window),hitTest(node,point:point) {
                guard candidates.count<48 else {throw fail("Too many current controls for the local command model")}
                let id=identities.first(where:{CFEqual($0.value,node)})?.key ?? UUID().uuidString
                let available=attribute(node,kAXEnabledAttribute) as? Bool == true
                let writable=isText && editable(node) && (canSet(node,kAXValueAttribute) || canSet(node,kAXSelectedTextAttribute))
                // Learned activation does not infer a desired checkbox/radio state.
                // Explicit native click commands keep their existing direct path.
                let capable=isText ? writable && canSet(node,kAXFocusedAttribute) :
                    ![kAXCheckBoxRole,kAXRadioButtonRole].contains(role) && supportsPress(node)
                let state=transitionState(node)
                nodes[id]=node
                candidates.append(.init(id:id,role:isText ? "textbox" : role=="AXLink" ? "link" : "button",
                    labels:isText ? textLabels(node) : labels(node),bounds:.init(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height),
                    enabled:available && capable,editable:isText,clickable:capable,selected:state[kAXSelectedAttribute] ?? state[kAXValueAttribute],expanded:state[kAXExpandedAttribute]))
            }
            stack.append(contentsOf:attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        let focusedID=focused.flatMap {element in nodes.first(where:{CFEqual($0.value,element)})?.key}
        let observation=BrowserObservation(documentId:"native:"+UUID().uuidString,observationId:UUID().uuidString,origin:"app:"+app,
            capturedAt:Date().timeIntervalSince1970*1000,viewport:.init(width:frame.width,height:frame.height,scale:1),focusedId:focusedID,candidates:candidates)
        return NativeSnapshot(app:app,window:window,scope:scope,menuSnapshot:menuSnapshot,focused:focused,frame:frame,capturedUptime:captured,observation:observation,nodes:nodes)
    }
    func bindNative(_ command:BrowserCommand,to snapshot:NativeSnapshot) throws {
        nativeBinding=nil
        guard command.op=="click",command.target==nil,command.value==nil,command.checked==nil,command.token==nil,
              command.documentId==snapshot.observation.documentId,command.observationId==snapshot.observation.observationId,
              let id=command.targetId,snapshot.nodes[id] != nil,
              snapshot.observation.candidates.contains(where:{$0.id==id && $0.enabled && $0.clickable}) else {throw fail("Invalid native control proposal")}
        nativeBinding=(command,snapshot)
    }
    func focusNative(_ name:String,app:String,stillValid:()->Bool) async throws -> String {
        let snapshot=try nativeSnapshot(app:app)
        let fields=snapshot.observation.candidates.filter(\.editable)
        let candidates=fields.map {NativeTextTarget.Candidate(labels:$0.labels,visible:true,enabled:$0.enabled,secure:false,writable:$0.clickable)}
        guard let index=NativeTextTarget.uniqueIndex(target:name,candidates:candidates) else {throw fail("Could not identify one available field named ‘\(name)’")}
        let command=BrowserCommand(op:"click",targetId:fields[index].id,documentId:snapshot.observation.documentId,observationId:snapshot.observation.observationId)
        try bindNative(command,to:snapshot)
        return try await activateNative(command,stillValid:stillValid)
    }
    /// A binding is consumed before validation or input; it can never be replayed.
    func activateNative(_ command:BrowserCommand,stillValid:()->Bool) async throws -> String {
        let prepared=nativeBinding;nativeBinding=nil
        guard let prepared,prepared.command==command,let id=command.targetId,
              let node=prepared.snapshot.nodes[id],let target=prepared.snapshot.observation.candidates.first(where:{$0.id==id}) else {throw fail("Native control proposal is missing or already used")}
        let original=prepared.snapshot
        guard stillValid(),ProcessInfo.processInfo.systemUptime-original.capturedUptime<=2 else {throw fail("Native observation expired; no action sent")}
        let current=try nativeSnapshot(app:original.app,identities:original.nodes)
        let sameFocus:Bool
        if let a=original.focused,let b=current.focused {sameFocus=CFEqual(a,b)} else {sameFocus=original.focused==nil && current.focused==nil}
        guard stillValid(),ProcessInfo.processInfo.systemUptime-original.capturedUptime<=2,
              sameElement(original.window,current.window),CFEqual(original.scope,current.scope),original.frame==current.frame,sameFocus,
              menus.sameScene(original.menuSnapshot,current.menuSnapshot),
              original.observation.candidates.sorted(by:{$0.id<$1.id})==current.observation.candidates.sorted(by:{$0.id<$1.id}) else {throw fail("Native controls changed after observation; no action sent")}
        if original.menuSnapshot.nodes[id] != nil {
            draft=nil
            return try await menus.press(id,snapshot:current.menuSnapshot,stillValid:{stillValid() && ProcessInfo.processInfo.systemUptime-original.capturedUptime<=2})
        }
        guard !current.menuSnapshot.active,let window=current.window,
              let point=visibleTextPoint(node,window:window),hitTest(node,point:point) else {throw fail("Native control is no longer visible")}

        if target.editable {
            guard AXUIElementSetAttributeValue(node,kAXFocusedAttribute as CFString,kCFBooleanTrue) == .success else {throw fail("Field refused focus")}
            draft=nil
            let start=ProcessInfo.processInfo.systemUptime
            var matched:TimeInterval?
            while ProcessInfo.processInfo.systemUptime-start<0.4 {
                guard stillValid(),NSWorkspace.shared.frontmostApplication?.bundleIdentifier==original.app else {throw fail("Focus action interrupted; not retrying")}
                if sameTextContext(node,window:window,app:original.app,stillValid:stillValid) {
                    if matched==nil {matched=ProcessInfo.processInfo.systemUptime}
                    if ProcessInfo.processInfo.systemUptime-matched!>=0.12 {
                        previousField=nil;needsNewField=false
                        return "Field focus verified"
                    }
                } else if matched != nil {throw fail("Field focus did not persist; not retrying")}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            throw fail("Field focus could not be verified; not retrying")
        }
        return try await verifiedPress(node,app:original.app,window:window,point:point,stillValid:stillValid)
    }
    private func sameElement(_ a:AXUIElement?,_ b:AXUIElement?)->Bool {
        if let a,let b {return CFEqual(a,b)}
        return a==nil && b==nil
    }
    func requireNoMenu(app:String) throws {
        guard try !menus.hasActiveMenu(app:app) else {throw fail("Choose an item in the open menu or say ‘close menu’")}
    }
    func dismissMenu(app:String,stillValid:()->Bool) async throws -> String {
        clearDraft()
        return try await menus.dismiss(app:app,stillValid:stillValid)
    }
    private func bounds(_ node: AXUIElement) -> CGRect? {
        guard let p=attribute(node,kAXPositionAttribute),CFGetTypeID(p)==AXValueGetTypeID(),
              let s=attribute(node,kAXSizeAttribute),CFGetTypeID(s)==AXValueGetTypeID() else { return nil }
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),size.width>0,size.height>0 else { return nil }
        return CGRect(origin:point,size:size)
    }
    private func labels(_ node: AXUIElement) -> [String] {
        [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { attribute(node,$0) as? String }.filter { !$0.isEmpty }.map { String($0.prefix(300)) }
    }
    func visualSnapshot(app: String) throws -> VisualSnapshot {
        let root=try appRoot(app)
        guard try !menus.hasActiveMenu(app:app) else {throw fail("Choose an item in the open menu or say ‘close menu’")}
        guard let window=element(root,kAXFocusedWindowAttribute),let windowBounds=bounds(window) else { throw fail("No focused accessible window") }
        var nodes=[String:AXUIElement](),candidates=[VisualTargetPolicy.Candidate](),stack=[(window,false)],visited=0
        let deadline=ProcessInfo.processInfo.systemUptime+0.35
        while let (node,parentIsWeb)=stack.popLast() {
            visited+=1
            guard visited<=2000,ProcessInfo.processInfo.systemUptime<deadline else { throw fail("Accessible controls exceeded the bounded scan; no visual click sent") }
            let role=attribute(node,kAXRoleAttribute) as? String ?? ""
            let isWeb=parentIsWeb || role=="AXWebArea"
            if (app != "com.google.Chrome" || isWeb),[kAXButtonRole,"AXLink",kAXCheckBoxRole,kAXRadioButtonRole].contains(role),let rect=bounds(node),windowBounds.contains(rect) {
                guard candidates.count<128 else { throw fail("Too many visible candidates; no visual click sent") }
                let id=UUID().uuidString
                nodes[id]=node
                candidates.append(.init(id:id,labels:labels(node),bounds:rect,enabled:attribute(node,kAXEnabledAttribute) as? Bool != false))
            }
            stack.append(contentsOf:(attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0,isWeb) })
        }
        return VisualSnapshot(app:app,window:window,bounds:windowBounds,candidates:candidates,nodes:nodes)
    }
    private func hitTest(_ node: AXUIElement, point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&hit) == .success else { return false }
        for _ in 0..<8 {
            guard let current=hit else { return false }
            if CFEqual(current,node) { return true }
            hit=element(current,kAXParentAttribute)
        }
        return false
    }
    private func transitionState(_ node: AXUIElement) -> [String:String] {
        var result=[String:String]()
        for key in [kAXExpandedAttribute,kAXSelectedAttribute] {
            if let value=attribute(node,key) as? NSNumber { result[key]=value.stringValue }
        }
        if [kAXCheckBoxRole,kAXRadioButtonRole].contains(attribute(node,kAXRoleAttribute) as? String ?? ""),let value=attribute(node,kAXValueAttribute) as? NSNumber { result[kAXValueAttribute]=value.stringValue }
        return result
    }
    private func verifiedPress(_ node: AXUIElement, app: String, window: AXUIElement, point: CGPoint, stillValid: () -> Bool) async throws -> String {
        let root=try appRoot(app)
        guard stillValid(),try !menus.hasActiveMenu(app:app),let currentWindow=element(root,kAXFocusedWindowAttribute),CFEqual(currentWindow,window),
              attribute(node,kAXEnabledAttribute) as? Bool != false,hitTest(node,point:point) else { throw fail("Target lost focus, moved behind another surface, or was cancelled") }
        let before=transitionState(node)
        // Ordinary AppKit buttons may wait for their press animation before
        // acknowledging AXPress. A 50 ms attribute-read timeout is too short.
        AXUIElementSetMessagingTimeout(node,0.35)
        guard AXUIElementPerformAction(node,kAXPressAction as CFString) == .success else { throw fail("Click acknowledgement unavailable; it may have occurred. Not retrying.") }
        draft=nil
        // No measurable native state was exposed, so an arbitrary delay cannot
        // establish an outcome. Report the acknowledgement without claiming one.
        if before.isEmpty {return "Click delivered; result not verified"}
        // Never replay input. A visual change alone is not an outcome verdict.
        try? await Task.sleep(nanoseconds:180_000_000)
        guard stillValid(),NSWorkspace.shared.frontmostApplication?.bundleIdentifier==app,
              let finalWindow=element(root,kAXFocusedWindowAttribute),CFEqual(finalWindow,window) else { return "Click delivered; result not verified" }
        let after=transitionState(node)
        let changed=before.contains { key,value in after[key] != nil && after[key] != value }
        return changed ? "Control transition verified" : "Click delivered; result not verified"
    }
    /// nil means preflight found no unique exact label. No input has been sent.
    func click(_ label: String, app: String, stillValid: () -> Bool) async throws -> String? {
        let root=try appRoot(app),menuSnapshot=try menus.snapshot(app:app)
        // An open menu owns interaction even when the old field retains AX focus.
        if !menuSnapshot.active,let window=element(root,kAXFocusedWindowAttribute) {
            let matches=try controls(in:window,labels:[InteractionRules.normalizedLabel(label)])
            if matches.count>1 {throw fail("More than one control matches ‘\(label)’")}
            if let node=matches.first {
                guard let rect=bounds(node) else {throw fail("Control has no visible bounds")}
                return try await verifiedPress(node,app:app,window:window,point:CGPoint(x:rect.midX,y:rect.midY),stillValid:stillValid)
            }
        }
        let matches=menus.matching(label,in:menuSnapshot)
        if matches.count>1 {throw fail("More than one menu item matches ‘\(label)’")}
        guard let match=matches.first else {return nil}
        draft=nil
        return try await menus.press(match.candidate.id,snapshot:menuSnapshot,stillValid:stillValid)
    }
    func pressVisual(_ id: String, point: CGPoint, snapshot: VisualSnapshot, stillValid: () -> Bool) async throws -> String {
        guard let candidate=snapshot.candidates.first(where:{$0.id==id}),let node=snapshot.nodes[id],
              bounds(snapshot.window)==snapshot.bounds,bounds(node)==candidate.bounds,labels(node)==candidate.labels,
              attribute(node,kAXEnabledAttribute) as? Bool != false else { throw fail("Observed control changed; no click sent") }
        return try await verifiedPress(node,app:snapshot.app,window:snapshot.window,point:point,stillValid:stillValid)
    }
    /// Fresh scans assign new ephemeral IDs. Tie them through actual AX element
    /// identity, original labels and geometry, never through coordinate alone.
    func sameVisualControl(_ originalID:String, original:VisualSnapshot, currentID:String, current:VisualSnapshot) -> Bool {
        guard original.app==current.app,CFEqual(original.window,current.window),original.bounds==current.bounds,
              let a=original.nodes[originalID],let b=current.nodes[currentID],CFEqual(a,b),
              let before=original.candidates.first(where:{$0.id==originalID}),let after=current.candidates.first(where:{$0.id==currentID}) else { return false }
        return before.bounds==after.bounds && before.labels==after.labels && before.enabled && after.enabled
    }
    func sameVisualScene(_ original:VisualSnapshot,_ current:VisualSnapshot) -> Bool {
        guard original.app==current.app,CFEqual(original.window,current.window),original.bounds==current.bounds,
              original.candidates.count==current.candidates.count else { return false }
        return original.candidates.allSatisfy { before in
            guard let node=original.nodes[before.id],let after=current.candidates.first(where: {
                guard let other=current.nodes[$0.id] else { return false }
                return CFEqual(node,other)
            }) else { return false }
            return before.bounds==after.bounds && before.labels==after.labels && before.enabled==after.enabled
        }
    }
    func send(app: String) throws -> String {
        let root = try appRoot(app)
        guard try !menus.hasActiveMenu(app:app) else {throw fail("Close the menu before sending the draft")}
        guard let draft, draft.app == app,
              let window = element(root,kAXFocusedWindowAttribute), CFEqual(window,draft.window),
              let current = focusedField(), CFEqual(current,draft.field),
              attribute(draft.field,kAXValueAttribute) as? String == draft.value else { throw fail("No unchanged dictated draft is focused. Dictate your message first.") }
        let matches = try controls(in:window,labels:InteractionRules.sendLabels)
        guard matches.count == 1 else { throw fail("Could not identify one Send button. You can send manually.") }
        _ = try appRoot(app)
        guard try !menus.hasActiveMenu(app:app),let finalField = focusedField(), CFEqual(finalField,draft.field),
              let finalWindow = element(root,kAXFocusedWindowAttribute), CFEqual(finalWindow,draft.window),
              attribute(draft.field,kAXValueAttribute) as? String == draft.value else { throw fail("Draft changed before sending") }
        guard AXUIElementPerformAction(matches[0],kAXPressAction as CFString) == .success else { throw fail("Send button refused the action") }
        self.draft = nil
        return "Send requested"
    }
}
