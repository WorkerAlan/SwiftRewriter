import SwiftAST

/// A wrapper for querying the type system context for specific type knowledges
public protocol TypeSystem {
    /// Returns `true` if `type` represents a numerical type (int, float, CGFloat, etc.)
    func isNumeric(_ type: SwiftType) -> Bool
    
    /// Returns `true` is an integer (signed or unsigned) type
    func isInteger(_ type: SwiftType) -> Bool
    
    /// Gets a known type with a given name from this type system
    func knownTypeWithName(_ name: String) -> KnownType?
    
    /// Returns `true` if a type represented by a given type name is a subtype of
    /// another type
    func isType(_ typeName: String, subtypeOf supertypeName: String) -> Bool
}

/// Standard type system implementation
public class DefaultTypeSystem: TypeSystem {
    var types: [KnownType] = []
    
    public init() {
        registerInitialKnownTypes()
    }
    
    public func addType(_ type: KnownType) {
        types.append(type)
    }
    
    public func knownTypeWithName(_ name: String) -> KnownType? {
        return types.first { $0.typeName == name }
    }
    
    public func isType(_ typeName: String, subtypeOf supertypeName: String) -> Bool {
        guard let type = knownTypeWithName(typeName) else {
            return false
        }
        guard let supertype = knownTypeWithName(supertypeName) else {
            return false
        }
        
        var current: KnownType? = type
        while let c = current {
            if c.typeName == supertype.typeName {
                return true
            }
            
            current = c.supertype?.asKnownType
        }
        
        return false
    }
    
    public func isNumeric(_ type: SwiftType) -> Bool {
        if isInteger(type) {
            return true
        }
        
        switch type {
        case .float, .double, .cgFloat:
            return true
        case .typeName("Float80"):
            return true
        default:
            return false
        }
    }
    
    public func isInteger(_ type: SwiftType) -> Bool {
        switch type {
        case .int, .uint:
            return true
        case .typeName("Int64"), .typeName("Int32"), .typeName("Int16"), .typeName("Int8"):
            return true
        case .typeName("UInt64"), .typeName("UInt32"), .typeName("UInt16"), .typeName("UInt8"):
            return true
        default:
            return false
        }
    }
}

extension DefaultTypeSystem {
    /// Initializes the default known types
    func registerInitialKnownTypes() {
        let nsObject =
            KnownTypeBuilder(typeName: "NSObject")
                .addingConstructor()
                .build()
        
        let nsArray =
            KnownTypeBuilder(typeName: "NSArray", supertype: nsObject)
                .build()
        
        let nsMutableArray =
            KnownTypeBuilder(typeName: "NSMutableArray", supertype: nsArray)
                .addingMethod(withSignature:
                    FunctionSignature(name: "addObject",
                                      parameters: [
                                        ParameterSignature(label: "_", name: "object", type: .anyObject)],
                                      returnType: .void,
                                      isStatic: false
                    )
                )
                .build()
        
        let nsDictionary =
            KnownTypeBuilder(typeName: "NSDictionary", supertype: nsObject)
                .build()
        
        let nsMutableDictionary =
            KnownTypeBuilder(typeName: "NSMutableDictionary", supertype: nsDictionary)
                .addingMethod(withSignature:
                    FunctionSignature(name: "setObject",
                                      parameters: [
                                        ParameterSignature(label: "_", name: "anObject", type: .anyObject),
                                        ParameterSignature(label: "forKey", name: "aKey", type: .anyObject)],
                                      returnType: .void,
                                      isStatic: false
                    )
                )
                .build()
        
        addType(nsObject)
        addType(nsArray)
        addType(nsMutableArray)
        addType(nsDictionary)
        addType(nsMutableDictionary)
    }
}

/// An extension over the default type system that enables using an intention
/// collection to search for types
class IntentionCollectionTypeSystem: DefaultTypeSystem {
    var intentions: IntentionCollection
    
    init(intentions: IntentionCollection) {
        self.intentions = intentions
        super.init()
    }
    
    override func knownTypeWithName(_ name: String) -> KnownType? {
        // TODO: Create a lazy KnownType implementer that searches for requested
        // members on-demand every time the respective KnownType members are requested.
        
        if let type = super.knownTypeWithName(name) {
            return type
        }
        
        // Search in type intentions
        let types = intentions.typeIntentions().map { $0 as KnownType }.filter { $0.typeName == name }
        guard types.count > 0 else {
            return nil
        }
        
        // Single type found: Avoid complex merge operations and return it as is.
        if types.count == 0 {
            return types[0]
        }
        
        var typeBuilder = KnownTypeBuilder(typeName: name)
        
        for type in types {
            // Search supertypes known here
            switch type.supertype {
            case .typeName(let supertypeName)?:
                typeBuilder =
                    typeBuilder.settingSupertype(super.knownTypeWithName(supertypeName))
            case .knownType(let supertype)?:
                typeBuilder =
                    typeBuilder.settingSupertype(supertype)
            default:
                break
            }
            
            for prot in type.knownProtocolConformances {
                typeBuilder =
                    typeBuilder.addingProtocolConformance(protocolName: prot.protocolName)
            }
            
            for prop in type.knownProperties {
                typeBuilder =
                    typeBuilder.addingProperty(named: prop.name, storage: prop.storage)
            }
            
            for ctor in type.knownConstructors {
                typeBuilder =
                    typeBuilder.addingConstructor(withParameters: ctor.parameters)
            }
            
            for method in type.knownMethods {
                typeBuilder =
                    typeBuilder.addingMethod(withSignature: method.signature)
            }
        }
        
        return typeBuilder.build()
    }
}