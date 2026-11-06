#if canImport(Combine)
import Combine
#else
import Foundation

/// Linux-only stand-ins so Settings view-models compile in `swift test`.
/// macOS uses real Combine.
public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: Published<Value> { self }
}
#endif
