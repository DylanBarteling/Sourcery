// Generated using Sourcery 2.2.6 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable vertical_whitespace trailing_newline

import Foundation


extension NSCoder {

    @nonobjc func decode(forKey: String) -> String? {
        return self.maybeDecode(forKey: forKey) as String?
    }

    @nonobjc func decode(forKey: String) -> TypeName? {
        return self.maybeDecode(forKey: forKey) as TypeName?
    }

    @nonobjc func decode(forKey: String) -> AccessLevel? {
        return self.maybeDecode(forKey: forKey) as AccessLevel?
    }

    @nonobjc func decode(forKey: String) -> Bool {
        return self.decodeBool(forKey: forKey)
    }

    @nonobjc func decode(forKey: String) -> Int {
        return self.decodeInteger(forKey: forKey)
    }

    func decode<E>(forKey: String) -> E? {
        return maybeDecode(forKey: forKey) as E?
    }

    fileprivate func maybeDecode<E>(forKey: String) -> E? {
        guard let object = self.decodeObject(forKey: forKey) else {
            return nil
        }

        return object as? E
    }

}

extension ArrayType: NSCoding {}

extension AssociatedType: NSCoding {}

extension AssociatedValue: NSCoding {}

extension Attribute: NSCoding {}

extension BytesRange: NSCoding {}


extension ClosureParameter: NSCoding {}

extension ClosureType: NSCoding {}

extension DictionaryType: NSCoding {}


extension EnumCase: NSCoding {}

extension FileParserResult: NSCoding {}

extension GenericParameter: NSCoding {}

extension GenericRequirement: NSCoding {}

extension GenericType: NSCoding {}

extension GenericTypeParameter: NSCoding {}

extension Import: NSCoding {}

extension Method: NSCoding {}

extension MethodParameter: NSCoding {}

extension Modifier: NSCoding {}



extension SetType: NSCoding {}


extension Subscript: NSCoding {}

extension TupleElement: NSCoding {}

extension TupleType: NSCoding {}

extension Type: NSCoding {}

extension TypeName: NSCoding {}

extension Typealias: NSCoding {}

extension Types: NSCoding {}

extension Variable: NSCoding {}

