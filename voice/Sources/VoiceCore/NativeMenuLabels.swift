import Foundation

public enum NativeMenuLabels {
    /// Ellipses mark commands opening a dialog; the spoken caption usually omits them.
    public static func aliases(_ title:String,opensMenu:Bool)->[String] {
        let literal=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !literal.isEmpty else {return []}
        let bare=literal.replacingOccurrences(of:#"(?:…|\.{3})$"#,with:"",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
        var values=[literal]
        if !bare.isEmpty,bare != literal {values.append(bare)}
        if !bare.isEmpty {values.append(bare+(opensMenu ? " menu" : " menu item"))}
        return values
    }
}
