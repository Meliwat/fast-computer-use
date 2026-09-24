/// Modifier-only gesture: chords cancel, and stay blocked until Option is released.
public struct PushToTalk {
    public enum Event: Equatable { case begin, finish, cancel }
    private var holding = false
    private var blocked = false
    public init() {}
    public mutating func update(option: Bool, otherModifier: Bool) -> Event? {
        if !option {
            let wasHolding = holding
            holding = false; blocked = false
            return wasHolding ? .finish : nil
        }
        if otherModifier {
            blocked = true
            let wasHolding = holding; holding = false
            return wasHolding ? .cancel : nil
        }
        guard !blocked, !holding else { return nil }
        holding = true; return .begin
    }
}
