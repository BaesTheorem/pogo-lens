import SwiftUI
import ReplayKit
import UserNotifications

/// The system broadcast picker: tapping it offers Pogo Lens as the broadcast target.
struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        view.preferredExtension = AppGroup.broadcastExtension
        view.showsMicrophoneButton = false
        return view
    }

    func updateUIViewController(_ uiViewController: RPSystemBroadcastPickerView, context: Context) {}
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct LiveScanSection: View {
    @EnvironmentObject var store: BoxStore
    @Binding var message: String?
    @State private var pending = LiveLog.pendingCount

    var body: some View {
        Section {
            HStack(spacing: 12) {
                BroadcastPickerButton().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start live scan").fontWeight(.medium)
                    Text("Tap the icon, then Start Broadcast. Switch to Pokémon GO and open each Pokémon; Appraise for exact IVs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if pending > 0 {
                Button("Import \(pending) live reading\(pending == 1 ? "" : "s")") {
                    message = LiveMerge.run(into: store)
                    pending = LiveLog.pendingCount
                }
            }
        } header: {
            Text("Live scan")
        } footer: {
            Text("A banner over the game shows each Pokémon as it is read. Stop the broadcast from the red status pill; readings import when you return here.")
        }
        .onAppear {
            pending = LiveLog.pendingCount
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }
}
