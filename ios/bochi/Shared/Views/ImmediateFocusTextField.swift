import SwiftUI
import UIKit

struct ImmediateFocusTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var textAlignment: NSTextAlignment = .natural
    var autofocus: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> AutoFocusTextField {
        let textField = AutoFocusTextField()
        textField.placeholder = placeholder
        textField.text = text
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = autocapitalizationType
        textField.textAlignment = textAlignment
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.accessibilityLabel = placeholder
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.autofocusOnWindowAttach = autofocus

        return textField
    }

    func updateUIView(_ uiView: AutoFocusTextField, context: Context) {
        context.coordinator.text = $text
        uiView.placeholder = placeholder
        uiView.keyboardType = keyboardType
        uiView.autocapitalizationType = autocapitalizationType
        uiView.textAlignment = textAlignment
        uiView.autofocusOnWindowAttach = autofocus

        if uiView.text != text {
            uiView.text = text
        }

        if autofocus {
            uiView.requestInitialFocusIfPossible()
        }
    }

    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }
    }

    final class AutoFocusTextField: UITextField {
        var autofocusOnWindowAttach = false
        private var hasRequestedInitialFocus = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            requestInitialFocusIfPossible()
        }

        // Behaviour: start keyboard presentation with the sheet instead of
        // waiting for SwiftUI's post-appearance focus pass.
        func requestInitialFocusIfPossible() {
            guard autofocusOnWindowAttach, !hasRequestedInitialFocus, window != nil else { return }

            hasRequestedInitialFocus = true
            focusIfStillAttached()

            DispatchQueue.main.async { [weak self] in
                self?.focusIfStillAttached()
            }
        }

        private func focusIfStillAttached() {
            guard window != nil, !isFirstResponder else { return }
            becomeFirstResponder()
        }
    }
}
