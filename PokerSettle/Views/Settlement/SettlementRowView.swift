import SwiftUI

struct SettlementRowView: View {
    let settlement: Settlement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(settlement.fromPlayerName)
                    .fontWeight(.medium)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(settlement.toPlayerName)
                    .fontWeight(.medium)
            }

            Text(settlement.amount.asCurrency())
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}
