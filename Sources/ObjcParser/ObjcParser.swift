import Foundation
import MiniLexer
import GrammarModels

public class ObjcParser {
    let lexer: Lexer
    let context: NodeCreationContext
    
    public let diagnostics: Diagnostics
    
    public init(string: String) {
        lexer = Lexer(input: string)
        context = NodeCreationContext()
        diagnostics = Diagnostics()
        
        // TODO: Remove-me: this should be done at a parseGlobalNamespace() or similar
        context.pushContext(nodeType: GlobalContextNode.self)
    }
    
    public convenience init(filePath: String, encoding: String.Encoding = .utf8) throws {
        let text = try String(contentsOfFile: filePath, encoding: encoding)
        self.init(string: text)
    }
    
    /// Parses an Objective-C class interface
    ///
    ///     classInterface = '@interface' className (':' superclassName)? protocolRefList? ivars? interfaceDeclList? '@end';
    ///
    public func parseClassInerfaceNode() throws {
        // @interface Name [: SuperClass] [<ProtocolList>]
        //
        // @end
        
        let classNode: ObjcClassInterface = context.pushContext()
        defer {
            context.popContext()
        }
        
        lexer.skipWhitespace()
        
        // Consume @interface
        try parseKeyword("@interface", onMissing: "Expected @interface to start class declaration")
        
        // Class name
        classNode.identifier = .valid(try parseIdentifierNode())
        
        lexer.skipWhitespace()
        
        // Super class name
        if try lexer.peek() == ":" {
            // Record ':'
            try parseTokenNode(":")
            
            // Record superclass name
            try parseSuperclassNameNode()
        }
        
        // Consume interface declarations
        _=lexer.performGreedyRounds { (lexer, _) -> Bool in
            var isEnd = false
            
            lexer.skipWhitespace()
            
            try lexer.matchFirst(withEither: { lexer in
                try self.parseKeyword("@end", onMissing: "Expected @end to end class declaration")
                
                isEnd = true
            }, { _ in
                try self.parsePropertyNode()
            })
            
            return !isEnd
        }
    }
    
    func parsePropertyNode() throws {
        let prop = ObjcClassInterface.Property(type: .placeholder, identifier: .placeholder)
        context.pushContext(node: prop)
        defer {
            context.popContext()
        }
        
        // @property [(<Modifiers>)] <Type> <Name>;
        lexer.skipWhitespace()
        
        // @property
        let range = startRange()
        try parseKeyword("@property", onMissing: "Expected @property declaration")
        lexer.skipWhitespace()
        
        // Modifiers
        if lexer.safeIsNextChar(equalTo: "(") {
            try parsePropertyModifiersListNode()
            lexer.skipWhitespace()
        }
        
        // Type
        prop.type = try asNodeRef(try parseTypeNameNode(), onPanic: {
            lexer.advance(until: { Lexer.isIdentifierLetter($0) || $0 == ";" || $0 == "@" })
        })
        
        lexer.skipWhitespace()
        
        // Name
        prop.identifier = try asNodeRef(try parseIdentifierNode(), onPanic: {
            lexer.advance(until: { $0 == ";" || $0 == "@" })
        })
        
        // ;
        try parseTokenNode(";", onMissing: "Expected ';' to end property declaration")
        
        prop.location = range.makeRange()
    }
    
    func parsePropertyModifiersListNode() throws {
        func parsePropertyModifier() throws {
            let range = startRange()
            let name = try lexer.lexIdentifier()
            
            let node = ObjcClassInterface.PropertyModifier(name: String(name), location: range.makeRange())
            context.addChildNode(node)
        }
        
        let node = context.pushContext(nodeType: ObjcClassInterface.PropertyModifierList.self)
        defer {
            context.popContext()
        }
        
        try parseTokenNode("(")
        
        var expectsItem = true
        while !lexer.isEof() {
            lexer.skipWhitespace()
            
            if lexer.safeIsNextChar(equalTo: ")") {
                break
            }
            
            expectsItem = false
            
            if lexer.safeIsNextChar(equalTo: ",") {
                try parseTokenNode(",")
                expectsItem = true
                continue
            }
            
            try parsePropertyModifier()
        }
        
        // Closed list after comma
        if expectsItem {
            diagnostics.error("Expected modifier parameter after comma", location: location())
            // Panic and end list here
            lexer.skipWhitespace()
        }
        
        try parseTokenNode(")")
    }
    
    func parseObjcType() throws -> TypeNameNode.ObjcType {
        // Here we simplify the grammar for types as:
        // TypeName: IDENTIFIER ('<' TypeName '>')? '*'?
        
        var type: TypeNameNode.ObjcType
        
        let typeName = String(try lexer.lexIdentifier())
        
        // '<' : Generic type specifier
        if lexer.withTemporaryIndex(changes: { lexer.skipWhitespace(); return lexer.safeIsNextChar(equalTo: "<") }) {
            if typeName == "id" {
                let types = try _parseCommaSeparatedList(braces: "<", ">", itemParser: lexer.lexIdentifier)
                type = .id(protocols: types.map { String($0) })
            } else {
                let types = try _parseCommaSeparatedList(braces: "<", ">", itemParser: parseObjcType)
                type = .generic(typeName, parameters: types)
            }
        } else {
            type = .struct(typeName)
        }
        
        // '*' : Pointer
        if lexer.withTemporaryIndex(changes: { lexer.skipWhitespace(); return lexer.safeIsNextChar(equalTo: "*") }) {
            lexer.skipWhitespace()
            try lexer.advance()
            type = .pointer(type)
        }
        
        return type
    }
    
    func parseTypeNameNode(onMissing message: String = "Expected type name") throws -> TypeNameNode {
        lexer.skipWhitespace()
        
        let range = startRange()
        do {
            return try lexer.rewindOnFailure {
                let type = try parseObjcType()
                
                return TypeNameNode(type: type, location: range.makeRange())
            }
        } catch {
            diagnostics.error(message, location: location())
            throw error
        }
    }
    
    func parseIdentifierNode(onMissing message: String = "Expected identifier") throws -> Identifier {
        lexer.skipWhitespace()
        
        let identRange = startRange()
        do {
            let ident = try lexer.rewindOnFailure { try lexer.lexIdentifier() }
            
            return Identifier(name: String(ident), location: identRange.makeRange())
        } catch {
            diagnostics.error(message, location: location())
            throw error
        }
    }
    
    func parseSuperclassNameNode() throws {
        lexer.skipWhitespace()
        
        let identRange = startRange()
        let ident = try lexer.lexIdentifier()
        let node = ObjcClassInterface.SuperclassName(name: String(ident), location: identRange.makeRange())
        
        context.addChildNode(node)
    }
    
    func parseKeyword(_ keyword: String, onMissing message: String? = nil) throws {
        let range = startRange()
        
        if !lexer.advanceIf(equals: keyword) {
            throw LexerError.syntaxError(message ?? "Expected \(keyword)")
        }
        
        let node = Keyword(name: keyword, location: range.makeRange())
        
        context.addChildNode(node)
    }
    
    func parseTokenNode(_ token: String, onMissing message: String? = nil, addToContext: Bool = true) throws {
        let range = startRange()
        
        if !lexer.advanceIf(equals: token) {
            throw LexerError.syntaxError(message ?? "Expected \(token)")
        }
        
        if addToContext {
            let node = TokenNode(token: token, location: range.makeRange())
            
            context.addChildNode(node)
        }
    }
    
    func startRange() -> RangeMarker {
        return RangeMarker(lexer: lexer)
    }
    
    /// Current lexer's location as a `SourceLocation`.
    func location() -> SourceLocation {
        return .location(lexer.inputIndex)
    }
    
    private func _parseCommaSeparatedList<T>(braces openBrace: Lexer.Atom, _ closeBrace: Lexer.Atom, addTokensToContext: Bool = true, itemParser: () throws -> T) throws -> [T] {
        try parseTokenNode(openBrace.description, addToContext: addTokensToContext)
        
        var expectsItem = true
        var items: [T] = []
        while !lexer.isEof() {
            lexer.skipWhitespace()
            
            // Close brace
            if lexer.safeIsNextChar(equalTo: closeBrace) {
                break
            }
            
            // Item
            let item = try itemParser()
            items.append(item)
            
            expectsItem = false
            
            // Comma separator
            lexer.skipWhitespace()
            if lexer.safeIsNextChar(equalTo: ",") {
                try parseTokenNode(",", addToContext: addTokensToContext)
                expectsItem = true
            }
        }
        
        // Closed list after comma
        if expectsItem {
            diagnostics.error("Expected item after comma", location: location())
            // Panic and end list here
            lexer.skipWhitespace()
        }
        
        try parseTokenNode(closeBrace.description, addToContext: addTokensToContext)
        
        return items
    }
    
    struct RangeMarker {
        let lexer: Lexer
        let index: Lexer.Index
        
        init(lexer: Lexer) {
            self.lexer = lexer
            self.index = lexer.inputIndex
        }
        
        func makeRange() -> SourceRange {
            return .valid(index..<lexer.inputIndex)
        }
        
        func makeLocation() -> SourceLocation {
            return .range(index..<lexer.inputIndex)
        }
    }
}

/// With a throwing, node-returning closure, encapsulate it within a do/catch
/// block and return an `ASTNodeRef.valid` with the resulting node if the
/// operation succeeds, or return `ASTNodeRef.invalid` if the operation fails.
///
/// An optional argument `onPanic` is called when the operation fails to allow the
/// caller to deal with a parsing failure plan in case the operation fails.
func asNodeRef<T: ASTNode>(_ closure: @autoclosure () throws -> T, onPanic: () throws -> () = { }) rethrows -> ASTNodeRef<T> {
    do {
        return .valid(try closure())
    } catch {
        try onPanic()
        return .invalid(InvalidNode())
    }
}