import Foundation

struct IndexedRow<Item: Identifiable>: Identifiable {
    let item: Item
    let index: Int

    var id: Item.ID { item.id }
}

extension IndexedRow: Equatable where Item: Equatable {}

extension Collection where Element: Identifiable {
    func indexedRows() -> [IndexedRow<Element>] {
        enumerated().map { IndexedRow(item: $0.element, index: $0.offset) }
    }
}
