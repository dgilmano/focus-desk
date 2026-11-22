import XCTest
@testable import FocusDeskCore

final class NextStepChecklistTests: XCTestCase {
    func testPlainAndNumberedStepsKeepOrderAndInlineMarkdown() {
        let list = NextStepChecklist("Собрать **логи**\n\n1. Сравнить версии\n2) Отправить [отчёт](https://example.com)\n")
        XCTAssertEqual(list.items.map(\.text), ["Собрать **логи**", "Сравнить версии", "Отправить [отчёт](https://example.com)"])
        XCTAssertTrue(list.items.allSatisfy { !$0.isCompleted })
        XCTAssertTrue(NextStepChecklist("\n \t\r\n").items.isEmpty)
        XCTAssertEqual(NextStepChecklist("[x](https://example.com)").items.first?.text, "[x](https://example.com)")
    }

    func testRenameOnlyReplacesTheChosenLabelAndKeepsCheckboxAndLineEndings() {
        let source = "1. Повтор\r\n\r\n  - [X]  Повтор  \r\n**Отправить**"
        let list = NextStepChecklist(source)
        XCTAssertEqual(list.renaming(1, to: "  Сверить **логи**  "), "1. Повтор\r\n\r\n  - [X]  Сверить **логи**  \r\n**Отправить**")
        XCTAssertNil(list.renaming(3, to: "Oops"))
        XCTAssertNil(list.renaming(0, to: "   "))
        XCTAssertNil(list.renaming(0, to: "Two\nlines"))
        for literal in ["1. Number", "[x] Literal", "- Another list"] {
            for original in ["Draft", "1. Draft", "- [X] Draft"] {
                let rewritten = NextStepChecklist(original).renaming(0, to: literal)
                let step = NextStepChecklist(rewritten ?? "").items.first
                XCTAssertEqual(step?.text, literal)
                XCTAssertEqual(step?.isCompleted, original.contains("[X]"))
            }
        }
    }

    func testRemovingStepKeepsOtherLinesAndTheirFormatting() {
        let original = "  1. [X] **Готово**  \r\n\r\n  • Шаг 👋🏽\r\n  • Шаг 👋🏽\n"
        let list = NextStepChecklist(original)
        XCTAssertEqual(list.items.map(\.isCompleted), [true, false, false])
        XCTAssertEqual(list.removing(0), "\r\n  • Шаг 👋🏽\r\n  • Шаг 👋🏽\n")
        XCTAssertEqual(list.removing(1), "  1. [X] **Готово**  \r\n\r\n  • Шаг 👋🏽\n")
        XCTAssertEqual(list.removing(2), "  1. [X] **Готово**  \r\n\r\n  • Шаг 👋🏽\r\n")
        XCTAssertEqual(NextStepChecklist("Первый\r\nПоследний").removing(1), "Первый")
        XCTAssertEqual(NextStepChecklist("Открыть отчёт").removing(0), "")
        XCTAssertEqual(list.removing(3), original)
    }
}
