/// Represents a centralization point where all source code generation intentions
/// are placed and queried for.
public class IntentionCollection {
    private var _intentions: [FileGenerationIntention] = []
    
    public init() {
        
    }
    
    public func fileIntentions() -> [FileGenerationIntention] {
        return _intentions
    }
    
    /// Performs a full search of all types intended to be created on all files.
    public func typeIntentions() -> [TypeGenerationIntention] {
        return _intentions.flatMap { $0.typeIntentions }
    }
    
    /// Gets all nominal class generation intentions across all files
    public func classIntentions() -> [ClassGenerationIntention] {
        return _intentions.flatMap { $0.classIntentions }
    }
    
    /// Gets all extension intentions across all files
    public func extensionIntentions() -> [ClassExtensionGenerationIntention] {
        return _intentions.flatMap { $0.extensionIntentions }
    }
    
    /// Gets all protocols intended to be created on all files.
    public func protocolIntentions() -> [ProtocolGenerationIntention] {
        return _intentions.flatMap { $0.protocolIntentions }
    }
    
    public func intentionFor(fileNamed name: String) -> FileGenerationIntention? {
        return fileIntentions().first { $0.filePath == name }
    }
    
    public func addIntention(_ intention: FileGenerationIntention) {
        _intentions.append(intention)
    }
    
    public func removeIntention(where predicate: (FileGenerationIntention) -> Bool) {
        for (i, item) in _intentions.enumerated() {
            if predicate(item) {
                _intentions.remove(at: i)
                return
            }
        }
    }
    
    public func removeIntentions(where predicate: (FileGenerationIntention) -> Bool) {
        for (i, item) in _intentions.enumerated().reversed() {
            if predicate(item) {
                _intentions.remove(at: i)
            }
        }
    }
}
