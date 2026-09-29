import SwiftUI
import UIKit

struct SearchStringsView: View {
    @State private var items = SearchStrings.builtIn
    @State private var copied: String?

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title).fontWeight(.medium)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = item.string
                        copied = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == item.id { copied = nil } }
                    } label: {
                        Label(copied == item.id ? "Copied" : "Copy", systemImage: copied == item.id ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                }
                Text(item.string)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                if !item.note.isEmpty {
                    Text(item.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Search strings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { items = SearchStrings.all() }
        .refreshable { items = SearchStrings.all() }
    }
}
