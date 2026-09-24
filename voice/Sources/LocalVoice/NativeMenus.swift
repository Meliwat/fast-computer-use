import AppKit
import ApplicationServices
import VoiceCore

/// Current-app menu surfaces. Hidden menu definitions are not action targets.
@MainActor final class NativeMenus {
    private var recentMenus:(pid:pid_t,nodes:[AXUIElement])?
    struct Entry {
        let candidate:BrowserObservation.Candidate
        let node:AXUIElement
        let opensMenu:Bool
    }
    struct Snapshot {
        let app:String
        let pid:pid_t
        let bar:AXUIElement?
        let openMenus:[AXUIElement]
        let entries:[Entry]
        var active:Bool {!openMenus.isEmpty}
        var nodes:[String:AXUIElement] {Dictionary(uniqueKeysWithValues:entries.map {($0.candidate.id,$0.node)})}
        var candidates:[BrowserObservation.Candidate] {entries.map(\.candidate)}
    }
    private func fail(_ message:String)->NSError {NSError(domain:"LocalVoiceMenus",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    private func attribute(_ node:AXUIElement,_ key:String)->CFTypeRef? {
        AXUIElementSetMessagingTimeout(node,0.05)
        var value:CFTypeRef?
        return AXUIElementCopyAttributeValue(node,key as CFString,&value) == .success ? value : nil
    }
    private func element(_ node:AXUIElement,_ key:String)->AXUIElement? {
        guard let value=attribute(node,key),CFGetTypeID(value)==AXUIElementGetTypeID() else {return nil}
        return (value as! AXUIElement)
    }
    private func children(_ node:AXUIElement)->[AXUIElement] {attribute(node,kAXChildrenAttribute) as? [AXUIElement] ?? []}
    private func role(_ node:AXUIElement)->String {attribute(node,kAXRoleAttribute) as? String ?? ""}
    private func root(_ app:String)throws->(AXUIElement,pid_t) {
        guard AXIsProcessTrusted(),let current=NSWorkspace.shared.frontmostApplication,current.bundleIdentifier==app else {throw fail("Menu access or foreground app changed")}
        return (AXUIElementCreateApplication(current.processIdentifier),current.processIdentifier)
    }
    private func bounds(_ node:AXUIElement)->CGRect? {
        guard let p=attribute(node,kAXPositionAttribute),CFGetTypeID(p)==AXValueGetTypeID(),
              let s=attribute(node,kAXSizeAttribute),CFGetTypeID(s)==AXValueGetTypeID() else {return nil}
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),
              [point.x,point.y,size.width,size.height].allSatisfy(\.isFinite),size.width>1,size.height>1 else {return nil}
        return CGRect(origin:point,size:size)
    }
    private func hit(_ node:AXUIElement,_ rect:CGRect)->Bool {
        var target:AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(rect.midX),Float(rect.midY),&target) == .success else {return false}
        for _ in 0..<12 {
            guard let current=target else {return false}
            if CFEqual(current,node) {return true}
            target=element(current,kAXParentAttribute)
        }
        return false
    }
    private func visible(_ node:AXUIElement)->CGRect? {
        guard attribute(node,"AXHidden") as? Bool != true,let rect=bounds(node),hit(node,rect) else {return nil}
        return rect
    }
    private func actions(_ node:AXUIElement)->[String] {
        var value:CFArray?
        guard AXUIElementCopyActionNames(node,&value) == .success else {return []}
        return value as? [String] ?? []
    }
    private func focusedMenu(_ pid:pid_t)->AXUIElement? {
        guard let focused=element(AXUIElementCreateSystemWide(),kAXFocusedUIElementAttribute) else {return nil}
        var owner:pid_t=0
        guard AXUIElementGetPid(focused,&owner) == .success,owner==pid else {return nil}
        if let shown=element(focused,"AXShownMenuUIElement"),role(shown)==kAXMenuRole,visible(shown) != nil {return shown}
        guard [kAXMenuRole,kAXMenuItemRole].contains(role(focused)) else {return nil}
        var node:AXUIElement?=focused
        for _ in 0..<8 {
            guard let current=node else {break}
            if role(current)==kAXMenuRole,visible(current) != nil {return current}
            node=element(current,kAXParentAttribute)
        }
        return nil
    }
    private func stillVisibleMenus(_ pid:pid_t)->[AXUIElement] {
        guard let recentMenus,recentMenus.pid==pid else {self.recentMenus=nil;return []}
        let visible=recentMenus.nodes.filter {self.visible($0) != nil}
        self.recentMenus=visible.isEmpty ? nil : (pid,visible)
        return visible
    }
    /// Cheap preflight for typing and ordinary native actions; no closed-item traversal.
    func hasActiveMenu(app:String)throws->Bool {
        let (appRoot,pid)=try root(app)
        if !stillVisibleMenus(pid).isEmpty {return true}
        if let bar=element(appRoot,kAXMenuBarAttribute),children(bar).contains(where:{attribute($0,kAXSelectedAttribute) as? Bool == true}) {return true}
        if let shown=element(appRoot,"AXShownMenuUIElement"),role(shown)==kAXMenuRole,visible(shown) != nil {return true}
        return focusedMenu(pid) != nil
    }
    func snapshot(app:String,identities:[String:AXUIElement]=[:])throws->Snapshot {
        let (appRoot,pid)=try root(app),started=ProcessInfo.processInfo.systemUptime
        let bar=element(appRoot,kAXMenuBarAttribute)
        // A cancelled command may leave a closing menu with AXSelected already
        // false. Retain only previously observed, still-hit-testable surfaces.
        var entries=[Entry](),open=[AXUIElement](),pending=stillVisibleMenus(pid),visited=0
        func budget()throws {
            visited+=1
            guard visited<=800,entries.count<128,ProcessInfo.processInfo.systemUptime-started<0.35 else {throw fail("Native menu observation was incomplete")}
        }
        func append(_ node:AXUIElement,opens:Bool,rect:CGRect) {
            let id=identities.first(where:{CFEqual($0.value,node)})?.key ?? "menu:"+UUID().uuidString
            let title=attribute(node,kAXTitleAttribute) as? String ?? ""
            let labels=NativeMenuLabels.aliases(title,opensMenu:opens)
            let press=actions(node).contains(kAXPressAction)
            let candidate=BrowserObservation.Candidate(id:id,role:"button",labels:labels,
                bounds:.init(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height),
                enabled:attribute(node,kAXEnabledAttribute) as? Bool == true,editable:false,clickable:press,
                selected:(attribute(node,kAXSelectedAttribute) as? NSNumber)?.stringValue)
            entries.append(Entry(candidate:candidate,node:node,opensMenu:opens))
        }
        if let bar {
            for header in children(bar) where role(header)==kAXMenuBarItemRole {
                try budget()
                guard let rect=visible(header) else {continue}
                append(header,opens:true,rect:rect)
                // Closed menus expose children too. Do not enumerate their definitions.
                if attribute(header,kAXSelectedAttribute) as? Bool == true {
                    let shown=children(header).filter {role($0)==kAXMenuRole && visible($0) != nil}
                    guard !shown.isEmpty else {throw fail("Menu is opening or closing; try again")}
                    pending+=shown
                }
            }
        }
        if let shown=element(appRoot,"AXShownMenuUIElement"),role(shown)==kAXMenuRole,visible(shown) != nil {pending.append(shown)}
        if let focused=focusedMenu(pid) {pending.append(focused)}
        while let menu=pending.popLast() {
            if open.contains(where:{CFEqual($0,menu)}) {continue}
            try budget()
            guard visible(menu) != nil else {continue}
            open.append(menu)
            for item in children(menu) where role(item)==kAXMenuItemRole {
                try budget()
                guard !entries.contains(where:{CFEqual($0.node,item)}),let rect=visible(item) else {continue}
                let submenus=children(item).filter {role($0)==kAXMenuRole}
                append(item,opens:!submenus.isEmpty,rect:rect)
                pending+=submenus.filter {visible($0) != nil}
            }
        }
        recentMenus=open.isEmpty ? nil : (pid,open)
        return Snapshot(app:app,pid:pid,bar:bar,openMenus:open,entries:entries)
    }
    func matching(_ name:String,in snapshot:Snapshot)->[Entry] {
        let wanted=InteractionRules.normalizedLabel(name)
        return snapshot.entries.filter {$0.candidate.labels.contains(where:{InteractionRules.normalizedLabel($0)==wanted})}
    }
    func sameScene(_ a:Snapshot,_ b:Snapshot)->Bool {
        let sameBar:Bool
        if let x=a.bar,let y=b.bar {sameBar=CFEqual(x,y)} else {sameBar=a.bar==nil && b.bar==nil}
        guard sameBar,a.app==b.app,a.pid==b.pid,a.active==b.active,a.openMenus.count==b.openMenus.count,
              a.openMenus.allSatisfy({old in b.openMenus.contains(where:{CFEqual(old,$0)})}) else {return false}
        guard a.entries.allSatisfy({entry in b.entries.contains(where:{$0.candidate.id==entry.candidate.id && $0.opensMenu==entry.opensMenu})}) else {return false}
        return a.candidates.sorted(by:{$0.id<$1.id})==b.candidates.sorted(by:{$0.id<$1.id})
    }
    private func childMenuVisible(_ node:AXUIElement)->Bool {children(node).contains {role($0)==kAXMenuRole && visible($0) != nil}}
    private func menuClosureObserved(_ original:Snapshot)throws->Bool {
        // AppKit clears AXSelected before its closing animation has finished.
        // Check the previously visible surfaces too, not just selected headers.
        try !hasActiveMenu(app:original.app) && original.openMenus.allSatisfy {visible($0)==nil}
    }
    func press(_ id:String,snapshot original:Snapshot,stillValid:()->Bool) async throws -> String {
        let current=try snapshot(app:original.app,identities:original.nodes)
        guard stillValid(),sameScene(original,current),let entry=current.entries.first(where:{$0.candidate.id==id}),
              entry.candidate.enabled,entry.candidate.clickable,visible(entry.node) != nil else {throw fail("Menu target changed or is unavailable; no input sent")}
        if entry.opensMenu,childMenuVisible(entry.node) {return "Menu already open · verified"}
        AXUIElementSetMessagingTimeout(entry.node,0.35)
        let acknowledgement=AXUIElementPerformAction(entry.node,kAXPressAction as CFString)
        if entry.opensMenu {
            let deadline=ProcessInfo.processInfo.systemUptime+0.5
            repeat {
                guard stillValid(),NSWorkspace.shared.frontmostApplication?.bundleIdentifier==original.app else {throw fail("Menu action interrupted; not retrying")}
                if childMenuVisible(entry.node) {return "Menu opened · verified"}
                try await Task.sleep(nanoseconds:20_000_000)
            } while ProcessInfo.processInfo.systemUptime<deadline
            throw fail("Menu opening could not be verified; not retrying")
        }
        guard acknowledgement == .success else {throw fail("Menu command acknowledgement unavailable; it may have occurred. Not retrying.")}
        // AXPress acknowledges before AppKit finishes menu tracking/animation.
        // Observe closure so a following command cannot mistake the closing
        // menu for an already-open destination. This is not command-outcome proof.
        let deadline=ProcessInfo.processInfo.systemUptime+0.5
        var closedSince:TimeInterval?
        repeat {
            guard stillValid(),NSWorkspace.shared.frontmostApplication?.bundleIdentifier==original.app else {return "Menu command delivered; result not verified"}
            if try menuClosureObserved(original) {
                if closedSince==nil {closedSince=ProcessInfo.processInfo.systemUptime}
                if ProcessInfo.processInfo.systemUptime-closedSince!>=0.06 {return "Menu command delivered; menu closed; result not verified"}
            } else {closedSince=nil}
            try await Task.sleep(nanoseconds:20_000_000)
        } while ProcessInfo.processInfo.systemUptime<deadline
        return "Menu command delivered; menu remains open; result not verified"
    }
    func dismiss(app:String,stillValid:()->Bool) async throws -> String {
        let observed=try snapshot(app:app)
        guard observed.active else {return "No open native menu"}
        let selectedBar=observed.bar.flatMap {bar in children(bar).contains(where:{attribute($0,kAXSelectedAttribute) as? Bool==true}) ? bar : nil}
        guard stillValid(),let target=selectedBar ?? observed.openMenus.first,actions(target).contains(kAXCancelAction) else {throw fail("Menu cannot be dismissed through Accessibility")}
        AXUIElementSetMessagingTimeout(target,0.35)
        _=AXUIElementPerformAction(target,kAXCancelAction as CFString)
        let deadline=ProcessInfo.processInfo.systemUptime+0.5
        var closedSince:TimeInterval?
        repeat {
            guard stillValid(),NSWorkspace.shared.frontmostApplication?.bundleIdentifier==app else {throw fail("Menu dismissal interrupted; not retrying")}
            if try menuClosureObserved(observed) {
                if closedSince==nil {closedSince=ProcessInfo.processInfo.systemUptime}
                if ProcessInfo.processInfo.systemUptime-closedSince!>=0.06 {return "Menu closed · verified"}
            } else {closedSince=nil}
            try await Task.sleep(nanoseconds:20_000_000)
        } while ProcessInfo.processInfo.systemUptime<deadline
        throw fail("Menu closure could not be verified; not retrying")
    }
}
