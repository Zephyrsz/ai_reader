import XCTest
import UIKit

final class AIReaderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["AI_READER_TEST_LIBRARY"] = "UITests-\(UUID().uuidString)"
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }

    func testNativeReadingPauseSkipBackgroundAndEditCancellation() throws {
        createText(title: "オフライン朗読", body: "京都の朝は静かです。今日は日本語の本を読みます。ゆっくりと散歩しましょう。\n次の段落も続けて読みましょう。")
        app.tabBars.buttons["文件库"].tap()
        app.buttons.containing(.staticText, identifier: "オフライン朗読").firstMatch.tap()
        let play = app.buttons["reader.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5)); play.tap()
        let status = app.staticTexts["reader.speechStatus"]
        let playing = NSPredicate(format: "label BEGINSWITH %@", "正在朗读")
        expectation(for: playing, evaluatedWith: status)
        waitForExpectations(timeout: 90)
        attach("原生日语朗读")
        play.tap()
        XCTAssertTrue(status.label.hasPrefix("已暂停"))
        play.tap()
        app.buttons["reader.next"].tap()
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["miniplayer.toggle"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["miniplayer.stop"].waitForExistence(timeout: 5))
        app.buttons["miniplayer.stop"].tap()
        XCTAssertFalse(app.buttons["miniplayer.stop"].exists)
        app.buttons.containing(.staticText, identifier: "オフライン朗読").firstMatch.tap()
        play.tap()
        app.buttons["更多操作"].tap(); app.buttons["编辑文本"].tap()
        XCTAssertTrue(app.textViews["editorBody"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()
        XCTAssertFalse(app.buttons["reader.stop"].exists)
    }

    func testFourNativeVoicePreviewsAndSelectionPersist() throws {
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.voice"].tap()
        for id in [0, 8, 14, 24] {
            let select = app.buttons["voice.select.\(id)"]
            if !select.isHittable { app.swipeUp() }
            XCTAssertTrue(select.waitForExistence(timeout: 5)); select.tap()
            app.buttons["voice.preview.\(id)"].tap()
            let status = app.staticTexts["voice.status"]
            if !status.isHittable { app.swipeUp() }
            let playing = NSPredicate(format: "label BEGINSWITH %@", "正在朗读")
            expectation(for: playing, evaluatedWith: status)
            waitForExpectations(timeout: 90)
            app.buttons["voice.stop"].tap()
            attach("音色试听-\(id)")
            app.swipeDown()
        }
        app.terminate(); app.launch()
        app.tabBars.buttons["设置"].tap(); app.buttons["settings.voice"].tap()
        let selected = app.buttons["voice.select.24"]
        if !selected.isHittable { app.swipeUp() }
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.value as? String, "已选择")
    }

    func testCreateReadEditAndRelaunchPersistsJapaneseText() throws {
        attach("首页")
        createText(title: "京都の朝", body: "京都の朝は静かです。\n今日は本を読みます。")
        app.tabBars.buttons["文件库"].tap()
        let document = app.buttons.containing(.staticText, identifier: "京都の朝").firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        document.tap()
        XCTAssertTrue(app.staticTexts["京都の朝は静かです。"].waitForExistence(timeout: 5))
        let play = app.buttons["reader.play"]
        XCTAssertTrue(play.exists)
        XCTAssertTrue(play.isEnabled)
        attach("文本阅读器")
        app.buttons["reader.find"].tap()
        app.textFields["reader.searchField"].tap()
        app.textFields["reader.searchField"].typeText("京都")
        XCTAssertTrue(app.staticTexts["1 个匹配"].waitForExistence(timeout: 3))
        app.buttons["reader.find"].tap()
        app.buttons["更多操作"].tap()
        app.buttons["添加书签"].tap()
        XCTAssertTrue(app.buttons["书签与目录"].waitForExistence(timeout: 3))
        app.buttons["更多操作"].tap()
        app.buttons["编辑文本"].tap()
        let title = app.textFields["editorTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("・改訂")
        app.buttons["saveText"].tap()
        XCTAssertTrue(app.staticTexts["京都の朝は静かです。"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["文件库"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "改訂")).firstMatch.waitForExistence(timeout: 5))
        attach("文件库・重启恢复")
    }

    func testFavoriteTrashAndRestore() throws {
        createText(title: "日本語の練習", body: "新しい言葉を覚えましょう。")
        app.tabBars.buttons["文件库"].tap()
        app.buttons["日本語の練習 操作"].tap()
        app.collectionViews.buttons["收藏"].tap()
        app.buttons["library.filter.favorites"].tap()
        XCTAssertTrue(app.staticTexts["日本語の練習"].waitForExistence(timeout: 3))
        app.buttons["日本語の練習 操作"].tap()
        app.buttons["移入最近删除"].tap()
        if app.buttons["移入最近删除"].exists { app.buttons["移入最近删除"].tap() }
        app.buttons["最近删除"].tap()
        let trashedDocument = app.staticTexts["日本語の練習"]
        XCTAssertTrue(trashedDocument.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trash.restore.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["最近删除为空"].waitForExistence(timeout: 5))
        app.buttons["trash.back"].tap()
        XCTAssertTrue(app.staticTexts["日本語の練習"].waitForExistence(timeout: 5))
    }

    func testDraftRecoveryAndSettingsRemainAvailable() throws {
        app.buttons["newText"].tap()
        app.textViews["editorBody"].tap()
        app.textViews["editorBody"].typeText("書きかけの文章です。")
        // Cancel explicitly flushes the draft; it must survive a full process restart.
        app.buttons["editor.cancel"].tap()
        app.terminate()
        app.launch()
        let recover = app.alerts.buttons["恢复"]
        XCTAssertTrue(recover.waitForExistence(timeout: 5))
        recover.tap()
        XCTAssertEqual(app.textViews["editorBody"].value as? String, "書きかけの文章です。")
        app.buttons["editor.cancel"].tap()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.voice"].waitForExistence(timeout: 5))
        attach("设置")
    }

    func testFileImportPreservesTXTNameAndDetectsDuplicate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("京都のメモ.txt")
        try "京都のメモ\n今朝は川のそばを散歩しました。".write(to: source, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        app.open(source)
        let start = app.buttons["开始导入"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let confirm = app.buttons["import.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["import.openImported"].waitForExistence(timeout: 5))
        attach("TXT 导入完成")
        app.buttons["完成"].tap()
        app.tabBars.buttons["文件库"].tap()
        XCTAssertTrue(app.staticTexts[source.deletingPathExtension().lastPathComponent].waitForExistence(timeout: 5))
        app.open(source)
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["import.openDuplicate"].waitForExistence(timeout: 5))
        attach("重复文件处理")
    }

    func testPDFImportOriginalAndExtractedTextModes() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("日本語の読書.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try renderer.writePDF(to: source) { context in
            for page in 1...2 {
                context.beginPage()
                ("日本語の読書 \(page)\n京都の朝は静かです。" as NSString).draw(in: CGRect(x: 50, y: 80, width: 480, height: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: source) }
        app.open(source)
        XCTAssertTrue(app.buttons["开始导入"].waitForExistence(timeout: 5))
        app.buttons["开始导入"].tap()
        XCTAssertTrue(app.buttons["import.confirm"].waitForExistence(timeout: 5))
        app.buttons["import.confirm"].tap()
        XCTAssertTrue(app.buttons["import.openImported"].waitForExistence(timeout: 5))
        app.buttons["import.openImported"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["原文"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["原文"].tap()
        XCTAssertTrue(app.textFields["页"].waitForExistence(timeout: 5))
        attach("PDF 原文阅读")
        app.segmentedControls.buttons["文本"].tap()
        XCTAssertTrue(app.staticTexts["reader.text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reader.play"].isEnabled)
        attach("PDF 文本阅读")
    }

    func testDefaultSpeedAndAppearancePersistAcrossRelaunch() throws {
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.speedLink"].tap()
        let preset = app.buttons["speed.preset.1.25"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5)); preset.tap()
        attach("语速设置")
        app.buttons["speed.done"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["1.25×"].waitForExistence(timeout: 5))
        app.buttons["settings.appearance"].tap()
        let dark = app.segmentedControls.buttons["深色"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5)); dark.tap()
        attach("深色阅读设置")
    }

    func testEditorClearUndoRedoAndSave() throws {
        app.buttons["newText"].tap()
        let editor = app.textViews["editorBody"]
        editor.tap(); editor.typeText("元に戻せる文章です。")
        app.buttons["收起键盘"].tap()
        app.buttons["editor.clear"].tap()
        app.buttons["清空正文"].tap()
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertFalse(app.buttons["saveText"].isEnabled)
        app.buttons["editor.undo"].tap()
        XCTAssertEqual(editor.value as? String, "元に戻せる文章です。")
        app.buttons["editor.redo"].tap()
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["editor.undo"].tap()
        app.buttons["saveText"].tap()
        XCTAssertTrue(app.buttons["newText"].waitForExistence(timeout: 5))
    }

    func testFoldersMoveAndJapaneseBodySearch() throws {
        createText(title: "読書のメモ", body: "春の京都を歩きます。")
        app.tabBars.buttons["文件库"].tap()
        app.buttons["library.manageFolders"].tap()
        app.alerts.textFields.firstMatch.tap()
        app.alerts.textFields.firstMatch.typeText("日本語")
        app.alerts.buttons["保存"].tap()
        app.buttons["読書のメモ 操作"].tap()
        app.buttons["移动到"].tap()
        app.collectionViews.buttons["日本語"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.folder.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["読書のメモ"].waitForExistence(timeout: 3))
        let search = app.textFields["library.search"]
        search.tap(); search.typeText("京都")
        XCTAssertTrue(app.staticTexts["読書のメモ"].waitForExistence(timeout: 3))
        app.buttons["清除搜索"].tap()
        app.buttons["library.backToAll"].tap()
        XCTAssertTrue(app.buttons["library.manageFolders"].waitForExistence(timeout: 3))
        attach("文件夹与资料管理")
    }

    func testLandscapeReaderKeepsControlsAvailable() throws {
        createText(title: "横向きの読書", body: "静かな午後に本を読みます。\n自分のペースで読み進めましょう。")
        app.tabBars.buttons["文件库"].tap()
        app.buttons.containing(.staticText, identifier: "横向きの読書").firstMatch.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let back = app.buttons["reader.back"]
        let player = app.buttons["reader.play"]
        let landscapeLayout = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let window = app.windows.firstMatch.frame
            return window.width > window.height
                && back.exists && player.exists
                && window.contains(back.frame) && window.contains(player.frame)
                && abs(player.frame.midX - window.midX) < 4
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeLayout], timeout: 8), .completed)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(player.exists)
        // Capture the screen after layout settles; app snapshots may crop during rotation.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "横屏阅读器"; attachment.lifetime = .keepAlways
        add(attachment)
        back.tap()
        XCTAssertTrue(app.tabBars.buttons["文件库"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }

    func testStorageCacheAndConfirmedReset() throws {
        createText(title: "消去の確認", body: "この資料はテスト専用です。")
        app.tabBars.buttons["文件库"].tap()
        app.buttons.containing(.staticText, identifier: "消去の確認").firstMatch.tap()
        XCTAssertTrue(app.buttons["reader.back"].waitForExistence(timeout: 5))
        app.buttons["reader.back"].tap()
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.storage"].tap()
        let clearCache = app.buttons["storage.clearExportCache"]
        XCTAssertTrue(clearCache.waitForExistence(timeout: 5))
        XCTAssertTrue(clearCache.isEnabled)
        clearCache.tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: clearCache)
        waitForExpectations(timeout: 5)
        let speechCache = app.buttons["storage.clearSpeechCache"]
        if !speechCache.isHittable { app.swipeUp() }
        XCTAssertTrue(speechCache.waitForExistence(timeout: 5)); speechCache.tap()
        let reset = app.buttons["storage.resetLibrary"]
        for _ in 0..<3 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 5)); reset.tap()
        app.buttons["继续"].tap()
        let finalConfirmation = app.buttons["删除所有本地资料"]
        XCTAssertTrue(finalConfirmation.waitForExistence(timeout: 5))
        finalConfirmation.tap()
        app.tabBars.buttons["文件库"].tap()
        XCTAssertTrue(app.staticTexts["这里还没有资料"].waitForExistence(timeout: 5))
    }

    private func createText(title: String, body: String) {
        let newText = app.buttons["newText"]
        XCTAssertTrue(newText.waitForExistence(timeout: 5))
        newText.tap()
        let titleField = app.textFields["editorTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap(); titleField.typeText(title)
        let editor = app.textViews["editorBody"]
        editor.tap(); editor.typeText(body)
        app.buttons["收起键盘"].tap()
        if title == "京都の朝" { attach("文本编辑器") }
        app.buttons["saveText"].tap()
        XCTAssertTrue(newText.waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
