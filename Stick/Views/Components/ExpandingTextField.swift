import SwiftUI

struct ExpandingTextField: View {
    var placeholder: String
    @Binding var text: String
    var onCommit: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(2...4)
            .focused($isFocused)
            .submitLabel(.done)
            .onChange(of: text) { _, newValue in
                // Intercept the "Return" key
                if let last = newValue.last, last == "\n" {
                    text.removeLast() // Delete the newline
                    isFocused = false // Dismiss keyboard
                    onCommit()        // Trigger the save action
                }
            }
    }
}
