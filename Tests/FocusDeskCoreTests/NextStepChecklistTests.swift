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
