import AppKit
import SwiftUI

struct LowStorageWarningView: View {
  let warningMessage: String
  let openSettings: () -> Void
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text("Low Storage Warning")
            .font(.title3.weight(.semibold))
          Text("Rewind may stop recording if your disk space runs out.")
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.yellow)
          .font(.system(size: 14, weight: .semibold))

        Text(warningMessage)
          .font(.system(size: 13, weight: .medium))
      }

      Spacer(minLength: 0)

      HStack {
        Spacer()

        Button("Got it") {
          close()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .frame(width: 520, height: 240)
  }
}
