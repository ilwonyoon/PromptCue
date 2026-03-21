import XCTest
@testable import Prompt_Cue

final class ParsedMemoryMarkdownTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ markdown: String) -> [ParsedMemoryMarkdown.Section] {
        ParsedMemoryMarkdown.parse(markdown)
    }

    private func blocks(of markdown: String) -> [ParsedMemoryMarkdown.Block] {
        let sections = parse(markdown)
        return sections.flatMap { $0.blocks }
    }

    // MARK: - Section headers (regression)

    func testSectionHeadersCreateSeparateSections() {
        let sections = parse("## Alpha\n\nHello\n\n## Beta\n\nWorld")
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Alpha")
        XCTAssertEqual(sections[1].title, "Beta")
    }

    func testNoHeaderProducesSingleSectionWithNilTitle() {
        let sections = parse("Just a paragraph.")
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
    }

    func testSectionIDsAreStableAcrossRepeatedParses() {
        let markdown = "## Alpha\n\nHello\n\n## Beta\n\nWorld"

        let first = parse(markdown).map(\.id)
        let second = parse(markdown).map(\.id)

        XCTAssertEqual(first, second)
    }

    func testSectionIDsStayUniqueWhenTitlesRepeat() {
        let markdown = "## Same\n\nAlpha\n\n## Same\n\nBeta"
        let sections = parse(markdown)

        XCTAssertEqual(sections.count, 2)
        XCTAssertNotEqual(sections[0].id, sections[1].id)
    }

    // MARK: - Plain paragraphs (regression)

    func testPlainParagraph() {
        let blks = blocks(of: "Hello world")
        XCTAssertEqual(blks.count, 1)
        if case .paragraph(let text) = blks[0] {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .paragraph, got \(blks[0])")
        }
    }

    func testMultiLineParagraphJoinsWithSpace() {
        let blks = blocks(of: "Line one\nLine two\nLine three")
        XCTAssertEqual(blks.count, 1)
        if case .paragraph(let text) = blks[0] {
            XCTAssertEqual(text, "Line one Line two Line three")
        } else {
            XCTFail("Expected .paragraph")
        }
    }

    // MARK: - Simple bullets (regression)

    func testSimpleBullets() {
        let blks = blocks(of: "- Alpha\n- Beta\n- Gamma")
        XCTAssertEqual(blks.count, 1)
        if case .bullets(let items) = blks[0] {
            XCTAssertEqual(items, ["Alpha", "Beta", "Gamma"])
        } else {
            XCTFail("Expected .bullets")
        }
    }

    // MARK: - Table parsing

    func testBasicTableWithHeadersAndRows() {
        let md = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .table(let table) = blks[0] {
            XCTAssertEqual(table.header, ["Name", "Age"])
            XCTAssertEqual(table.rows.count, 2)
            XCTAssertEqual(table.rows[0], ["Alice", "30"])
            XCTAssertEqual(table.rows[1], ["Bob", "25"])
        } else {
            XCTFail("Expected .table, got \(blks[0])")
        }
    }

    func testTableWithThreeColumns() {
        let md = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        """
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .table(let table) = blks[0] {
            XCTAssertEqual(table.header.count, 3)
            XCTAssertEqual(table.rows[0].count, 3)
        } else {
            XCTFail("Expected .table")
        }
    }

    func testTableWithEmptyCell() {
        let md = """
        | Key | Value |
        |-----|-------|
        | foo |  |
        """
        let blks = blocks(of: md)
        if case .table(let table) = blks[0] {
            // The empty cell may be dropped by filter(!s.isEmpty) — verify row is parsed
            XCTAssertEqual(table.rows.count, 1)
            XCTAssertEqual(table.rows[0][0], "foo")
        } else {
            XCTFail("Expected .table")
        }
    }

    func testTableCellsWithInlineBoldMarkdown() {
        let md = """
        | Header |
        |--------|
        | **bold** |
        """
        let blks = blocks(of: md)
        if case .table(let table) = blks[0] {
            XCTAssertEqual(table.rows[0][0], "**bold**")
        } else {
            XCTFail("Expected .table")
        }
    }

    func testTableCellsWithInlineCodeMarkdown() {
        let md = """
        | Header |
        |--------|
        | `code` |
        """
        let blks = blocks(of: md)
        if case .table(let table) = blks[0] {
            XCTAssertEqual(table.rows[0][0], "`code`")
        } else {
            XCTFail("Expected .table")
        }
    }

    func testTableRequiresAtLeastTwoLines() {
        // Single header line with no separator → not parsed as table
        let md = "| A | B |"
        let blks = blocks(of: md)
        // Should not produce a table block (only header line, no separator)
        let hasTable = blks.contains { if case .table = $0 { return true }; return false }
        XCTAssertFalse(hasTable, "Single-line table should not be parsed as a table block")
    }

    // MARK: - Code block parsing

    func testCodeBlockWithLanguageTag() {
        let md = "```swift\nlet x = 1\n```"
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .codeBlock(let language, let code) = blks[0] {
            XCTAssertEqual(language, "swift")
            XCTAssertEqual(code, "let x = 1")
        } else {
            XCTFail("Expected .codeBlock")
        }
    }

    func testCodeBlockWithoutLanguageTag() {
        let md = "```\nsome code\n```"
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .codeBlock(let language, let code) = blks[0] {
            XCTAssertNil(language)
            XCTAssertEqual(code, "some code")
        } else {
            XCTFail("Expected .codeBlock")
        }
    }

    func testCodeBlockPreservesInternalIndentation() {
        let md = "```python\ndef foo():\n    return 42\n```"
        let blks = blocks(of: md)
        if case .codeBlock(_, let code) = blks[0] {
            XCTAssertTrue(code.contains("    return 42"), "Indentation should be preserved")
        } else {
            XCTFail("Expected .codeBlock")
        }
    }

    func testCodeBlockPreservesInternalBlankLines() {
        let md = "```\nline1\n\nline3\n```"
        let blks = blocks(of: md)
        if case .codeBlock(_, let code) = blks[0] {
            XCTAssertEqual(code, "line1\n\nline3")
        } else {
            XCTFail("Expected .codeBlock")
        }
    }

    func testMultipleCodeBlocksInOneSection() {
        let md = "```\nfirst\n```\n\nSome text\n\n```js\nsecond\n```"
        let blks = blocks(of: md)
        let codeBlocks = blks.compactMap { block -> String? in
            if case .codeBlock(_, let code) = block { return code }
            return nil
        }
        XCTAssertEqual(codeBlocks.count, 2)
        XCTAssertEqual(codeBlocks[0], "first")
        XCTAssertEqual(codeBlocks[1], "second")
    }

    // MARK: - Numbered list

    func testBasicNumberedList() {
        let md = "1. First\n2. Second\n3. Third"
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .numberedList(let items) = blks[0] {
            XCTAssertEqual(items, ["First", "Second", "Third"])
        } else {
            XCTFail("Expected .numberedList, got \(blks[0])")
        }
    }

    func testNumberedListWithNonSequentialNumbers() {
        let md = "1. Alpha\n3. Beta\n7. Gamma"
        let blks = blocks(of: md)
        if case .numberedList(let items) = blks[0] {
            XCTAssertEqual(items, ["Alpha", "Beta", "Gamma"])
        } else {
            XCTFail("Expected .numberedList")
        }
    }

    func testNumberedListItemsWithInlineMarkdown() {
        let md = "1. **Bold** item\n2. `code` item"
        let blks = blocks(of: md)
        if case .numberedList(let items) = blks[0] {
            XCTAssertEqual(items[0], "**Bold** item")
            XCTAssertEqual(items[1], "`code` item")
        } else {
            XCTFail("Expected .numberedList")
        }
    }

    // MARK: - Nested bullets

    func testNestedBulletsWithTwoSpaceIndent() {
        let md = "  - Indented one"
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 1)
        if case .nestedBullets(let items) = blks[0] {
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items[0].indent, 1)
            XCTAssertEqual(items[0].text, "Indented one")
        } else {
            XCTFail("Expected .nestedBullets, got \(blks[0])")
        }
    }

    func testNestedBulletsWithFourSpaceIndent() {
        let md = "    - Deep item"
        let blks = blocks(of: md)
        if case .nestedBullets(let items) = blks[0] {
            XCTAssertEqual(items[0].indent, 2)
            XCTAssertEqual(items[0].text, "Deep item")
        } else {
            XCTFail("Expected .nestedBullets")
        }
    }

    func testMixedIndentLevels() {
        let md = "  - Level 1\n    - Level 2\n  - Level 1 again"
        let blks = blocks(of: md)
        if case .nestedBullets(let items) = blks[0] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].indent, 1)
            XCTAssertEqual(items[1].indent, 2)
            XCTAssertEqual(items[2].indent, 1)
        } else {
            XCTFail("Expected .nestedBullets")
        }
    }

    // MARK: - Integration tests

    func testDocumentWithAllBlockTypesMixed() {
        let md = """
        ## Overview

        This is a paragraph.

        - Bullet A
        - Bullet B

        1. First
        2. Second

        | Col1 | Col2 |
        |------|------|
        | a | b |

        ```swift
        let x = 42
        ```

          - Nested item
        """
        let sections = parse(md)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Overview")

        let blks = sections[0].blocks
        let kinds = blks.map { block -> String in
            switch block {
            case .paragraph: return "paragraph"
            case .bullets: return "bullets"
            case .numberedList: return "numberedList"
            case .table: return "table"
            case .codeBlock: return "codeBlock"
            case .nestedBullets: return "nestedBullets"
            }
        }
        XCTAssertTrue(kinds.contains("paragraph"))
        XCTAssertTrue(kinds.contains("bullets"))
        XCTAssertTrue(kinds.contains("numberedList"))
        XCTAssertTrue(kinds.contains("table"))
        XCTAssertTrue(kinds.contains("codeBlock"))
        XCTAssertTrue(kinds.contains("nestedBullets"))
    }

    func testRealWorldDocumentWithMultipleSections() {
        let md = """
        ## Architecture

        The system uses a three-layer design.

        | Layer | Role |
        |-------|------|
        | UI | Presentation |
        | Core | Domain logic |
        | DB | Persistence |

        ## Setup

        Run the following:

        ```bash
        swift build
        swift test
        ```

        Steps:

        1. Clone the repo
        2. Run xcodegen
        3. Open in Xcode
        """
        let sections = parse(md)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Architecture")
        XCTAssertEqual(sections[1].title, "Setup")

        let archBlocks = sections[0].blocks
        let hasTable = archBlocks.contains { if case .table = $0 { return true }; return false }
        XCTAssertTrue(hasTable)

        let setupBlocks = sections[1].blocks
        let hasCode = setupBlocks.contains { if case .codeBlock = $0 { return true }; return false }
        XCTAssertTrue(hasCode)
        let hasList = setupBlocks.contains { if case .numberedList = $0 { return true }; return false }
        XCTAssertTrue(hasList)
    }

    func testCRLFNormalization() {
        let md = "## Title\r\n\r\nParagraph text."
        let sections = parse(md)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Title")
        if case .paragraph(let text) = sections[0].blocks.first {
            XCTAssertEqual(text, "Paragraph text.")
        } else {
            XCTFail("Expected .paragraph after CRLF normalization")
        }
    }

    func testEmptyDocumentProducesNoSections() {
        let sections = parse("")
        XCTAssertTrue(sections.isEmpty)
    }

    func testBlankLinesBetweenBlocksDoNotLeakIntoParagraphs() {
        let md = "First paragraph.\n\nSecond paragraph."
        let blks = blocks(of: md)
        XCTAssertEqual(blks.count, 2)
        if case .paragraph(let t1) = blks[0] { XCTAssertEqual(t1, "First paragraph.") }
        if case .paragraph(let t2) = blks[1] { XCTAssertEqual(t2, "Second paragraph.") }
    }
}
