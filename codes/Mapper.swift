//
//  Mapper.swift
//  Mapping
//
//  Created by kaizei on 16/8/16.
//  Copyright © 2016年 kaizei.yimi. All rights reserved.
//

import Foundation

// MARK: - KeyPath

/// support key & index
public enum MappingKeyPath: CustomStringConvertible {
    case key(String)
    case index(Int)
    
    public var description: String {
        switch self {
        case let .key(key): return key
        case let .index(index): return "\(index)"
        }
    }
}

public protocol MappingKeyPathConvertible {
    func asMappingKeyPaths() -> [MappingKeyPath]
}

extension String: MappingKeyPathConvertible {
    public func asMappingKeyPaths() -> [MappingKeyPath] {
        return [.key(self)]
    }
}

extension Int: MappingKeyPathConvertible {
    public func asMappingKeyPaths() -> [MappingKeyPath] {
        return [.index(self)]
    }
}

extension Array: MappingKeyPathConvertible where Element == MappingKeyPathConvertible {
    public func asMappingKeyPaths() -> [MappingKeyPath] {
        return flatMap{ $0.asMappingKeyPaths() }
    }
}

// MARK: - Mapper

/// Mapper which wraps JSONDict
public struct Mapper {
    
    /// represents errors when perform mapping.
    public enum Error: Swift.Error {
        case typeMismatch(keyPath: [MappingKeyPath], value: Any, fromType: Any.Type, toType: Any.Type)
        case transformFailed(keyPath: [MappingKeyPath], value: Any, fromType: Any.Type, toType: Any.Type)
        
        case missingField(keyPath: [MappingKeyPath], json: Any)
        case missingCase(keyPath: [MappingKeyPath], value: Any, toType: Any.Type)
    }
    
    public var json: Any
    public var context: Any?
    
    public init(json: Any, context: Any? = nil) {
        self.json = json
        self.context = context
    }
    
    /**
     *  try check **from**'s value is compatible for type **Raw**, then do transform.
     *
     *  **Raw** can be valid **JSON** types or **Mapper**(checks `Any`) or **[Mapper]**(checks `[Any]`).
     */
    public func transform<Raw, T>(_ from: Any, transform: (Raw) throws -> T) throws -> T {
        let toValue: T
        
        if Raw.self == Mapper.self {
            toValue = try transform(Mapper(json: from, context: context) as! Raw)
        } else if Raw.self == [Mapper].self {
            guard let array = from as? [Any] else {
                throw Error.typeMismatch(keyPath: [], value: from, fromType: type(of: from), toType: [Any].self)
            }
            toValue = try transform(array.map{ Mapper(json: $0, context: context) } as! Raw)
        } else {
            toValue = try transform(try Mapper.cast(from, to: Raw.self))
        }
        return toValue
    }
    
    /// get **Raw** value from JSON at **keyPath**.
    /// throws invalidKeyPath, missingField or typeMismatch.
    public func rawField(at keyPath: MappingKeyPathConvertible...) throws -> Any {
        var object = json
        var components = keyPath.asMappingKeyPaths()
        
        var checkingKeyPath: [MappingKeyPath] = []
        while components.count > 0 {
            let component = components.remove(at: 0)
            switch component {
            case let .key(key):
                guard let dict = object as? [String: Any] else {
                    throw Error.typeMismatch(keyPath: checkingKeyPath,
                                             value: object,
                                             fromType: type(of: object),
                                             toType: [String: Any].self)
                }
                checkingKeyPath.append(component)
                guard let next = dict[key] else {
                    throw Error.missingField(keyPath: checkingKeyPath, json: json)
                }
                object = next
                
            case let .index(index):
                guard let array = object as? [Any] else {
                    throw Error.typeMismatch(keyPath: checkingKeyPath,
                                             value: object,
                                             fromType: type(of: object),
                                             toType: [Any].self)
                }
                checkingKeyPath.append(component)
                guard index >= 0, index < array.count else {
                    throw Error.missingField(keyPath: checkingKeyPath, json: json)
                }
                object = array[index]
            }
        }
        
        return object
    }
    
    /**
     get **Raw** value from JSON at **keyPath**. if value not exist, returns **nil**.
     throws invalidKeyPath or typeMismatch.
     - parameters:
     - pathNullAsMissing: if true, `null` component in keyPath will be treated as missing.
     - important:
     `pathNullAsMissing` only checks components in keyPath, the value at keyPath is **NOT** checked.
     Thus, `NSNull` can also be fetched when `pathNullAsMissing` is true.
     */
    public func optionalRawField(at keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true) throws -> Any? {
        do {
            return try rawField(at: keyPath)
        } catch Error.missingField {
            return nil
        } catch let Error.typeMismatch(_, _, fromType, _) where pathNullAsMissing && fromType == NSNull.self {
            return nil
        }
    }
    
    /// get **Raw** value from JSON at **keyPath**, and peform transform to T.
    /// throws invalidKeyPath, missingField, typeMismatch.
    public func map<Raw, T>(_ keyPath: MappingKeyPathConvertible..., transform: (Raw) throws -> T) throws -> T {
        let raw = try rawField(at: keyPath)
        return try Mapper.catchTransformErrorAndFillKeyPath(keyPath) {
            try self.transform(raw, transform: transform)
        }
    }
    
    /// get **Raw** from JSON using **keyPath**, and perform transform to T.
    /// throws invalidKeyPath, typeMismatch.
    public func optionalMap<Raw, T>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true, fieldNullAsMissing: Bool = true, transform: (Raw) throws -> T) throws -> T? {
        return try optionalRawField(at: keyPath, pathNullAsMissing: pathNullAsMissing)
            .flatMap { raw in
                if fieldNullAsMissing, raw is NSNull { return nil }
                return try Mapper.catchTransformErrorAndFillKeyPath(keyPath) {
                    do {
                        return try self.transform(raw, transform: transform)
                    } catch let Error.missingCase(info) where info.keyPath.count == 0 && info.toType.self == T.self {
                        return nil
                    }
                }
            }
    }
    
    public func nullableMap<Raw, T>(_ keyPath: MappingKeyPathConvertible..., transform: (Raw) throws -> T) throws -> Nullable<T> {
        let raw = try rawField(at: keyPath)
        if raw is NSNull {
            return .null
        }
        return try .some(
            Mapper.catchTransformErrorAndFillKeyPath(keyPath) {
                try self.transform(raw, transform: transform)
            }
        )
    }
    
    public func optionalNullableMap<Raw, T>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true, transform: (Raw) throws -> T) throws -> Nullable<T>? {
        return try optionalRawField(at: keyPath, pathNullAsMissing: pathNullAsMissing)
            .flatMap{ raw in
                if raw is NSNull {
                    return .null
                }
                let value: T? = try Mapper.catchTransformErrorAndFillKeyPath(keyPath) {
                    do {
                        return try self.transform(raw, transform: transform)
                    } catch let Error.missingCase(info) where info.keyPath.count == 0 && info.toType.self == T.self {
                        return nil
                    }
                }
                return value.flatMap{ .some($0) }
        }
    }
    
    private static func catchTransformErrorAndFillKeyPath<T>(_ parentKeyPath: MappingKeyPathConvertible..., transform: () throws -> T) throws -> T {
        do {
            return try transform()
        } catch let error as Mapper.Error {
            switch error {
            case let .typeMismatch(keyPath, value, fromType, toType):
                throw Mapper.Error.typeMismatch(keyPath: parentKeyPath.asMappingKeyPaths() + keyPath, value: value, fromType: fromType, toType: toType)
            case let .transformFailed(keyPath, value, fromType, toType):
                throw Mapper.Error.transformFailed(keyPath: parentKeyPath.asMappingKeyPaths() + keyPath, value: value, fromType: fromType, toType: toType)
            case let .missingCase(keyPath, value, toType):
                throw Mapper.Error.missingCase(keyPath: parentKeyPath.asMappingKeyPaths() + keyPath, value: value, toType: toType)
            case let .missingField(keyPath, json):
                throw Mapper.Error.missingField(keyPath: parentKeyPath.asMappingKeyPaths() + keyPath, json: json)
            }
        }
    }
    
    /// return a new transform func that maps array.
    private static func wrapAsArrayTransform<F, T>(skipFailedItems: Bool = false, transform: @escaping (F) throws -> T) -> ([F]) throws -> [T] {
        return { (array: [F]) throws -> [T] in
            try array.enumerated().compactMap { (index, f: F) throws -> T? in
                if skipFailedItems {
                    return try? transform(f)
                } else {
                    return try Mapper.catchTransformErrorAndFillKeyPath([index]) {
                        try transform(f)
                    }
                }
            }
        }
    }
}

// methods for utils
extension Mapper {
    
    /// parse JSON string to JSONObject
    public static func parseJSONString(_ string: String) throws -> Any {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) else {
            throw Error.transformFailed(keyPath: [], value: string, fromType: String.self, toType: Data.self)
        }
        return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
    }
    
    public static func cast<T>(_ from: Any, to: T.Type) throws -> T {
        guard let result = from as? T else {
            throw Error.typeMismatch(keyPath: [], value: from, fromType: type(of: from), toType: T.self)
        }
        return result
    }
    
    public static func required<F, T>(from: F, transform: (F) throws -> T?) throws -> T {
        guard let result = try transform(from) else {
            throw Error.transformFailed(keyPath: [], value: from, fromType: F.self, toType: T.self)
        }
        return result
    }
    
    /// generate Mapper at keyPath. NSNull at keyPath is treated as undefined
    public func mapper(at keyPath: MappingKeyPathConvertible...) throws -> Mapper {
        let raw = try rawField(at: keyPath)
        guard !(raw is NSNull) else {
            throw Error.missingField(keyPath: keyPath.asMappingKeyPaths(), json: json)
        }
        return Mapper(json: raw, context: context)
    }
    
    /// generate Mapper at keyPath. NSNull at keyPath is treated as undefined
    public func optionalMapper(at keyPath: MappingKeyPathConvertible...) throws -> Mapper? {
        guard let raw = try optionalRawField(at: keyPath, pathNullAsMissing: true) else {
            return nil
        }
        guard !(raw is NSNull) else {
            return nil
        }
        return Mapper(json: raw, context: context)
    }
    
    /// generate Mapper at keyPath. NSNull at keyPath is treated as undefined
    public func mapper(at keyPath: MappingKeyPathConvertible..., default: Any) throws -> Mapper {
        var raw = try optionalRawField(at: keyPath, pathNullAsMissing: true)
        if raw == nil || raw is NSNull {
            raw = `default`
        }
        guard !(raw is NSNull) else {
            throw Error.missingField(keyPath: keyPath.asMappingKeyPaths(), json: json)
        }
        return Mapper(json: raw!, context: context)
    }
}


// extension Transformable
extension Mapper {
    public func map<P: Transformable>(_ keyPath: MappingKeyPathConvertible...) throws -> P where P == P.TransformTargetType {
        return try map(keyPath, transform: P.transform)
    }
    
    public func map<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., skipFailedItems: Bool = false) throws -> [P] where P == P.TransformTargetType {
        return try map(keyPath, transform: Mapper.wrapAsArrayTransform(skipFailedItems: skipFailedItems, transform: P.transform))
    }
    
    public func map<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: P.Type) throws -> P where P == P.TransformTargetType {
        return try map(keyPath)
    }
    
    public func map<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: [P].Type, skipFailedItems: Bool = false) throws -> [P] where P == P.TransformTargetType {
        return try map(keyPath, skipFailedItems: skipFailedItems)
    }
    
    public func optionalMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true, fieldNullAsMissing: Bool = true) throws -> P? where P == P.TransformTargetType {
        return try optionalMap(keyPath, pathNullAsMissing: pathNullAsMissing, fieldNullAsMissing: fieldNullAsMissing, transform: P.transform)
    }
    
    public func optionalMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true, fieldNullAsMissing: Bool = true, skipFailedItems: Bool = false) throws -> [P]? where P == P.TransformTargetType {
        return try optionalMap(keyPath, pathNullAsMissing: pathNullAsMissing, fieldNullAsMissing: fieldNullAsMissing,
                               transform: Mapper.wrapAsArrayTransform(skipFailedItems: skipFailedItems, transform: P.transform))
    }
    
    public func optionalMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: P.Type, pathNullAsMissing: Bool = true, fieldNullAsMissing: Bool = true) throws -> P? where P == P.TransformTargetType {
        return try optionalMap(keyPath, pathNullAsMissing: pathNullAsMissing, fieldNullAsMissing: fieldNullAsMissing)
    }
    
    public func optionalMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: [P].Type, pathNullAsMissing: Bool = true, fieldNullAsMissing: Bool = true, skipFailedItems: Bool = false) throws -> [P]? where P == P.TransformTargetType {
        return try optionalMap(keyPath, pathNullAsMissing: pathNullAsMissing, fieldNullAsMissing: fieldNullAsMissing, skipFailedItems: skipFailedItems)
    }
}

// extension Nullable
extension Mapper {
    public func nullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible...) throws -> Nullable<P> where P == P.TransformTargetType {
        return try nullableMap(keyPath, transform: P.transform)
    }
    
    public func nullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., skipFailedItems: Bool = false) throws -> Nullable<[P]> where P == P.TransformTargetType {
        return try nullableMap(keyPath, transform: Mapper.wrapAsArrayTransform(skipFailedItems: skipFailedItems, transform: P.transform))
    }
    
    public func nullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: P.Type) throws -> Nullable<P> where P == P.TransformTargetType {
        return try nullableMap(keyPath)
    }
    
    public func nullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: [P].Type, skipFailedItems: Bool = false) throws -> Nullable<[P]> where P == P.TransformTargetType {
        return try nullableMap(keyPath, skipFailedItems: skipFailedItems)
    }
    
    public func optionalNullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true) throws -> Nullable<P>? where P == P.TransformTargetType {
        return try optionalNullableMap(keyPath, pathNullAsMissing: pathNullAsMissing, transform: P.transform)
    }
    
    public func optionalNullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., pathNullAsMissing: Bool = true, skipFailedItems: Bool = false) throws -> Nullable<[P]>? where P == P.TransformTargetType {
        return try optionalNullableMap(keyPath, pathNullAsMissing: pathNullAsMissing, transform: Mapper.wrapAsArrayTransform(skipFailedItems: skipFailedItems, transform: P.transform))
    }
    
    public func optionalNullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: P.Type, pathNullAsMissing: Bool = true) throws -> Nullable<P>? where P == P.TransformTargetType {
        return try optionalNullableMap(keyPath, pathNullAsMissing: pathNullAsMissing)
    }
    
    public func optionalNullableMap<P: Transformable>(_ keyPath: MappingKeyPathConvertible..., type: [P].Type, pathNullAsMissing: Bool = true, skipFailedItems: Bool = false) throws -> Nullable<[P]>? where P == P.TransformTargetType {
        return try optionalNullableMap(keyPath, pathNullAsMissing: pathNullAsMissing, skipFailedItems: skipFailedItems)
    }
}
