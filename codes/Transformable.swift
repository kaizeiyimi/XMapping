//
//  Transformable.swift
//  Mapping
//
//  Created by kaizei on 16/8/16.
//  Copyright © 2016年 kaizei.yimi. All rights reserved.
//

import UIKit
import Foundation

// MARK: - Transformable
public protocol Transformable {
    
    // should be JSON supported types, or else will trigger type mismatch MapError.
    associatedtype TransformOriginType = Self
    associatedtype TransformTargetType = Self
    
    static func transform(_ fromValue: TransformOriginType) throws -> TransformTargetType
    
}

extension Transformable {
    
    /// default only check type.
    public static func transform(_ fromValue: TransformOriginType) throws -> TransformTargetType {
        guard let property = fromValue as? TransformTargetType else {
            throw Mapper.Error.typeMismatch(keyPath: [], value: fromValue, fromType: TransformOriginType.self, toType: TransformTargetType.self)
        }
        return property
    }
    
}

// MARK: - NSNull & SomeValue
/// json from js has undefined, null & value. in most cases, undefined & null is the same, but not always.
public enum Nullable<Wrapped> {
    case null
    case some(Wrapped)

    public var value: Wrapped? {
        if case let .some(value) = self {
            return value
        }
        return nil
    }

    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    public var hasValue: Bool {
        return !isNull
    }

    public init(_ value: Wrapped) {
        self = .some(value)
    }
}


// MARK: - String
extension String: Transformable {}

// MARK: - Bool
extension Bool: Transformable {}

// MARK: - Numbers
public protocol StringTransformable {
    static func transformString(_ value: String) throws -> Self
}

extension Int: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> Int {
        return try Mapper.required(from: value) { Int($0) }
    }
}
extension Int64: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> Int64 {
        return try Mapper.required(from: value) { Int64($0) }
    }
}
extension UInt: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> UInt {
        return try Mapper.required(from: value) { UInt($0) }
    }
}
extension UInt64: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> UInt64 {
        return try Mapper.required(from: value) { UInt64($0) }
    }
}
extension Float: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> Float {
        return try Mapper.required(from: value) { Float($0) }
    }
}
extension Double: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> Double {
        return try Mapper.required(from: value) { Double($0) }
    }
}
extension CGFloat: Transformable, StringTransformable {
    public static func transformString(_ value: String) throws -> CGFloat {
        return try Mapper.required(from: value) { Double($0).flatMap{ CGFloat($0) } }
    }
}

// MARK: - URL
extension URL: Transformable {
    
    public static func transform(_ fromValue: String) throws -> URL {
        let fromValue = fromValue.removingPercentEncoding?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromValue
        guard let url = URL(string: fromValue) else {
            throw Mapper.Error.transformFailed(keyPath: [], value: fromValue, fromType: String.self, toType: URL.self)
        }
        return url
    }
    
}


extension Mapper {
    
    /// you should setup sharedDateFormatter as early as possible.
    public static var sharedDateFormatter: () -> DateFormatter = { return DateFormatter() }
    
    // borrowed from swiftMoment and modified a little
    public static var dateFormatterFormats = [
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'",
        "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ssZZZZZ",
        "yyyy'-'MM'-'dd' 'HH':'mm':'ss'Z'",
        "yyyy'-'MM'-'dd' 'HH':'mm':'ss'.'SSS'Z'",
        "yyyy-MM-dd HH:mm:ss.SSSZ",
        "yyyy-MM-dd",
        "yyyyMMdd",
        "h:mm:ss A",
        "h:mm A",
        "MM/dd/yyyy",
        "MMMM d, yyyy",
        "MMMM d, yyyy LT",
        "dddd, MMMM D, yyyy LT",
        "yyyyyy-MM-dd",
        "GGGG-[W]WW-E",
        "GGGG-[W]WW",
        "yyyy-ddd",
        "HH:mm:ss.SSSS",
        "HH:mm:ss",
        "HH:mm",
        "HH"
    ]
}

extension Date {
    
    /// uses the sharedDateFormatter
    public static func transformString(_ string: String) throws -> Date {
        let formatter = Mapper.sharedDateFormatter()
        for format in Mapper.dateFormatterFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        throw Mapper.Error.transformFailed(keyPath: [], value: string, fromType: String.self, toType: Date.self)
    }
    
    public static func transformMilliSecond(_ ms: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(ms / 1000))
    }
    
    public static func transformSecond(_ s: Double) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(s))
    }
}


// MARK: - Enum Transformable

/// enumeration representing server's cases should confirm to this protocol.
/// custom your convert function if needed.
public protocol EnumerationTransformable: RawRepresentable, Transformable {
    static func convert(rawValue: RawValue) -> Self?
}

extension EnumerationTransformable  {
    public static func transform(_ fromValue: RawValue) throws -> Self {
        guard let result = self.convert(rawValue: fromValue) else {
            throw Mapper.Error.missingCase(keyPath: [], value: fromValue, toType: Self.self)
        }
        return result
    }
    
    public static func convert(rawValue: RawValue) -> Self? {
        return self.init(rawValue: rawValue)
    }
}


public func compatible<A, B>(_ typeA: A.Type, _ convert: @escaping (A) throws -> B) -> (Any) throws -> B where B: Transformable, B == B.TransformTargetType {
    return { value -> B in
        switch value {
        case let v as B.TransformOriginType:
            return try B.transform(v)
        case let a as A:
            return try convert(a)
            
        default:
            throw Mapper.Error.transformFailed(keyPath: [], value: value, fromType: type(of: value), toType: B.self)
        }
    }
}


// raw type transform
public func rawTransform<J>(_ type:J.Type) ->  (J) -> J {
    return { $0 }
}
