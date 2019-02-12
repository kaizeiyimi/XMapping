//
//  ModelMappable.swift
//  Mapping
//
//  Created by kaizei on 16/8/16.
//  Copyright © 2016年 kaizei.yimi. All rights reserved.
//

import Foundation


public protocol ModelMappable: Transformable {
    init(mapper: Mapper) throws
}

extension ModelMappable {
    
    public static func transform(_ fromValue: Mapper) throws -> Self {
        return try self.init(mapper: fromValue)
    }
    
}

extension ModelMappable {

    public static func mapFrom(_ jsonDict: [String: Any], context: Any? = nil) throws -> Self {
        return try self.init(mapper: Mapper(json: jsonDict, context: context))
    }
    
    public static func mapFrom(_ jsonArray: [[String: Any]], skipFailedItems: Bool = false, context: Any? = nil) throws -> [Self] {
        if skipFailedItems {
            return jsonArray.compactMap { try? mapFrom($0, context: context) }
        } else {
            return try jsonArray.map{ try mapFrom($0, context: context) }
        }
    }

}


extension CodingUserInfoKey {
    enum Mapper {
        static let context = CodingUserInfoKey(rawValue: "CodingUserInfoKey.kaizei.yimi.Mapper.context.key")
    }
}

public protocol ModelDecodeMappable: Transformable, Decodable {
    static func makeJSONDecoder(context: Any?) -> JSONDecoder
}

extension ModelDecodeMappable {
    public static func makeJSONDecoder(context: Any?) -> JSONDecoder {
        let decoder = JSONDecoder()
        if let context = context, let contextKey = CodingUserInfoKey.Mapper.context {
            decoder.userInfo[contextKey] = context
        }
        return decoder
    }
}

extension ModelDecodeMappable {
    public static func transform(_ fromValue: Mapper) throws -> Self {
        let decoder = makeJSONDecoder(context: fromValue.context)
        do {
            return try decoder.decode(Self.self, from: try JSONSerialization.data(withJSONObject: fromValue.json))
        } catch let decodingError as DecodingError {
            func convert(_ codingKey: CodingKey) -> MappingKeyPath {
                if let intValue = codingKey.intValue {
                    return .index(intValue)
                } else {
                    return .key(codingKey.stringValue)
                }
            }
            
            // convert decoding error to mapping error
            switch decodingError {
            case let .keyNotFound(lastKey, ctx):
                let keyPath = (ctx.codingPath + [lastKey]).map(convert)
                throw Mapper.Error.missingField(keyPath: keyPath, json: fromValue.json)
            case let .valueNotFound(toType, ctx):
                let keyPath = ctx.codingPath.map(convert)
                throw Mapper.Error.transformFailed(keyPath: keyPath, value: NSNull(), fromType: NSNull.self, toType: toType)
            case let .typeMismatch(toType, ctx):
                let keyPath = ctx.codingPath.map(convert)
                let rawFieldKeyPath = keyPath.map{ component -> MappingKeyPathConvertible in
                    switch component {
                    case let .key(key): return key
                    case let .index(index): return index
                    }
                }
                let value: Any = (try? fromValue.rawField(at: rawFieldKeyPath)) ?? ctx.debugDescription
                throw Mapper.Error.typeMismatch(keyPath: keyPath, value: value, fromType: type(of: value), toType: toType)
            case let .dataCorrupted(ctx):
                let keyPath = ctx.codingPath.map(convert)
                throw Mapper.Error.transformFailed(keyPath: keyPath, value: fromValue.json, fromType: type(of: fromValue.json), toType: [String: Any].self)
            }
        }
    }
}
