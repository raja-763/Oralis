import SwiftUI

struct ComposeView: View {
    var replyTo: EmailMessage?
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var to    = ""
    @State private var cc    = ""
    @State private var subject = ""
    @State private var body  = ""
    @State private var isSending = false
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case to, cc, subject, body }

    init(replyTo: EmailMessage? = nil) {
        self.replyTo = replyTo
        if let msg = replyTo {
            _to      = State(initialValue: msg.from.address)
            _subject = State(initialValue: "Re: \(msg.subject)")
            _body    = State(initialValue: "\n\n---\nOn \(msg.date.formatted()), \(msg.from.display) wrote:\n\(msg.bodyPlain.prefix(500))")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(replyTo == nil ? "New Message" : "Reply")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Send") { Task { await send() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(to.isEmpty || subject.isEmpty || isSending)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send email")
            }
            .padding()

            Divider()

            // Fields
            Form {
                LabeledContent("To") {
                    TextField("recipient@example.com", text: $to)
                        .focused($focusedField, equals: .to)
                        .accessibilityLabel("To field")
                }
                LabeledContent("CC") {
                    TextField("Optional", text: $cc)
                        .focused($focusedField, equals: .cc)
                        .accessibilityLabel("CC field")
                }
                LabeledContent("Subject") {
                    TextField("Subject", text: $subject)
                        .focused($focusedField, equals: .subject)
                        .accessibilityLabel("Subject field")
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 180)

            // Body
            TextEditor(text: $body)
                .focused($focusedField, equals: .body)
                .padding(8)
                .accessibilityLabel("Message body")
        }
        .frame(minWidth: 600, minHeight: 480)
        .onAppear { focusedField = to.isEmpty ? .to : .body }
    }

    private func send() async {
        guard let acc = appState.selectedAccount else { return }
        isSending = true
        let draft = DraftMessage(
            to: [EmailAddress(name: "", address: to)],
            cc: cc.isEmpty ? [] : [EmailAddress(name: "", address: cc)],
            subject: subject,
            body: body,
            replyToMessageID: replyTo?.remoteID
        )
        let service = EmailServiceFactory.service(for: acc)
        do {
            try await service.sendMessage(draft)
            appState.announce("Email sent.")
            dismiss()
        } catch {
            appState.announce("Failed to send: \(error.localizedDescription)")
        }
        isSending = false
    }
}
