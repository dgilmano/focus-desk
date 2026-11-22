#if DEBUG && !FOCUS_DESK_UPDATES
import SwiftData
import XCTest
@testable import FocusDesk

private final class VoiceFixture: URLProtocol, @unchecked Sendable {
    static let rules = "Пиши кратко.\n- Сохраняй названия узлов."
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "api.openai.com")
            XCTAssertEqual(request.httpMethod, "POST")
            let key = request.value(forHTTPHeaderField: "Authorization")
            let status = key == "Bearer rejected-test" ? 401 : 200
            let json: [String: Any]
            if status == 401 {
                json = ["error": ["message": "Invalid key rejected-test"]]
            } else if url.path == "/v1/audio/transcriptions" {
                let body = String(decoding: try bodyData(), as: UTF8.self)
                XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
                XCTAssertTrue(body.contains("name=\"file\"; filename=\"note.m4a\""))
                XCTAssertTrue(body.contains("fixture audio"))
                XCTAssertFalse(body.contains(Self.rules))
                json = ["text": "Нужен отчёт и слайды."]
            } else {
                XCTAssertEqual(url.path, "/v1/responses")
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
                XCTAssertEqual(payload["store"] as? Bool, false)
                let format = (payload["text"] as? [String: Any])?["format"] as? [String: Any]
                XCTAssertEqual(format?["strict"] as? Bool, true)
                let input = try XCTUnwrap(payload["input"] as? String)
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
                if key == "Bearer rules-test" {
                    XCTAssertEqual(fields["taskInstructions"] as? String, Self.rules)
                    XCTAssertEqual(fields["note"] as? String, "Сверить отчёт.")
                } else {
                    XCTAssertNil(fields["taskInstructions"])
                }
                XCTAssertFalse(input.contains("localDraft"))
                XCTAssertFalse(input.contains("journal"))
                let proposal: [String: Any] = ["kind": "task", "projectName": "Nokia Networks", "parentTitle": "", "title": "Отчёт", "summary": "Сверить цифры.", "steps": ["Открыть выгрузку."], "suggestions": ["Сравнить итоги."]]
                if key == "Bearer refusal-test" {
                    json = ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "Unavailable"]]]]]
                } else {
                    let tasks = fields["currentTask"] != nil ? [proposal] : [proposal, ["kind": "task", "projectName": "Nokia Networks", "parentTitle": "Отчёт", "title": "Слайды", "summary": "", "steps": [], "suggestions": []]]
                    let content = try JSONSerialization.data(withJSONObject: ["tasks": tasks])
                    json = ["status": "completed", "output": [["type": "reasoning"], ["type": "message", "content": [["type": "output_text", "text": String(decoding: content, as: UTF8.self)]]]]]
                }
            }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { return data }
            data.append(contentsOf: bytes.prefix(count))
        }
    }
}

@MainActor final class VoiceTaskTests: XCTestCase {
    #if SWIFT_PACKAGE
    func testStandaloneDebugExecutableDeclaresMicrophoneUsage() throws {
        let products = Bundle(for: VoiceTaskTests.self).bundleURL.deletingLastPathComponent()
        let executable = products.appendingPathComponent("FocusDesk")
        let info = try XCTUnwrap(CFBundleCopyInfoDictionaryForURL(executable as CFURL) as? [String: Any])
        let usage = try XCTUnwrap(info["NSMicrophoneUsageDescription"] as? String)
        XCTAssertFalse(usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    #endif

    private func client() -> OpenAIVoiceClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VoiceFixture.self]
        return OpenAIVoiceClient(session: URLSession(configuration: config))
    }

    func testVoiceToMultipleDraftsAndOptionalSuggestion() async throws {
        let api = client()
        let transcript = try await api.transcribe(Data("fixture audio".utf8), key: "test")
        let proposals = try await api.organize(transcript, current: nil, key: "test")
        XCTAssertEqual(proposals.map(\.title), ["Отчёт", "Слайды"])
        var review = VoiceTaskReview(proposals[0])
        XCTAssertEqual(review.nextStep, "Открыть выгрузку.")
        review.include("Сравнить итоги.")
        review.include("Сравнить итоги.")
        XCTAssertEqual(review.nextStep, "Открыть выгрузку.\nСравнить итоги.")
        XCTAssertTrue(review.suggestions.isEmpty)
    }

    func testTaskInstructionsApplyToNewAndUpdatedDraftsAndCanBeCleared() async throws {
        let api = client()
        let target = VoiceTaskContext(FocusTask(title: "Отчёт", sortOrder: 0))
        for current in [nil, target] {
            let drafts = try await api.organize("Сверить отчёт.", current: current,
                                                taskInstructions: " \n" + VoiceFixture.rules + "\n", key: "rules-test")
            XCTAssertEqual(drafts.count, current == nil ? 2 : 1)
        }
        _ = try await api.organize("Сверить отчёт.", current: nil, taskInstructions: " \n\t", key: "test")
    }

    func testSubtaskModeUsesSelectedParentAndNeverSilentlyDropsAStaleSelection() throws {
        let parent = FocusTask(title: "Package", sortOrder: 0)
        parent.tagRecords = [.init(name: "Build")]
        let chosen = VoiceTaskContext(parent)
        let proposal = VoiceTaskProposal(title: "Verify PDF", summary: "", steps: [], suggestions: [], projectName: "Other")
        let draft = VoiceTaskReview(proposal, tasks: [chosen], defaultParent: chosen.id)
        XCTAssertEqual(draft.parentTaskID, parent.id)
        XCTAssertEqual(draft.projectName, "Build")
        let stale = VoiceTaskReview(proposal, tasks: [], defaultParent: chosen.id)
        XCTAssertNotNil(stale.unmatchedParent)
        XCTAssertNil(stale.parentTaskID)
    }

    func testDictatedParentAndChildCanBeReviewedSavedAndRestored() async throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let store = TaskStore(context: container.mainContext)
        let proposals = try await client().organize("Проект Nokia Networks. Отчёт с подзадачей Слайды.", current: nil, key: "test")
        let root = try XCTUnwrap(store.saveVoiceReview(VoiceTaskReview(proposals[0]), target: nil))
        var childDraft = VoiceTaskReview(proposals[1], tasks: [VoiceTaskContext(root)])
        XCTAssertEqual(childDraft.parentTaskID, root.id)
        childDraft.projectName = " nokia networks "
        let child = try XCTUnwrap(store.saveVoiceReview(childDraft, target: nil))
        XCTAssertEqual(child.parentTaskID, root.id)
        XCTAssertEqual(child.deskProjectTag?.name, "Nokia Networks")
        XCTAssertTrue(store.setCompleted(child, true))
        XCTAssertNil(root.completedAt)
        XCTAssertTrue(store.setCompleted(child, false))
        XCTAssertTrue(store.setCompleted(root, true))
        XCTAssertNil(child.completedAt)
        XCTAssertTrue(store.setCompleted(root, false))

        let original = VoiceTaskContext(root)
        var move = VoiceTaskReview(proposals[0], target: original)
        move.parentTaskID = child.id
        XCTAssertThrowsError(try store.saveVoiceReview(move, target: original))
        move.parentTaskID = nil
        move.projectName = "Rollout"
        _ = try store.saveVoiceReview(move, target: original)
        XCTAssertEqual(child.projectName, "Rollout")
        let backup = try WorkspaceBackup.capture(from: container.mainContext)
        XCTAssertEqual(backup.projects, ["Nokia Networks", "Rollout"])
        let restored = try PersistenceController.makeModelContainer(inMemory: true)
        try WorkspaceBackup.decode(backup.encoded()).apply(to: restored.mainContext)
        try restored.mainContext.save()
        let copy = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<FocusTask>()).first { $0.id == child.id })
        XCTAssertEqual(copy.parentTaskID, root.id)
        XCTAssertEqual(copy.projectName, "Rollout")
        var invalid = backup
        let index = try XCTUnwrap(invalid.tasks.firstIndex { $0.id == root.id })
        invalid.tasks[index].parentTaskID = child.id
        XCTAssertThrowsError(try invalid.validated())
        invalid.tasks[index].parentTaskID = UUID()
        XCTAssertThrowsError(try invalid.validated())

        XCTAssertTrue(store.delete(root))
        XCTAssertNil(child.parentTaskID)
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(child.parentTaskID, original.id)
    }

    func testProjectOnlyDraftAndAmbiguousParentAndFailedSave() throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        var fail = false
        let store = TaskStore(context: context, persist: { context in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        let project = VoiceTaskProposal(title: "Nokia Networks", summary: "", steps: [], suggestions: [], kind: .project)
        XCTAssertNil(try store.saveVoiceReview(VoiceTaskReview(project), target: nil))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusTask>()), 0)
        let proposal = VoiceTaskProposal(title: "Rollout", summary: "", steps: [], suggestions: [], projectName: "Nokia Networks")
        let first = try XCTUnwrap(store.saveVoiceReview(VoiceTaskReview(proposal), target: nil))
        let second = try XCTUnwrap(store.saveVoiceReview(VoiceTaskReview(proposal), target: nil))
        var child = proposal
        child.title = "Check site"
        child.parentTitle = "Rollout"
        var review = VoiceTaskReview(child, tasks: [VoiceTaskContext(first), VoiceTaskContext(second)])
        XCTAssertEqual(review.unmatchedParent, "Rollout")
        XCTAssertThrowsError(try store.saveVoiceReview(review, target: nil))
        review.parentTaskID = second.id
        review.unmatchedParent = nil
        let saved = try XCTUnwrap(store.saveVoiceReview(review, target: nil))
        XCTAssertEqual(saved.parentTaskID, second.id)
        let original = VoiceTaskContext(second)
        var move = VoiceTaskReview(proposal, target: original)
        move.projectName = "Another project"
        fail = true
        XCTAssertThrowsError(try store.saveVoiceReview(move, target: original))
        XCTAssertEqual(saved.projectName, "Nokia Networks")
        XCTAssertEqual(second.projectName, "Nokia Networks")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<DeskProject>()), 1)
    }

    func testAuthenticationAndRefusalAreRecoverable() async throws {
        let api = client()
        for key in ["rejected-test", "refusal-test"] {
            do {
                _ = try await api.organize("Plan work", current: nil, key: key)
                XCTFail("Expected a recoverable error")
            } catch let error as VoiceNoteError {
                XCTAssertFalse(error.localizedDescription.contains(key))
            }
        }
        let retry = try await api.organize("Plan work", current: nil, key: "test")
        XCTAssertFalse(retry.isEmpty)
    }

    func testReviewedUpdateRollsBackAndPreservesUnrelatedData() async throws {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let task = FocusTask(title: "Old title", details: "Original", sortOrder: 0, motivation: "Why", localDraft: "Unsubmitted")
        task.tagRecords = [.init(name: "Work")]
        task.entries.append(ProgressEntry(note: "Existing entry", timestamp: Date(), task: task))
        context.insert(task)
        try context.save()
        var fail = true
        let store = TaskStore(context: context, persist: { context in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        let snapshot = VoiceTaskContext(task)
        let proposals = try await client().organize("Update my plan", current: snapshot, key: "test")
        let review = VoiceTaskReview(try XCTUnwrap(proposals.first))
        XCTAssertThrowsError(try store.saveVoiceReview(review, target: snapshot))
        XCTAssertEqual(VoiceTaskContext(task), snapshot)
        fail = false
        _ = try store.saveVoiceReview(review, target: snapshot)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<FocusTask>()).first)
        XCTAssertEqual(saved.title, review.title)
        XCTAssertEqual(saved.nextStep, review.nextStep)
        XCTAssertEqual(saved.localDraft, "Unsubmitted")
        XCTAssertEqual(saved.entries.map(\.note), ["Existing entry"])
        XCTAssertEqual(saved.enabledTagRecords.map(\.name), ["Work"])
        XCTAssertEqual(saved.motivation, "Why")
        XCTAssertThrowsError(try store.saveVoiceReview(review, target: snapshot))
    }
}
#endif
