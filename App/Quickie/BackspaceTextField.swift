import SwiftUI
import UIKit

/// A text field that reports a backspace pressed while it is **empty** — the
/// breadcrumb's "pop the last pill" gesture (issue #37), which a SwiftUI
/// `TextField` can't surface. Used only by the multi-step capture input; the
/// normal search field stays a plain SwiftUI `TextField`.
///
/// It also auto-focuses when it appears so the keyboard rises for each text/choice
/// step the way it does on launch, and resigns when the step morphs to the date
/// picker (the field is removed from the hierarchy).
struct BackspaceTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var returnKey: UIReturnKeyType = .next
    var onSubmit: () -> Void
    var onBackspaceWhenEmpty: () -> Void

    func makeUIView(context: Context) -> EmptyBackspaceTextField {
        let field = EmptyBackspaceTextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.font = .preferredFont(forTextStyle: .title3)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.accessibilityIdentifier = "capture-input"
        // Focus on the next runloop tick so the keyboard rises once the field is
        // in the window — the same fresh-appearance focus the launcher relies on.
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmptyBackspaceTextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.returnKeyType = returnKey
        field.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            onSubmit()
            return false
        }
    }
}

/// A `UITextField` that forwards a backspace on an empty field. UIKit calls
/// `deleteBackward()` even with no text to delete, which is the documented hook
/// for detecting the gesture.
final class EmptyBackspaceTextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onBackspaceWhenEmpty?()
        }
        super.deleteBackward()
    }
}
