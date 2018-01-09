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
            return jsonArray.flatMap { try? mapFrom($0, context: context) }
        } else {
            return try jsonArray.map{ try mapFrom($0, context: context) }
        }
    }

}
