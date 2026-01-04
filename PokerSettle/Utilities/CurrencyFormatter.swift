import Foundation

// Cached formatters for performance (NumberFormatter creation is expensive)
private let currencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter
}()

private let decimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
}()

extension Double {
    func asCurrency() -> String {
        currencyFormatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}

extension Int {
    func withCommas() -> String {
        decimalFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
