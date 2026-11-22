#if (DEBUG && !FOCUS_DESK_UPDATES) || FOCUS_DESK_PERSONAL
import SwiftUI
import SwiftData

struct VoiceButtonAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct VoiceTaskWidget: View {
    let current: VoiceTaskContext?
    @Binding var apiKey: String
    let buttonBounds: CGRect
    let available: CGSize
    let save: (VoiceTaskReview, VoiceTaskContext?) throws -> VoiceTaskContext?
    let dismiss: () -> Void

    @Query(sort: \FocusTask.sortOrder) private var tasks: [FocusTask]
    @Query(sort: \DeskProject.key) private var projects: [DeskProject]
    @AppStorage(VoiceTaskPreferences.instructionsKey) private var taskInstructions = ""
    @State private var capture = VoiceCapture()
    private enum Mode: String { case newTask = "New task", subtask = "Subtask", update = "Update task" }
    @State private var mode = Mode.newTask
    @State private var parentID: UUID?
    private var updateCurrent: Bool { mode == .update }
    @State private var editID: UUID?
    @State private var reviewingTarget: VoiceTaskContext?
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var savedInBatch: [VoiceTaskContext] = []
    @State private var note = ""
    @State private var review: VoiceTaskReview?
    @State private var remaining: [VoiceTaskProposal] = []
    @State private var batchSize = 0
    @State private var showingConnection = false
    @State private var keySaved = false
    @State private var operation: Task<Void, Never>?
    @State private var busy: String?
    @State private var errorText: String?
    @State private var confirmDiscard = false
    @State private var resizedFrame: CGRect?
    private let client = OpenAIVoiceClient()

    private var choices: [VoiceTaskContext] {
        let live = tasks.map(VoiceTaskContext.init)
        let ids = Set(live.map(\.id))
        return live + savedInBatch.filter { !ids.contains($0.id) }
    }
    private var projectNames: [String] {
        var seen = Set<String>()
        return (projects.map(\.name) + choices.map(\.project))
            .filter { !$0.isEmpty && seen.insert(DeskProject.key(for: $0)).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private var target: VoiceTaskContext? {
        updateCurrent ? choices.first { $0.id == editID && !$0.isCompleted } : nil
    }
    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasWork: Bool { !note.isEmpty || capture.file != nil || review != nil || busy != nil }

    private var heading: String {
        if showingConnection { return "OpenAI connection" }
        guard let review else { return "Voice note" }
        if review.kind == .project { return "Review project" }
        return review.parentTaskID == nil ? "Review task" : "Review subtask"
    }

    private var limits: CGRect {
        let margin: CGFloat = 12
        return CGRect(x: margin, y: margin, width: max(0, available.width - 2 * margin),
                      height: max(0, available.height - 2 * margin))
    }

    private var initialHeight: CGFloat {
        if showingConnection { return 260 }
        if review != nil { return 470 }
        return mode == .newTask ? 272 : 338
    }

    private var cardFrame: CGRect {
        let y = max(limits.minY, buttonBounds.maxY + 8)
        let initial = CGRect(x: buttonBounds.midX - 190, y: y, width: 380,
                             height: min(initialHeight, max(VoiceWidgetResizeBorder.minimumSize.height, limits.maxY - y)))
        let desired = resizedFrame?.offsetBy(dx: buttonBounds.midX, dy: buttonBounds.maxY) ?? initial
        let width = min(desired.width, limits.width)
        let height = min(desired.height, limits.height)
        return CGRect(x: max(limits.minX, min(desired.minX, limits.maxX - width)),
                      y: max(limits.minY, min(desired.minY, limits.maxY - height)),
                      width: width, height: height)
    }

    var body: some View {
        let frame = cardFrame
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: requestClose)
                .accessibilityHidden(true)
            card(frame: frame)
                .overlay {
                    VoiceWidgetResizeBorder(frame: frame, limits: limits) { newFrame in
                        resizedFrame = newFrame.offsetBy(dx: -buttonBounds.midX, dy: -buttonBounds.maxY)
                    }
                }
                .position(x: frame.midX, y: frame.midY)
        }
        .confirmationDialog("Discard the unfinished voice note?", isPresented: $confirmDiscard) {
            Button("Discard note", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear {
            editID = current?.id ?? choices.first(where: { !$0.isCompleted })?.id
            parentID = editID
            do {
                let saved = try VoiceAPIKey.read()
                keySaved = !saved.isEmpty
                if apiKey.isEmpty { apiKey = saved }
            } catch { errorText = error.localizedDescription }
        }
        .onDisappear {
            operation?.cancel()
            capture.discard()
        }
    }

    private func requestClose() {
        if hasWork { confirmDiscard = true } else { dismiss() }
    }

    private func card(frame: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .accessibilityHidden(true)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FocusDeskStyle.deskAccent)
                    .frame(width: 28, height: 28)
                    .background(FocusDeskStyle.deskAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                Text(heading)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if review != nil && batchSize > 1 {
                    Text("\(batchSize - remaining.count) of \(batchSize)").font(.caption).foregroundStyle(.secondary)
                } else if review == nil && !showingConnection {
                    Menu {
                        Button("OpenAI connection…") { showingConnection = true }
                        Button("Create project…") { newProjectName = ""; showingNewProject = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuIndicator(.hidden).menuStyle(.borderlessButton).fixedSize()
                    .disabled(busy != nil)
                    .accessibilityLabel("Voice note options")
                    .help("Voice note options")
                }
                Button(action: requestClose) {
                    Image(systemName: "xmark").frame(width: 22, height: 22)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close voice note").help("Close voice note")
            }
            Divider()
            ViewThatFits(in: .vertical) {
                widgetContent
                ScrollView { widgetContent.padding(2) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(16)
        .frame(width: frame.width, height: frame.height)
        .background {
            RoundedRectangle(cornerRadius: 13).fill(FocusDeskStyle.groupedBackground)
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        }
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(FocusDeskStyle.hairline).allowsHitTesting(false) }
        .alert("Create project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let proposal = VoiceTaskProposal(title: newProjectName, summary: "", steps: [], suggestions: [],
                                                 kind: .project, projectName: newProjectName)
                do { _ = try save(VoiceTaskReview(proposal), nil); errorText = nil }
                catch { errorText = error.localizedDescription }
            }
            .disabled(DeskProject.key(for: newProjectName).isEmpty)
        }
    }

    private var widgetContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showingConnection {
                connection
            } else if let draft = Binding($review) {
                reviewContent(draft)
            } else {
                composer
            }
            if let message = errorText ?? capture.errorMessage {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(busy != nil)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            let openTasks = choices.filter { !$0.isCompleted }
            HStack(spacing: 2) {
                modeButton(.newTask)
                modeButton(.subtask).disabled(openTasks.isEmpty)
                modeButton(.update).disabled(openTasks.isEmpty)
            }
            .padding(3)
            .background(FocusDeskStyle.focusSurface, in: RoundedRectangle(cornerRadius: 8))
            if mode != .newTask {
                let outline = TaskOutline(choices.map(\.outlineItem))
                if mode == .subtask { Text("Parent task").font(.caption).foregroundStyle(.secondary) }
                ProjectTaskPicker(tasks: openTasks.map(\.outlineItem), selection: updateCurrent ? $editID : $parentID,
                                  label: updateCurrent ? "Task to update" : "Parent task")
                    .frame(maxWidth: .infinity).frame(height: 24)
                if let id = updateCurrent ? editID : parentID, let item = outline.items[id] {
                    Text("\(item.project.isEmpty ? "Untagged" : item.project) › \(outline.path(to: id))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if updateCurrent, let children = outline.children[id] {
                        Menu("Subtasks (\(children.count))") {
                            ForEach(children, id: \.self) { childID in
                                if let child = choices.first(where: { $0.id == childID }) {
                                    Button(child.title) { editID = child.id }.disabled(child.isCompleted)
                                }
                            }
                        }
                        .fixedSize().font(.caption)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Your note").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let busy {
                        ProgressView().controlSize(.small)
                        Text(busy).font(.caption).foregroundStyle(.secondary)
                    } else if capture.file != nil && !capture.isRecording {
                        Button { capture.discard(); errorText = nil } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).accessibilityLabel("Discard recording").help("Discard recording")
                    }
                }
                noteField("Your note", text: $note)
            }
        }
    }

    private func modeButton(_ option: Mode) -> some View {
        let selected = mode == option
        return Button { mode = option } label: {
            Text(option.rawValue).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : .secondary)
                .frame(maxWidth: .infinity).frame(height: 25)
                .background { if selected { RoundedRectangle(cornerRadius: 6).fill(FocusDeskStyle.groupedBackground) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func reviewContent(_ draft: Binding<VoiceTaskReview>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reviewingTarget { Text("Updating \(reviewingTarget.title)").foregroundStyle(.secondary) }
            projectField(draft.projectName) { clearParentIfNeeded(draft, project: $0) }
            if let reviewingTarget, DeskProject.key(for: reviewingTarget.project) != DeskProject.key(for: draft.wrappedValue.projectName),
               choices.contains(where: { $0.parentTaskID == reviewingTarget.id }) {
                Text("Subtasks will move to this project too.").font(.caption).foregroundStyle(.secondary)
            }
            if draft.wrappedValue.kind == .task {
                parentMenu(selected: draft.wrappedValue.parentTaskID, target: reviewingTarget, hint: draft.wrappedValue.unmatchedParent) { parent in
                    draft.wrappedValue.parentTaskID = parent?.id
                    draft.wrappedValue.unmatchedParent = nil
                    if let parent { draft.wrappedValue.projectName = parent.project }
                }
                reviewFields(draft)
            }
            if updateCurrent && errorText != nil {
                Button("Use draft for a new task") { mode = .newTask; reviewingTarget = nil; errorText = nil }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if showingConnection {
                Spacer()
                primaryButton("Done") { showingConnection = false }
            } else if let review {
                if batchSize - remaining.count == 1 {
                    Button("Edit note") { self.review = nil; remaining = []; errorText = nil }
                }
                if !remaining.isEmpty { Button("Skip") { advance() } }
                Spacer(minLength: 0)
                primaryButton(review.kind == .project ? "Save project" : (updateCurrent ? "Apply changes" : (review.parentTaskID == nil ? "Create task" : "Create subtask"))) {
                    do {
                        if let saved = try save(review, reviewingTarget) { savedInBatch.append(saved) }
                        advance()
                    } catch { errorText = error.localizedDescription }
                }
                .disabled((review.kind == .project ? review.projectName : review.title).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || review.unmatchedParent != nil)
            } else {
                recordingControls.disabled(busy != nil)
                Spacer()
                if hasKey {
                    primaryButton("Create draft", action: organize)
                        .disabled(busy != nil || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || capture.file != nil || (updateCurrent && target == nil) || (mode == .subtask && !choices.contains { $0.id == parentID && !$0.isCompleted }))
                        .help(updateCurrent ? "Send your note, task instructions and the selected task’s title, description and next steps to OpenAI." : "Send your note and task instructions to OpenAI.")
                } else {
                    primaryButton("Connect OpenAI") { showingConnection = true }.disabled(busy != nil)
                }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(VoiceWidgetActionStyle(primary: true))
    }

    private func projectField(_ name: Binding<String>, changed: @escaping (String) -> Void) -> some View {
        let selection = Binding(get: { name.wrappedValue }, set: { name.wrappedValue = $0; changed($0) })
        return HStack(spacing: 6) {
            Text("Project").accessibilityHidden(true)
            TextField("Choose or enter a project", text: selection)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Project")
            Menu {
                Button("No project") { selection.wrappedValue = "" }
                ForEach(projectNames, id: \.self) { project in
                    Button(project) { selection.wrappedValue = project }
                }
            } label: { Image(systemName: "folder") }
            .fixedSize().accessibilityLabel("Choose project")
        }
    }

    private func parentMenu(selected: UUID?, target: VoiceTaskContext?, hint: String?,
                            choose: @escaping (VoiceTaskContext?) -> Void) -> some View {
        let parents = VoiceTaskReview.parentChoices(for: target, tasks: choices)
        let binding = Binding<UUID?>(get: { selected }, set: { id in choose(parents.first { $0.id == id }) })
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Parent task").accessibilityHidden(true)
                ProjectTaskPicker(tasks: parents.map(\.outlineItem), selection: binding, label: "Parent task", emptyChoice: "No parent")
                    .frame(height: 24)
            }
            if let selected {
                Text(TaskOutline(choices.map(\.outlineItem)).path(to: selected)).font(.caption).foregroundStyle(.secondary)
            }
            if let hint {
                Text("Parent in your note: \(hint). Choose a matching task or No parent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clearParentIfNeeded(_ draft: Binding<VoiceTaskReview>, project: String) {
        if let parent = choices.first(where: { $0.id == draft.wrappedValue.parentTaskID }),
           DeskProject.key(for: parent.project) != DeskProject.key(for: project) {
            draft.wrappedValue.parentTaskID = nil
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SecureField("OpenAI API key", text: $apiKey)
            HStack {
                Button("Save in Keychain") {
                    do {
                        try VoiceAPIKey.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        keySaved = true
                        showingConnection = false
                        errorText = nil
                    } catch { errorText = error.localizedDescription }
                }.disabled(!hasKey)
                if keySaved {
                    Button("Forget saved key") {
                        do {
                            try VoiceAPIKey.forget()
                            apiKey = ""
                            keySaved = false
                            errorText = nil
                        } catch { errorText = error.localizedDescription }
                    }
                }
            }
            Text("You can also use the key for this session.").font(.caption).foregroundStyle(.secondary)
            Text("Transcription sends audio to OpenAI. Creating a draft sends your note, any task instructions from Settings and, for updates, the selected task’s title, description and next steps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recordingControls: some View {
        Group {
            if capture.isRecording {
                Button { capture.stop() } label: { Label("Stop recording", systemImage: "stop.circle.fill") }
                    .tint(.red)
            } else if let url = capture.file {
                Button { transcribe(url) } label: { Label("Transcribe", systemImage: "waveform") }.disabled(!hasKey).help("Send the recording to OpenAI for transcription")
            } else {
                Button {
                    run("Opening microphone…") { try await capture.start() }
                } label: { Label("Record", systemImage: "record.circle") }
            }
        }
        .buttonStyle(VoiceWidgetActionStyle(primary: false))
    }

    private func reviewFields(_ draft: Binding<VoiceTaskReview>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task title", text: draft.title).font(.headline)
            editor("Description", text: draft.summary, height: 60)
            editor("Next step", text: draft.nextStep, height: 84)
            if !draft.wrappedValue.suggestions.isEmpty {
                Text("Suggestions from GPT").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(Array(draft.wrappedValue.suggestions.enumerated()), id: \.offset) { _, suggestion in
                    HStack(alignment: .firstTextBaseline) {
                        Text(suggestion).frame(maxWidth: .infinity, alignment: .leading)
                        Button { draft.wrappedValue.include(suggestion) } label: { Image(systemName: "plus.circle") }
                            .buttonStyle(.plain).help("Add to next steps").accessibilityLabel("Add suggestion: \(suggestion)")
                    }
                }
            }
        }
    }

    private func editor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            noteField(title, text: text, height: height)
        }
    }

    private func noteField(_ title: String, text: Binding<String>, height: CGFloat? = nil) -> some View {
        TextEditor(text: text)
            .font(.body).scrollContentBackground(.hidden).padding(6)
            .frame(minHeight: height ?? 40, maxHeight: height ?? .infinity)
            .background(FocusDeskStyle.focusSurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(FocusDeskStyle.hairline).allowsHitTesting(false) }
            .accessibilityLabel(title)
    }

    private func transcribe(_ url: URL) {
        run("Transcribing…") {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 25_000_000 else { throw VoiceNoteError.message("The recording exceeds the 25 MB transcription limit.") }
            let transcript = try await client.transcribe(Data(contentsOf: url, options: .mappedIfSafe), key: apiKey)
            try Task.checkCancellation()
            if !note.isEmpty { note += "\n" }
            note += transcript
            capture.discard()
        }
    }

    private func organize() {
        let original = target
        run("Structuring tasks…") {
            let proposals = try await client.organize(note, current: original, taskInstructions: taskInstructions, key: apiKey)
            try Task.checkCancellation()
            batchSize = proposals.count
            remaining = Array(proposals.dropFirst())
            reviewingTarget = original
            review = makeReview(proposals[0])
        }
    }

    private func advance() {
        errorText = nil
        if remaining.isEmpty { dismiss() } else { review = makeReview(remaining.removeFirst()) }
    }

    private func makeReview(_ proposal: VoiceTaskProposal) -> VoiceTaskReview {
        VoiceTaskReview(proposal, target: reviewingTarget, tasks: choices, defaultParent: mode == .subtask ? parentID : nil)
    }

    private func run(_ label: String, work: @escaping @MainActor () async throws -> Void) {
        guard busy == nil else { return }
        errorText = nil
        busy = label
        operation = Task { @MainActor in
            defer { busy = nil; operation = nil }
            do { try await work() }
            catch { if !Task.isCancelled { errorText = error.localizedDescription } }
        }
    }
}

private struct VoiceWidgetActionStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .frame(width: 120, height: 34)
            .background(primary ? FocusDeskStyle.deskActionBlue : FocusDeskStyle.focusSurface,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.65)
    }
}
#endif
