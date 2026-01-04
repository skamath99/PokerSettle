//
//  PokerSettleTests.swift
//  PokerSettleTests
//
//  Created by Sanketh Kamath on 12/14/25.
//

import Testing
import Foundation
@testable import PokerSettle

struct PokerSettleTests {

    // MARK: - SettlementCalculator Tests

    @Test("Settlement calculation with two players - one winner, one loser")
    func testTwoPlayersSimpleSettlement() throws {
        // Create a test game
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        // Player 1: bought in $10 (100 chips), ended with 150 chips
        let player1 = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 150)
        player1.game = game

        // Player 2: bought in $10 (100 chips), ended with 50 chips
        let player2 = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 50)
        player2.game = game

        game.players = [player1, player2]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        // Should have exactly 1 settlement
        #expect(settlements.count == 1)

        // Bob should pay Alice $5
        let settlement = settlements[0]
        #expect(settlement.fromPlayerName == "Bob")
        #expect(settlement.toPlayerName == "Alice")
        #expect(abs(settlement.amount - 5.0) < 0.01)
    }

    @Test("Settlement calculation with three players")
    func testThreePlayersSettlement() throws {
        let game = Game(buyInAmount: 20.0, chipCount: 100)

        // Alice: bought in $20 (100 chips), ended with 180 chips (+$16)
        let alice = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 180)
        alice.game = game

        // Bob: bought in $20 (100 chips), ended with 70 chips (-$6)
        let bob = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 70)
        bob.game = game

        // Charlie: bought in $20 (100 chips), ended with 50 chips (-$10)
        let charlie = PlayerSession(playerName: "Charlie", buyInCount: 1, finalChipCount: 50)
        charlie.game = game

        game.players = [alice, bob, charlie]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        // Should have exactly 2 settlements (optimal)
        #expect(settlements.count == 2)

        // Total amount paid should equal total amount received
        let totalAmount = settlements.reduce(0.0) { $0 + $1.amount }
        #expect(abs(totalAmount - 16.0) < 0.01)

        // Verify all debtors pay and all creditors receive
        let bobSettlement = settlements.first { $0.fromPlayerName == "Bob" }
        let charlieSettlement = settlements.first { $0.fromPlayerName == "Charlie" }

        #expect(bobSettlement != nil)
        #expect(charlieSettlement != nil)
        #expect(bobSettlement?.toPlayerName == "Alice")
        #expect(charlieSettlement?.toPlayerName == "Alice")
    }

    @Test("Settlement calculation with all players breaking even")
    func testAllPlayersBreakEven() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player1 = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 100)
        player1.game = game

        let player2 = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 100)
        player2.game = game

        game.players = [player1, player2]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        // Should have no settlements when everyone breaks even
        #expect(settlements.isEmpty)
    }

    @Test("Settlement calculation with multiple buy-ins")
    func testMultipleBuyIns() throws {
        let game = Game(buyInAmount: 5.0, chipCount: 100)

        // Alice: bought in 3 times ($15, 300 chips), ended with 250 chips (-$2.50)
        let alice = PlayerSession(playerName: "Alice", buyInCount: 3, finalChipCount: 250)
        alice.game = game

        // Bob: bought in 1 time ($5, 100 chips), ended with 150 chips (+$2.50)
        let bob = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 150)
        bob.game = game

        game.players = [alice, bob]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        #expect(settlements.count == 1)

        let settlement = settlements[0]
        #expect(settlement.fromPlayerName == "Alice")
        #expect(settlement.toPlayerName == "Bob")
        #expect(abs(settlement.amount - 2.5) < 0.01)
    }

    @Test("Settlement calculation with four players - complex scenario")
    func testFourPlayersComplexSettlement() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        // Alice wins big
        let alice = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 200)
        alice.game = game

        // Bob wins small
        let bob = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 120)
        bob.game = game

        // Charlie loses small
        let charlie = PlayerSession(playerName: "Charlie", buyInCount: 1, finalChipCount: 80)
        charlie.game = game

        // Dave loses big
        let dave = PlayerSession(playerName: "Dave", buyInCount: 1, finalChipCount: 0)
        dave.game = game

        game.players = [alice, bob, charlie, dave]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        // Should have at most 3 settlements (4-1 players)
        #expect(settlements.count <= 3)

        // Total debts should equal total winnings
        let totalAmount = settlements.reduce(0.0) { $0 + $1.amount }
        #expect(abs(totalAmount - 12.0) < 0.01) // Alice +$10, Bob +$2
    }

    @Test("Settlement calculation with zero chips player")
    func testPlayerWithZeroChips() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let alice = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 200)
        alice.game = game

        let bob = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 0)
        bob.game = game

        game.players = [alice, bob]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        #expect(settlements.count == 1)

        let settlement = settlements[0]
        #expect(settlement.fromPlayerName == "Bob")
        #expect(settlement.toPlayerName == "Alice")
        #expect(abs(settlement.amount - 10.0) < 0.01)
    }

    @Test("Settlement calculation handles floating point precision")
    func testFloatingPointPrecision() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 30)

        // This creates a chip-to-dollar ratio of 0.333...
        let alice = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 31)
        alice.game = game

        let bob = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 29)
        bob.game = game

        game.players = [alice, bob]

        let settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)

        // Should handle small amounts properly (threshold is 0.01)
        if !settlements.isEmpty {
            let settlement = settlements[0]
            #expect(settlement.amount > 0.01)
        }
    }

    // MARK: - ValidationHelper Tests

    @Test("Chip balance validation - perfectly balanced")
    func testChipBalanceBalanced() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player1 = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 150)
        player1.game = game

        let player2 = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 50)
        player2.game = game

        game.players = [player1, player2]

        let result = ValidationHelper.validateChipBalance(game: game)

        #expect(result.isValid)
        if case .balanced = result {
            // Success
        } else {
            Issue.record("Expected balanced result")
        }
    }

    @Test("Chip balance validation - small difference (warning)")
    func testChipBalanceWarning() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        // Total chips in: 200
        // Total chips out: 195 (5 chip difference)
        let player1 = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 145)
        player1.game = game

        let player2 = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 50)
        player2.game = game

        game.players = [player1, player2]

        let result = ValidationHelper.validateChipBalance(game: game)

        #expect(result.isValid)
        if case .warning(let message) = result {
            #expect(message.contains("5"))
        } else {
            Issue.record("Expected warning result")
        }
    }

    @Test("Chip balance validation - large difference (error)")
    func testChipBalanceError() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        // Total chips in: 200
        // Total chips out: 180 (20 chip difference > 10 threshold)
        let player1 = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 130)
        player1.game = game

        let player2 = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 50)
        player2.game = game

        game.players = [player1, player2]

        let result = ValidationHelper.validateChipBalance(game: game)

        #expect(!result.isValid)
        if case .error(let message) = result {
            #expect(message.contains("mismatch"))
        } else {
            Issue.record("Expected error result")
        }
    }

    // MARK: - Game Model Tests

    @Test("Game chip to dollar ratio calculation")
    func testChipToDollarRatio() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)
        #expect(abs(game.chipToDollarRatio - 0.1) < 0.001)

        let game2 = Game(buyInAmount: 5.0, chipCount: 50)
        #expect(abs(game2.chipToDollarRatio - 0.1) < 0.001)
    }

    @Test("Game with zero chip count returns zero ratio")
    func testZeroChipCountRatio() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 0)
        #expect(game.chipToDollarRatio == 0)
    }

    @Test("Total chips calculation with zero ratio")
    func testTotalChipsWithZeroRatio() throws {
        let game = Game(buyInAmount: 0, chipCount: 100)

        let player = PlayerSession(playerName: "Alice", buyInCount: 1)
        player.game = game
        game.players = [player]

        #expect(game.totalChips == 0)
    }

    // MARK: - PlayerSession Model Tests

    @Test("Player total buy-in calculation")
    func testPlayerTotalBuyIn() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player = PlayerSession(playerName: "Alice", buyInCount: 3)
        player.game = game

        #expect(player.totalBuyIn == 30.0)
    }

    @Test("Player final value calculation")
    func testPlayerFinalValue() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 150)
        player.game = game

        #expect(abs(player.finalValue - 15.0) < 0.01)
    }

    @Test("Player net amount calculation - winning")
    func testPlayerNetAmountWinning() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 150)
        player.game = game

        #expect(abs(player.netAmount - 5.0) < 0.01)
        #expect(player.netAmount > 0)
    }

    @Test("Player net amount calculation - losing")
    func testPlayerNetAmountLosing() throws {
        let game = Game(buyInAmount: 10.0, chipCount: 100)

        let player = PlayerSession(playerName: "Bob", buyInCount: 1, finalChipCount: 50)
        player.game = game

        #expect(abs(player.netAmount - (-5.0)) < 0.01)
        #expect(player.netAmount < 0)
    }

}
