import UIKit

/// An invisible text field that brings up the system keyboard when a
/// game asks for text (naming the player, for example).
///
/// SDL's own keyboard is turned off (SDL_ENABLE_SCREEN_KEYBOARD=0):
/// its Return key presses and releases in the same instant, which a
/// game reading input once per frame never sees. Here, typed text goes
/// to the engine with mkxp_pushTextInput, and Return and Backspace go
/// through KeyTapper, held long enough to count.
final class GameTextField: UITextField, UITextFieldDelegate {
    /// Kept in the field so the keyboard's delete key stays enabled:
    /// deleting it is how a backspace shows up.
    private static let placeholderText = " "

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        text = Self.placeholderText
        alpha = 0.01
        tintColor = .clear
        autocorrectionType = .no
        autocapitalizationType = .words
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        textContentType = UITextContentType(rawValue: "")
        inlinePredictionType = .no
        returnKeyType = .done
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Opened by the player from the menu, not by the game: stays up
    /// until Return, whatever the game's text mode says.
    private(set) var isManual = false

    func openManually() {
        isManual = true
        setActive(true)
    }

    func setActive(_ active: Bool) {
        if !active, isManual { return }
        if active, !isFirstResponder {
            text = Self.placeholderText
            becomeFirstResponder()
        } else if !active, isFirstResponder {
            resignFirstResponder()
        }
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        MainActor.assumeIsolated {
            if string.isEmpty, range.length > 0 {
                KeyTapper.tap(.backspace)
            } else if mkxp_isTextInputActive() != 0 {
                // The game reads text (Input.gets): newer Essentials.
                for character in string {
                    mkxp_pushTextInput(String(character))
                }
            } else {
                // The game polls the keyboard key by key: older Essentials
                // name entry, and other scenes built for a PC keyboard.
                for character in string {
                    KeyTapper.type(character)
                }
            }
        }
        textField.text = Self.placeholderText
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        MainActor.assumeIsolated { KeyTapper.tap(.enter) }
        if isManual {
            isManual = false
            resignFirstResponder()
        }
        return false
    }
}
