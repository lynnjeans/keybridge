import ApplicationServices

/// What has keyboard focus in the frontmost application, read through the
/// Accessibility API that KeyBridge holds permission for anyway.
enum FocusedElement {
    /// True while keys belong to typing or to a dialog rather than to a file
    /// list: a text field, a search field, a button, or anything in a dialog
    /// window. Rules that skip text input stand aside then.
    ///
    /// Called from the event tap, and only for rules that ask, so it must be
    /// quick: the query gives up after 50 ms and then counts as not typing.
    @MainActor
    static func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let element = element(of: system, kAXFocusedUIElementAttribute) else {
            return false
        }
        AXUIElementSetMessagingTimeout(element, 0.05)
        let role = string(of: element, kAXRoleAttribute)
        let subrole = string(of: element, kAXSubroleAttribute)
        if let role, typingRoles.contains(role) { return true }
        if subrole == kAXSearchFieldSubrole { return true }

        if let window = self.element(of: element, kAXWindowAttribute) {
            let windowSubrole = string(of: window, kAXSubroleAttribute)
            if let windowSubrole, dialogSubroles.contains(windowSubrole) { return true }
        }
        return false
    }

    private static let typingRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXButtonRole,
        "AXSearchField", "AXSheet",
    ]

    private static let dialogSubroles: Set<String> = [kAXDialogSubrole, kAXSystemDialogSubrole]

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func element(of element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
