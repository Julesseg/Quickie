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
    /// The system keyboard this step raises — the numeric pad for a `number`
    /// Argument, the default alphanumeric layout otherwise (issue #96).
    var keyboardType: UIKeyboardType = .default
    var onSubmit: () -> Void
    var onBackspaceWhenEmpty: () -> Void

    func makeUIView(context: Context) -> EmptyBackspaceTextField {
        let field = EmptyBackspaceTextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.keyboardType = keyboardType
        field.font = .preferredFont(forTextStyle: .title3)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.accessibilityIdentifier = "capture-input"
        configureAccessory(field, context)
        // Focus on the next runloop tick so the keyboard rises once the field is
        // in the window — the same fresh-appearance focus the launcher relies on.
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmptyBackspaceTextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.returnKeyType = returnKey
        // Swap the keyboard layout when the step's type changes (text ↔ number),
        // rebuilding the number pad's accessory bar and reloading the input views if
        // the field is already first responder.
        if field.keyboardType != keyboardType {
            field.keyboardType = keyboardType
            configureAccessory(field, context)
            if field.isFirstResponder { field.reloadInputViews() }
        }
        // Keep the number pad's submit-button title in step with the return key even
        // when the keyboard itself doesn't change — two consecutive numeric steps can
        // differ only in whether the current one is the final step ("Done" vs "Next").
        // A live title change updates in place, so no input-view reload is needed.
        field.numberSubmitItem?.title = returnKey == .done ? "Done" : "Next"
        field.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        context.coordinator.onSubmit = onSubmit
    }

    /// The number pad carries no Return key, so a numeric step gets a toolbar above
    /// the pad with a submit button — "Done" on the final step, "Next" otherwise —
    /// that commits the step exactly as Return does for a text step (issue #96). A
    /// text step needs no accessory (its Return key submits), so the bar is cleared.
    private func configureAccessory(_ field: EmptyBackspaceTextField, _ context: Context) {
        guard keyboardType == .numberPad else {
            field.inputAccessoryView = nil
            field.numberSubmitItem = nil
            return
        }
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let submit = UIBarButtonItem(
            title: returnKey == .done ? "Done" : "Next",
            style: .done,
            target: context.coordinator,
            action: #selector(Coordinator.accessoryTapped)
        )
        submit.accessibilityIdentifier = "capture-number-submit"
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            submit,
        ]
        field.inputAccessoryView = toolbar
        // Held so a later step (same keyboard, different return key) can refresh the
        // title without rebuilding the whole bar.
        field.numberSubmitItem = submit
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

        /// The number pad's accessory-bar submit button — commits the step the way
        /// Return does on a text step (issue #96).
        @objc func accessoryTapped() {
            onSubmit()
        }
    }
}

/// A `UITextField` that forwards a backspace on an empty field. UIKit calls
/// `deleteBackward()` even with no text to delete, which is the documented hook
/// for detecting the gesture.
final class EmptyBackspaceTextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?
    /// The number pad's accessory-bar submit button, held so its title can track the
    /// return key across steps that share the numeric keyboard (issue #96).
    weak var numberSubmitItem: UIBarButtonItem?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onBackspaceWhenEmpty?()
        }
        super.deleteBackward()
    }
}
