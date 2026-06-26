/// The kind of value flowing through Quickie. An Action declares the content
/// type(s) it consumes and the one it produces (ADR 0011); content type drives
/// which Actions are eligible for a value, how they rank, and — in a future
/// Workflow — whether one Action's output can feed another's input.
///
/// The walking skeleton needs only this handful; the enum grows as new
/// providers arrive (e.g. a Calculator producing `.number`).
public enum ContentType: Equatable, Sendable {
    case text
    case url
    case number
    case file
}
