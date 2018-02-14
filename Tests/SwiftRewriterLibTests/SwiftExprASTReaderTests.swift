import XCTest
import Antlr4
import ObjcParser
import ObjcParserAntlr
import SwiftRewriterLib

class SwiftExprASTReaderTests: XCTestCase {
    var tokens: CommonTokenStream!
    
    func testConstants() {
        assert(objcExpr: "1", readsAs: .constant(.int(1)))
        assert(objcExpr: "1ulL", readsAs: .constant(.int(1)))
        assert(objcExpr: "1.0e2", readsAs: .constant(.float(1e2)))
        assert(objcExpr: "1f", readsAs: .constant(.float(1)))
        assert(objcExpr: "1F", readsAs: .constant(.float(1)))
        assert(objcExpr: "1d", readsAs: .constant(.float(1)))
        assert(objcExpr: "1D", readsAs: .constant(.float(1)))
        assert(objcExpr: "true", readsAs: .constant(.boolean(true)))
        assert(objcExpr: "YES", readsAs: .constant(.boolean(true)))
        assert(objcExpr: "false", readsAs: .constant(.boolean(false)))
        assert(objcExpr: "NO", readsAs: .constant(.boolean(false)))
        assert(objcExpr: "0123", readsAs: .constant(.octal(0o123)))
        assert(objcExpr: "0x123", readsAs: .constant(.hexadecimal(0x123)))
        assert(objcExpr: "\"abc\"", readsAs: .constant(.string("abc")))
    }
    
    func testFunctionCall() {
        assert(objcExpr: "print()", readsAs: .postfix(.identifier("print"), .functionCall(arguments: [])))
        assert(objcExpr: "a.method()", readsAs: .postfix(.postfix(.identifier("a"), .member("method")), .functionCall(arguments: [])))
        assert(objcExpr: "print(123, 456)", readsAs: .postfix(.identifier("print"), .functionCall(arguments: [.unlabeled(.constant(123)),
                                                                                                              .unlabeled(.constant(456))])))
    }
    
    func testSubscript() {
        assert(objcExpr: "aSubscript[1]", readsAs: .postfix(.identifier("aSubscript"), .subscript(.constant(1))))
    }
    
    func testMemberAccess() {
        assert(objcExpr: "aSubscript.def", readsAs: .postfix(.identifier("aSubscript"), .member("def")))
    }
    
    func testSelectorMessage() {
        assert(objcExpr: "[a selector]", readsAs: .postfix(.postfix(.identifier("a"), .member("selector")), .functionCall(arguments: [])))
        
        assert(objcExpr: "[a selector:1, 2, 3]",
               readsAs: .postfix(.postfix(.identifier("a"), .member("selector")),
                                 .functionCall(arguments: [.unlabeled(.constant(1)), .unlabeled(.constant(2)), .unlabeled(.constant(3))])))
        
        assert(objcExpr: "[a selector:1 c:2, 3]",
               readsAs: .postfix(.postfix(.identifier("a"), .member("selector")),
                                 .functionCall(arguments: [.unlabeled(.constant(1)), .labeled("c", .constant(2)), .unlabeled(.constant(3))])))
    }
    
    func testCastExpression() {
        assert(objcExpr: "(NSString*)abc",
               readsAs: .cast(.identifier("abc"), type: .pointer(.struct("NSString"))))
    }
    
    func testAssignmentWithMethodCall() {
        let exp =
            Expression.postfix(
                .postfix(
                    .postfix(
                        .postfix(.identifier("UIView"), .member("alloc")),
                        .functionCall(arguments: [])), .member("initWithFrame")), .functionCall(arguments:
                            [
                            .unlabeled(
                                .postfix(.identifier("CGRectMake"),
                                         .functionCall(arguments:
                                            [
                                            .unlabeled(.constant(0)),
                                            .unlabeled(.identifier("kCPDefaultTimelineRowHeight")),
                                            .unlabeled(.postfix(.identifier("self"), .member("ganttWidth"))),
                                            .unlabeled(.postfix(.identifier("self"), .member("ganttHeight")))
                                            ])))
                            ]))
        
        assert(objcExpr: """
            _cellContainerView =
                [[UIView alloc] initWithFrame:CGRectMake(0, kCPDefaultTimelineRowHeight, self.ganttWidth, self.ganttHeight)];
            """,
            readsAs: .assignment(lhs: .identifier("_cellContainerView"), op: .assign, rhs: exp))
    }
    
    func testPostfixStructAccessWithAssignment() {
        let exp =
            Expression
                .assignment(lhs: .postfix(.identifier("self"), .member("_ganttEndDate")),
                            op: .assign,
                            rhs: .identifier("ganttEndDate"))
        
        assert(objcExpr: "self->_ganttEndDate = ganttEndDate",
               readsAs: exp)
    }
    
    func assert(objcExpr: String, readsAs expected: Expression, file: String = #file, line: Int = #line) {
        let input = ANTLRInputStream(objcExpr)
        let lxr = ObjectiveCLexer(input)
        tokens = CommonTokenStream(lxr)
        
        let sut = SwiftExprASTReader()
        
        do {
            let parser = try ObjectiveCParser(tokens)
            let expr = try parser.expression()
            
            let result = expr.accept(sut)
            
            if result != expected {
                var resStr = "nil"
                var expStr = ""
                
                if let result = result {
                    dump(result, to: &resStr)
                }
                dump(expected, to: &expStr)
                
                recordFailure(withDescription: """
                    Failed: Expected to read Objective-C expression
                    \(objcExpr)
                    as
                    \(expStr)
                    but read as
                    \(resStr)
                    """, inFile: file, atLine: line, expected: false)
            }
        } catch {
            recordFailure(withDescription: "Unexpected error(s) parsing objective-c: \(error)", inFile: file, atLine: line, expected: false)
        }
    }
}