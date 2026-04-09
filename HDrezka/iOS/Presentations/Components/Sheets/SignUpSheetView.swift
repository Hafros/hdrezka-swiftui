import FirebaseAnalytics
import SwiftUI

struct SignUpSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .center, spacing: 25) {
            VStack(alignment: .center, spacing: 5) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)

                Text("key.sign_up.label")
                    .font(.largeTitle.weight(.semibold))

                Text("key.sign_up_temporarily_unavailable")
                    .font(.title3)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }

            Button {
                dismiss()
                appState.isSignInPresented = true
            } label: {
                Text("key.sign_in")
                    .frame(width: 250, height: 30)
                    .foregroundStyle(.white)
                    .contentShape(.rect(cornerRadius: 6))
                    .background(Color.accentColor, in: .rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 35)
        .padding(.top, 35)
        .padding(.bottom, 25)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .analyticsScreen(name: "sign_up_sheet", class: "SignUpSheetView")
    }
}
