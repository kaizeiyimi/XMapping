# XMapping

XMapping provides some useful functions for fetching field from JSON and perfroming transformation.

whole logic depends on swift generic and try-catch. with these two powerful thing, handle json can also be easy.

`Mapper` is provided as a wrapper for a JSON object. We all know JSON object can be a `Dictionary`, an `Array`, `Number`, `String`, `Bool` and `Null`,
and no one said a root JSON object should be a `Dictionary`, which means we should check type from root till we get what we want.

when getting something from JSON, we actually mean two step:

1. get a `raw field` at specified `keyPath`.
        a `raw field` is a raw JSON type value, `keyPath` is the path describing how to get the desired field.
        notice that, this `keyPath` is not the same as KVC's keyPath which uses `.` for key separation.  `keyPath` in XMapping is an array containing `String` or `Int`.
2. transfrom the `raw field` to desired Type(String, Double, Date, URL .etc)
        transform is a function that receives a `raw field` value, makes some magic and returns the desired result.

thanks to the well **generic** and **try catch** in swift, check type and report error become very easy.

someone would say why not just use `Codable`? if you really try, you will give up. `Codable` is too simple to fit complicated business logic.

# quick look

say you have a struct `Person`, and want be initialized from a JSON:

```swift
public struct Person: ModelMappable {   // Models should confirm to ModelMappable
    public let id: Int
    public let name: String
    public let avatar: URL?
    public let birthday: Date?
    public let friends: [Person]
    
    init(mapper: Mapper) throws {
        id = try mapper.map("id")
        name = try mapper.map("user_name")
        avatar = try mapper.optionalMap("avatar_url")
        birthday = try mapper.optionalMap("birthday", transform: Date.transformString)  // some free util functions
        friends = try mapper.optionalMap("friends") ?? []
    }
}
```

no magic here.  Let's talk deeper.
`id` and `name` are required fields, so use `map`, corresponding `keyPath` is String `"id"`, String `"user_name"` respectively.
`avatar` is optional, so use `optionalMap`. `optionalMap` tries to get a `String` value at `avatar_url`, and then uses `URL.transform` function to transform the string to `URL`.
`birthday` is almost the same as `avatar`, but a transform function is provides directly.
`friends` is an array of `Person`, we consider using empty array instead of `[Person]?`.


# Details

to be done...

