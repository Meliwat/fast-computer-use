// Disposable native text fields. No real documents, network, microphone or capture.
import AppKit
import Darwin

final class TextFixture: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window:NSWindow!
    var fields=[String:NSTextField]()
    var last=[String:String]()
    var changes=[String:Int]()
    var history=[String:[String]]()
    let grounded=CommandLine.arguments.contains("--grounded")
    var buttons=[String:NSButton]()
    var clicks=[String:Int]()
    var focusHistory=[String]()
    var lastFocus="none"
    var helpRenamed=false
    var renameObserver:NSObjectProtocol?
    let menuTesting=CommandLine.arguments.contains("--menus")
    var testMenus=[NSMenu]()
    var menuEvents=[String]()
    var menuCommands=[String]()
    var menuOpenedAt:Date?
    var timer:Timer?
    var scheduled=Set<String>()
    var previousApp:NSRunningApplication?
    var wasForeground=false
    var termination:DispatchSourceSignal?
    let report=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("text-fixture-state.json")
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let index=CommandLine.arguments.firstIndex(of:"--return-to"),index+1<CommandLine.arguments.count,
           let pid=Int32(CommandLine.arguments[index+1]) {previousApp=NSRunningApplication(processIdentifier:pid)}
        else {previousApp=NSWorkspace.shared.frontmostApplication}
        signal(SIGTERM,SIG_IGN)
        termination=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
        termination?.setEventHandler { NSApp.terminate(nil) };termination?.resume()
        NSApp.setActivationPolicy(.regular)
        let menu=NSMenu(),item=NSMenuItem(),appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quit Text Fixture",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=appMenu;menu.addItem(item);NSApp.mainMenu=menu
        if menuTesting {
            let file=NSMenu(title:"File");file.autoenablesItems=false;file.delegate=self
            let header=NSMenuItem(title:"File",action:nil,keyEquivalent:"");header.submenu=file;menu.addItem(header)
            for (id,title,enabled) in [("new","New workspace",true),("save","Save",true),("save-as","Save as…",true),
                                       ("disabled","Unavailable",false),("duplicate-a","Details",true),("duplicate-b","Details",true)] {
                let entry=NSMenuItem(title:title,action:#selector(menuInvoked(_:)),keyEquivalent:"");entry.target=self;entry.representedObject=id;entry.isEnabled=enabled;file.addItem(entry)
            }
            let export=NSMenu(title:"Export");export.autoenablesItems=false;export.delegate=self
            let sub=NSMenuItem(title:"Export",action:nil,keyEquivalent:"");sub.submenu=export;file.addItem(sub)
            for (id,title) in [("image","Image…"),("text","Text…")] {
                let entry=NSMenuItem(title:title,action:#selector(menuInvoked(_:)),keyEquivalent:"");entry.target=self;entry.representedObject=id;export.addItem(entry)
            }
            testMenus=[file,export]
        }
        let width=grounded ? 940 : 680
        window=NSWindow(contentRect:NSRect(x:260,y:100,width:width,height:740),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Local Voice — disposable native text test"
        let view=NSView(frame:NSRect(x:0,y:0,width:width,height:740));window.contentView=view
        let heading=NSTextField(labelWithString:"Native field and read-back checks")
        heading.font = .systemFont(ofSize:22);heading.frame=NSRect(x:30,y:690,width:620,height:34);view.addSubview(heading)
        let entries=[("destination","Destination"),("reverting","Reverting"),("moving","Moving focus"),
                     ("duplicateA","Duplicate"),("duplicateB","Duplicate"),("disabled","Disabled"),
                     ("readonly","Read only"),("password","Password"),("hidden","Hidden"),
                     ("placeholder","City"),("linked","Subject")]
        for (index,pair) in entries.enumerated() {
            let (id,name)=pair
            let label=NSTextField(labelWithString:name);label.frame=NSRect(x:30,y:640-index*55,width:180,height:26);view.addSubview(label)
            let field:NSTextField=id=="password" ? NSSecureTextField() : NSTextField()
            field.frame=NSRect(x:220,y:640-index*55,width:420,height:28)
            field.stringValue=grounded && id=="linked" ? "" : "Original";field.placeholderString=name
            if id=="linked" {field.placeholderString=nil;field.setAccessibilityTitleUIElement(label)}
            else if id != "placeholder" {field.setAccessibilityLabel(name)}
            field.setAccessibilityIdentifier(id)
            if id=="disabled" {field.isEnabled=false}
            if id=="readonly" {field.isEditable=false;field.isSelectable=true}
            if id=="hidden" {field.isHidden=true;label.isHidden=true}
            fields[id]=field;last[id]=field.stringValue;changes[id]=0;view.addSubview(field)
            if id != "password" {history[id]=[field.stringValue]}
        }
        if grounded {
            let controls=[("preferences","Preferences"),("help","Help"),("open","Open"),("save","Save"),("save-as","Save as"),
                          ("details-a","Details"),("details-b","Details"),("unavailable","Unavailable")]
            for (i,pair) in controls.enumerated() {
                let (id,title)=pair,button=NSButton(title:title,target:self,action:#selector(pressed(_:)))
                button.identifier=NSUserInterfaceItemIdentifier(id);button.frame=NSRect(x:680,y:640-i*55,width:220,height:32)
                button.isEnabled=id != "unavailable";buttons[id]=button;clicks[id]=0;view.addSubview(button)
            }
            renameObserver=DistributedNotificationCenter.default().addObserver(forName:Notification.Name("dev.localvoice.TextFixture.renameHelp"),object:nil,queue:.main) {[weak self] _ in
                self?.buttons["help"]?.title="Changed Help";self?.helpRenamed=true;self?.save()
            }
        }
        timer=Timer(timeInterval:0.01,repeats:true) {[weak self] _ in self?.observe()}
        RunLoop.main.add(timer!,forMode:.common)
        save();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func pressed(_ sender:NSButton) {
        if let id=sender.identifier?.rawValue {clicks[id,default:0]+=1;save()}
    }
    @objc func menuInvoked(_ sender:NSMenuItem) {
        if let id=sender.representedObject as? String {menuCommands.append(id);save()}
    }
    func menuWillOpen(_ menu:NSMenu) {menuEvents.append("willOpen:"+menu.title);menuOpenedAt=Date();save()}
    func menuDidClose(_ menu:NSMenu) {menuEvents.append("didClose:"+menu.title);save()}
    func observe() {
        if let opened=menuOpenedAt,Date().timeIntervalSince(opened)>8 {testMenus.forEach {$0.cancelTracking()};menuOpenedAt=nil}
        let foreground=NSWorkspace.shared.frontmostApplication?.processIdentifier==ProcessInfo.processInfo.processIdentifier
        var changed=foreground != wasForeground
        wasForeground=foreground
        let focus=fields.first {_,field in field.currentEditor().map {window.firstResponder === $0} ?? false}?.key ?? "none"
        if focus != lastFocus {lastFocus=focus;focusHistory.append(focus);changed=true}
        for (id,field) in fields where last[id] != field.stringValue {
            last[id]=field.stringValue;changes[id,default:0]+=1;changed=true
            if id != "password" {history[id,default:[]].append(field.stringValue)}
            if id=="reverting",field.stringValue=="Changed",scheduled.insert(id).inserted {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.06) {[weak self] in self?.fields[id]?.stringValue="Original"}
            }
            if id=="moving",field.stringValue=="Focus test",scheduled.insert(id).inserted {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.04) {[weak self] in
                    guard let self,let other=self.fields["destination"] else {return}
                    self.window.makeFirstResponder(other)
                }
            }
        }
        if changed {save()}
    }
    func save() {
        // Password values are never included, even in this synthetic fixture.
        let values=fields.filter {$0.key != "password"}.mapValues {$0.stringValue}
        let record:[String:Any]=["version":1,"values":values,"changes":changes,"history":history,"foreground":wasForeground,
                               "clicks":clicks,"focusHistory":focusHistory,"focused":lastFocus,"helpRenamed":helpRenamed,
                               "menuEvents":menuEvents,"menuCommands":menuCommands,"scope":"Disposable fixture strings only"]
        if let data=try? JSONSerialization.data(withJSONObject:record,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:report,options:.atomic)}
    }
    func applicationWillTerminate(_ notification:Notification) {
        timer?.invalidate();observe();save()
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier==Bundle.main.bundleIdentifier {
            previousApp?.activate(options:[])
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
}
let application=NSApplication.shared
if CommandLine.arguments.contains("--foreground-pid") {
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
    exit(0)
}
let fixture=TextFixture()
application.delegate=fixture
application.run()
