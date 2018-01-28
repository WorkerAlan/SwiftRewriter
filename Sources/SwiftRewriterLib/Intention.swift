import GrammarModels

/// An intention represents the intent of the code transpiler to generate a
/// file/class/struct/property/etc. with Swift code.
public protocol Intention: Context {
    /// Reference to an AST node that originated this source-code generation
    /// intention
    var source: ASTNode? { get }
}

/// An intention to create a .swift file
public class FileGenerationIntention: Intention {
    /// The intended output file path
    public var filePath: String
    
    /// Gets the types to create on this file.
    private(set) var typeIntentions: [TypeGenerationIntention] = []
    
    /// Gets the global functions to create on this file.
    private(set) var globalFunctionIntentions: [GlobalFunctionGenerationIntention] = []
    
    /// Gets the global variables to create on this file.
    private(set) var globalVariableIntentions: [GlobalVariableGenerationIntention] = []
    
    public var source: ASTNode?
    
    public init(filePath: String) {
        self.filePath = filePath
    }
    
    public func addType(_ intention: TypeGenerationIntention) {
        typeIntentions.append(intention)
    }
    
    public func removeTypes(where predicate: (TypeGenerationIntention) -> Bool) {
        for (i, type) in typeIntentions.enumerated().reversed() {
            if predicate(type) {
                typeIntentions.remove(at: i)
            }
        }
    }
    
    public func addGlobalFunction(_ intention: GlobalFunctionGenerationIntention) {
        globalFunctionIntentions.append(intention)
    }
    
    public func addGlobalVariable(_ intention: GlobalVariableGenerationIntention) {
        globalVariableIntentions.append(intention)
    }
}

/// An intention to generate a global function.
public class GlobalFunctionGenerationIntention: FromSourceIntention {
    
}

/// An intention to generate a global variable.
public class GlobalVariableGenerationIntention: FromSourceIntention {
    public var name: String
    public var type: ObjcType
    public var initialValueExpr: String?
    
    public init(name: String, type: ObjcType, accessLevel: AccessLevel = .internal, source: ASTNode? = nil) {
        self.name = name
        self.type = type
        super.init(accessLevel: accessLevel, source: source)
    }
}