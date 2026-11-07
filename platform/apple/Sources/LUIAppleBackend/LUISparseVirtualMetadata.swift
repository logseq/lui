import Foundation

/// Source metadata belongs to the virtual parent; row roots may be extensions.
struct LUISparseVirtualMetadata: Equatable {
  let count: Int
  let generation: Int
  let indices: [Int]
  let scrollIndex: Int?

  static func canonicalIndices(_ value: String) -> [Int]? {
    guard let data = value.data(using: .utf8),
      let indices = try? JSONDecoder().decode([Int].self, from: data),
      let encoded = try? JSONEncoder().encode(indices), encoded == data
    else { return nil }
    var previous = -1
    for index in indices {
      guard index >= 0, index > previous else { return nil }
      previous = index
    }
    return indices
  }

  init?(properties: [LUIProperty: LUIWireValue], children: [Int]) throws {
    let fields: [LUIProperty] = [.virtualTotalCount, .virtualGeneration, .virtualIndices]
    guard
      fields.contains(where: { properties[$0] != nil }) || properties[.virtualScrollIndex] != nil
    else {
      return nil
    }
    guard let count = properties[.virtualTotalCount]?.intValue, count >= 0,
      let generation = properties[.virtualGeneration]?.intValue, generation > 0,
      let vector = properties[.virtualIndices]?.stringValue,
      let indices = Self.canonicalIndices(vector), indices.count == children.count,
      indices.last.map({ $0 < count }) ?? true
    else {
      throw LUIBackendError.invalidBatch("invalid sparse virtual source metadata")
    }
    let scrollIndex = properties[.virtualScrollIndex]?.intValue
    if let scrollIndex, scrollIndex != -1 && !(scrollIndex >= 0 && scrollIndex < count) {
      throw LUIBackendError.invalidBatch("virtual scroll index is outside the source")
    }
    self.count = count
    self.generation = generation
    self.indices = indices
    self.scrollIndex = scrollIndex
  }
}
