#if DEBUG && !FOCUS_DESK_UPDATES
import Foundation

struct VoiceTaskReview {
    let kind: VoiceTaskProposal.Kind
    var title: String
    var summary: String
    var nextStep: String
    var suggestions: [String]
    var projectName: String
    var parentTaskID: UUID?
    var unmatchedParent: String?

    init(_ proposal: VoiceTaskProposal, target: VoiceTaskContext? = nil, tasks: [VoiceTaskContext] = [],
         defaultProject: String = "", defaultParent: UUID? = nil) {
        kind = proposal.kind
        title = proposal.title
        summary = proposal.summary
        nextStep = proposal.steps.joined(separator: "\n")
        suggestions = proposal.suggestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let spokenProject = proposal.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        projectName = spokenProject.isEmpty ? defaultProject : spokenProject
        if kind == .project {
            projectName = spokenProject.isEmpty ? title : spokenProject
            return
        }
        if projectName.isEmpty { projectName = target?.project ?? "" }
        let hint = DeskProject.key(for: proposal.parentTitle)
        let eligible = Self.parentChoices(for: target, tasks: tasks)
        if !hint.isEmpty {
            let projectKey = DeskProject.key(for: projectName)
            let matches = eligible.filter {
                DeskProject.key(for: $0.title) == hint && (projectKey.isEmpty || DeskProject.key(for: $0.project) == projectKey)
            }
            if matches.count == 1 { parentTaskID = matches[0].id }
            else { unmatchedParent = proposal.parentTitle }
        } else if let parent = eligible.first(where: { $0.id == defaultParent }),
                  spokenProject.isEmpty || DeskProject.key(for: parent.project) == DeskProject.key(for: spokenProject) {
            parentTaskID = parent.id
        } else if let target, DeskProject.key(for: target.project) == DeskProject.key(for: projectName) {
            parentTaskID = target.parentTaskID
        }
        if let parent = eligible.first(where: { $0.id == parentTaskID }) { projectName = parent.project }
    }

    static func parentChoices(for target: VoiceTaskContext?, tasks: [VoiceTaskContext]) -> [VoiceTaskContext] {
        let excluded = target.map { TaskHierarchy.branch(from: $0.id, links: tasks.map { ($0.id, $0.parentTaskID) }) } ?? []
        return tasks.filter { !excluded.contains($0.id) && (!$0.isCompleted || $0.id == target?.parentTaskID) }
    }

    mutating func include(_ suggestion: String) {
        if !nextStep.components(separatedBy: .newlines).contains(suggestion) {
            if !nextStep.isEmpty && !nextStep.hasSuffix("\n") { nextStep += "\n" }
            nextStep += suggestion
        }
        suggestions.removeAll { $0 == suggestion }
    }
}
#endif
