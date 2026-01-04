import SwiftUI

struct PlayerListView: View {
    let players: [PlayerSession]

    var body: some View {
        ForEach(players) { player in
            VStack(alignment: .leading, spacing: 4) {
                Text(player.playerName)
                    .font(.headline)

                HStack {
                    Text("Buy-ins: \(player.buyInCount)")
                    Text("•")
                    Text("Chips: \(player.finalChipCount.withCommas())")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if player.finalChipCount > 0 {
                    Text("Net: \(player.netAmount.asCurrency())")
                        .font(.subheadline)
                        .foregroundStyle(player.netAmount >= 0 ? .green : .red)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
