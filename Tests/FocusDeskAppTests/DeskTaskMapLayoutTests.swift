#if DEBUG
import FocusDeskCore
import XCTest
@testable import FocusDesk

final class DeskTaskMapLayoutTests: XCTestCase {
    func testRepeatedTagsShareOneClusterAndNodesKeepListOrder() {
        let tags: [String?] = ["Design", "Build", "design", nil, "BUILD", nil]
        let items = tags.map(item)
        let layout = DeskTaskMapLayout(items: items, width: 700)
        XCTAssertEqual(layout.groups.map(\.indices), [[0, 2], [1, 4], [3, 5]])
        XCTAssertEqual(layout.groups.last?.name, "Untagged")
        XCTAssertLessThan(layout.nodes[0].center.x, layout.nodes[1].center.x)
        XCTAssertGreaterThan(layout.nodes[3].center.y, layout.nodes[1].center.y)
    }

    func testLongLabelsRemainSelectableWithUnevenGroupsAndNarrowWindows() {
        let tags: [String?] = Array(repeating: "Build", count: 12) + [nil, "Design", "Work", "Study", "Other", "Life"]
        let items = tags.map(item)
        for width: CGFloat in [320, 380, 760, 1200] {
            let layout = DeskTaskMapLayout(items: items, width: width)
            let bounds = CGRect(x: 0, y: 0, width: width, height: layout.mapHeight)
            var previous: [CGRect] = []
            for node in layout.nodes {
                let button = CGRect(x: node.center.x - node.maxWidth / 2, y: node.center.y - 11,
                                    width: node.maxWidth, height: 22)
                XCTAssertTrue(bounds.contains(button))
                XCTAssertFalse(previous.contains { $0.intersects(button) })
                previous.append(button)
            }
        }
    }

    func testProjectMembershipUsesEveryEnabledTagAndIncludesCompletedTasks() throws {
        let layout = DeskTaskMapLayout(items: ["My Project", nil, "Untagged"].map(item), width: 700)
        let project = try XCTUnwrap(layout.groups.first { $0.tag == "My Project" })
        let untagged = try XCTUnwrap(layout.groups.first { $0.tag == nil })
        let namedUntagged = try XCTUnwrap(layout.groups.first { $0.tag == "Untagged" })
        let task = FocusTask(title: "Review", sortOrder: 0, completedAt: Date())
        task.tagRecords = [.init(name: "Design"), .init(name: " my PROJECT ", sortOrder: 1)]
        XCTAssertTrue(project.includes(task))
        XCTAssertFalse(untagged.includes(task))

        task.tagRecords = [.init(name: "My Project", isEnabled: false), .init(name: " ")]
        XCTAssertFalse(project.includes(task))
        XCTAssertTrue(untagged.includes(task))
        task.tagRecords = [.init(name: "Untagged")]
        XCTAssertTrue(namedUntagged.includes(task))
        XCTAssertFalse(untagged.includes(task))
    }

    func testCloudJunctionIsVisibleBetweenDefaultLabelsAndTaskChips() {
        for count in 1...6 {
            let items = Array(repeating: "Design", count: count).map(item)
            let layout = DeskTaskMapLayout(items: items, width: 400)
            let group = layout.groups[0]
            XCTAssertGreaterThan(group.hubBounds.minY, group.label.y + 11)
            for node in layout.nodes {
                let chip = CGRect(x: node.center.x - node.chipWidth / 2, y: node.center.y - 11,
                                  width: node.chipWidth, height: 22)
                XCTAssertFalse(chip.intersects(group.hubBounds))
            }
        }
    }

    func testGroupDragKeepsMembersTogetherAfterIndividualDragAndReload() throws {
        let items = ["Design", "Design", "Build"].map(item)
        let base = DeskTaskMapLayout(items: items, width: 700)
        let task = DeskMapDrag.Target.task(items[1].id)
        let individual = base.moving(.init(target: task, translation: CGSize(width: 27, height: 14)), items: items, width: 700)
        XCTAssertEqual(individual.nodes[1].center.x - base.nodes[1].center.x, 27)
        XCTAssertEqual(individual.nodes[0].center, base.nodes[0].center)

        var saved = DeskMapArrangement()
        saved.remember(task, in: individual, items: items, width: 700)
        let group = DeskMapDrag.Target.group(base.groups[0].id)
        let moved = base.placing(saved, items: items, width: 700)
            .moving(.init(target: group, translation: CGSize(width: 40, height: 15)), items: items, width: 700)
        for i in [0, 1] {
            XCTAssertEqual(moved.nodes[i].center.x - individual.nodes[i].center.x, 40, accuracy: 0.001)
            XCTAssertEqual(moved.nodes[i].center.y - individual.nodes[i].center.y, 15, accuracy: 0.001)
        }
        XCTAssertEqual(moved.nodes[2].center, base.nodes[2].center)
        saved.remember(group, in: moved, items: items, width: 700)
        let persisted = try JSONDecoder().decode(DeskMapArrangement.self, from: JSONEncoder().encode(saved))
        let reloaded = base.placing(persisted, items: items, width: 700)
        XCTAssertEqual(reloaded.groups[0].label.x, moved.groups[0].label.x, accuracy: 0.001)
        for i in items.indices {
            XCTAssertEqual(reloaded.nodes[i].center.x, moved.nodes[i].center.x, accuracy: 0.001)
            XCTAssertEqual(reloaded.nodes[i].center.y, moved.nodes[i].center.y, accuracy: 0.001)
        }
    }

    func testDraggingBeyondCanvasAndResizingKeepsHandlesReachable() {
        let items = [nil, "Untagged", nil].map(item)
        let layout = DeskTaskMapLayout(items: items, width: 900)
        XCTAssertNotEqual(layout.groups[0].id, layout.groups[1].id)
        let group = DeskMapDrag.Target.group(layout.groups[0].id)
        let moved = layout.moving(.init(target: group, translation: CGSize(width: 9000, height: -9000)),
                                  items: items, width: 900)
        XCTAssertEqual(moved.groups[0].label.y, 11)
        XCTAssertLessThanOrEqual(moved.nodes[0].center.x + moved.nodes[0].chipWidth / 2, 900)
        var saved = DeskMapArrangement()
        saved.remember(group, in: moved, items: items, width: 900)
        let narrow = DeskTaskMapLayout(items: items, width: 320).placing(saved, items: items, width: 320)
        for node in narrow.nodes {
            XCTAssertGreaterThanOrEqual(node.center.x - node.chipWidth / 2, 0)
            XCTAssertLessThanOrEqual(node.center.x + node.chipWidth / 2, 320)
            XCTAssertGreaterThanOrEqual(node.center.y, 11)
            XCTAssertLessThanOrEqual(node.center.y, narrow.mapHeight - 11)
        }
    }

    func testLabelDragPersistsRelativeToTheCloudThroughGroupDragRenameAndResize() throws {
        let items = ["Learning", "Learning", "Sport"].map(item)
        let base = DeskTaskMapLayout(items: items, width: 720)
        let group = base.groups[0]
        let label = DeskMapDrag.Target.label(group.id)
        let moved = base.moving(.init(target: label, translation: CGSize(width: 28, height: 25)), items: items, width: 720)
        XCTAssertEqual(moved.groups[0].label, CGPoint(x: group.label.x + 28, y: group.label.y + 25))
        XCTAssertEqual(moved.groups[0].center, group.center)
        XCTAssertEqual(moved.nodes.map(\.center), base.nodes.map(\.center))
        XCTAssertEqual(moved.groups[1].label, base.groups[1].label)
        var saved = DeskMapArrangement()
        saved.remember(label, in: moved, items: items, width: 720)
        let cloud = DeskMapDrag.Target.group(group.id)
        let both = base.placing(saved, items: items, width: 720)
            .moving(.init(target: cloud, translation: CGSize(width: 20, height: 12)), items: items, width: 720)
        saved.remember(cloud, in: both, items: items, width: 720)
        let restored = base.placing(saved, items: items, width: 720)
        XCTAssertEqual(restored.groups[0].center.y, both.groups[0].center.y, accuracy: 0.0001)
        XCTAssertEqual(restored.groups[0].label.x, both.groups[0].label.x, accuracy: 0.0001)
        XCTAssertEqual(restored.groups[0].label.y, both.groups[0].label.y, accuracy: 0.0001)
        saved.renameGroup(from: group.id, to: "tag:reading")
        XCTAssertNil(saved.groups[group.id])
        XCTAssertNil(saved.labels[group.id])
        XCTAssertNotNil(saved.groups["tag:reading"])
        XCTAssertNotNil(saved.labels["tag:reading"])

        let limited = base.moving(.init(target: label, translation: CGSize(width: -10000, height: 10000)), items: items, width: 720)
        saved.remember(label, in: limited, items: items, width: 720)
        let smaller = DeskTaskMapLayout(items: items, width: 320).placing(saved, items: items, width: 320).groups[0]
        let cornerX = abs(smaller.center.x - smaller.label.x) + smaller.labelWidth / 2
        let cornerY = abs(smaller.center.y - smaller.label.y) + 11
        XCTAssertLessThanOrEqual(hypot(cornerX, cornerY), smaller.radius + 0.001)
    }

    func testExistingMapPreferencesWithoutLabelOffsetsStillLoad() throws {
        let items = ["Sport"].map(item)
        let base = DeskTaskMapLayout(items: items, width: 500)
        var arranged = DeskMapArrangement()
        arranged.tasks[items[0].id] = CGPoint(x: 0.2, y: 0.4)
        arranged.groups["tag:sport"] = CGPoint(x: 0.6, y: 0.3)
        let data = try JSONEncoder().encode(arranged)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "labels")
        legacy.removeValue(forKey: "stepOffsets")
        legacy.removeValue(forKey: "expandedTasks")
        legacy.removeValue(forKey: "clouds")
        let decoded = try JSONDecoder().decode(DeskMapArrangement.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, arranged)
        let restored = base.placing(decoded, items: items, width: 500)
        XCTAssertEqual(restored.groups[0].label.x, 300, accuracy: 0.001)
        XCTAssertEqual(restored.nodes[0].center.x, 100, accuracy: 0.001)
    }

    func testMapReopensWithItsExpandedTasksAndManualPositions() throws {
        let parent = UUID(), child = UUID()
        var arrangement = DeskMapArrangement(expandedTasks: [parent, child])
        arrangement.tasks[child] = CGPoint(x: 0.3, y: 0.7)
        let saved = try JSONEncoder().encode(arrangement)
        let reopened = try JSONDecoder().decode(DeskMapArrangement.self, from: saved)
        XCTAssertEqual(reopened, arrangement)
        XCTAssertEqual(DeskMapArrangement(expandedTasks: reopened.expandedTasks).expandedTasks, [parent, child])
    }

    func testHubRecognizesDoubleClickAfterEarlierSingleClickAndKeepsLabelClicksSeparate() {
        var clicks = DeskMapClicks()
        XCTAssertFalse(clicks.doubleClickedHub("Study", at: 1, doubleClickInterval: 0.5))
        XCTAssertFalse(clicks.doubleClickedHub("Study", at: 1.7, doubleClickInterval: 0.5))
        XCTAssertTrue(clicks.doubleClickedHub("Study", at: 1.8, doubleClickInterval: 0.5))
        XCTAssertEqual(clicks.record(.project("Study"), at: 2, doubleClickInterval: 0.5), .select)
        XCTAssertFalse(clicks.doubleClickedHub("Study", at: 2.1, doubleClickInterval: 0.5))
        XCTAssertFalse(clicks.doubleClickedHub("Sport", at: 2.2, doubleClickInterval: 0.5))
    }

    func testFoldingCloudHidesOnlyItsTasksAndStepsAndKeepsPlacement() throws {
        var work = item("Work"), study = item("Study")
        work.steps = NextStepChecklist("Review draft").items
        study.steps = NextStepChecklist("Read chapter").items
        let items = [work, item("Work"), study]
        let plain = DeskTaskMapLayout(items: items, width: 680)
        let key = DeskTaskMapLayout.Group.projectID("Work")
        var saved = DeskMapArrangement(expandedTasks: [work.id, study.id])
        saved.tasks[work.id] = CGPoint(x: 0.2, y: 0.6)
        saved.clouds[key] = .init(isCollapsed: true, color: "purple", symbol: "briefcase")
        let folded = DeskTaskMapLayout(items: items, width: 680, clouds: saved.clouds).placing(saved, items: items, width: 680)
        XCTAssertEqual(folded.visibleTaskIndices, [2])
        XCTAssertEqual(folded.groups[0].center, plain.groups[0].center)
        XCTAssertEqual(folded.groups[0].palette, .purple)
        XCTAssertLessThan(folded.groups[0].haloBounds.width, plain.groups[0].haloBounds.width)
        XCTAssertEqual(DeskMapSteps(layout: folded, items: items, width: 680).leaves.map(\.id.task), [study.id])
        var restored = try JSONDecoder().decode(DeskMapArrangement.self, from: JSONEncoder().encode(saved))
        restored.clouds[key]?.isCollapsed = false
        let open = DeskTaskMapLayout(items: items, width: 680, clouds: restored.clouds).placing(restored, items: items, width: 680)
        XCTAssertEqual(open.visibleTaskIndices, [0, 1, 2])
        XCTAssertEqual(open.nodes[0].center, folded.nodes[0].center)
        XCTAssertEqual(DeskMapSteps(layout: open, items: items, width: 680).leaves.map(\.id.task), [work.id, study.id])
        restored.renameGroup(from: key, to: "tag:new")
        restored.resetPositions()
        XCTAssertEqual(restored.clouds["tag:new"]?.symbol, "briefcase")
        XCTAssertEqual(restored.clouds["tag:new"]?.color, "purple")
        XCTAssertNil(restored.clouds[key])
        XCTAssertEqual(restored.expandedTasks, saved.expandedTasks)
    }

    func testDropTargetsUseThePointerAndThePlacedCloudIncludingEmptyProjects() throws {
        let items = ["Learning", "Learning", nil, "Untagged"].map(item)
        let layout = DeskTaskMapLayout(items: items, width: 720, projects: ["Learning", "Sport"])
        let source = try XCTUnwrap(layout.groups.first { $0.tag == "Learning" })
        let sport = try XCTUnwrap(layout.groups.first { $0.tag == "Sport" })
        XCTAssertTrue(sport.indices.isEmpty)
        let shifted = layout.moving(.init(target: .group(sport.id), translation: CGSize(width: 48, height: 15)),
                                    items: items, width: 720)
        let target = try XCTUnwrap(shifted.groups.first { $0.id == sport.id })
        func drop(at point: CGPoint) -> String? {
            shifted.dropTarget(for: .init(target: .task(items[0].id), translation: .zero, location: point), items: items)?.id
        }
        XCTAssertEqual(drop(at: target.center), sport.id)
        XCTAssertEqual(drop(at: target.label), sport.id)
        XCTAssertNil(drop(at: source.center))
        XCTAssertNil(drop(at: CGPoint(x: -20, y: -20)))
        let unassigned = try XCTUnwrap(shifted.groups.first { $0.tag == nil })
        XCTAssertEqual(drop(at: unassigned.center), "untagged")
        let named = try XCTUnwrap(shifted.groups.first { $0.tag == "Untagged" })
        XCTAssertEqual(drop(at: named.center), "tag:untagged")
        let newItems = ["Sport", "Learning", nil, "Untagged"].map(item)
        let newLayout = DeskTaskMapLayout(items: newItems, width: 720, projects: ["Sport"], groupOrder: layout.groups.map(\.id))
        XCTAssertEqual(layout.groups.map(\.id), newLayout.groups.map(\.id))
    }

    func testSubtasksAreHiddenUntilEveryAncestorIsExpanded() {
        let root = UUID(), child = UUID(), nested = UUID(), other = UUID(), orphan = UUID()
        let outline = TaskOutline([
            .init(id: nested, parentID: child, title: "Verify", project: "Build"),
            .init(id: other, parentID: root, title: "Other project", project: "Study"),
            .init(id: orphan, parentID: UUID(), title: "Open child", project: "Build"),
            .init(id: root, parentID: nil, title: "Ship", project: "BUILD"),
            .init(id: child, parentID: root, title: "Package", project: "Build")
        ])
        XCTAssertEqual(outline.rows(expanded: []).map(\.id), [other, orphan, root])
        XCTAssertEqual(outline.rows(expanded: [child]).map(\.id), [other, orphan, root])
        XCTAssertEqual(outline.rows(expanded: [root]).map(\.id), [other, orphan, root, child])
        XCTAssertEqual(outline.rows(expanded: [root, child]).map(\.depth), [0, 0, 0, 1, 2])
        XCTAssertEqual(outline.path(to: nested), "Ship › Package › Verify")
        XCTAssertEqual(outline.rows().map(\.id), [other, orphan, root, child, nested])
        let cycle = TaskOutline([.init(id: root, parentID: child, title: "A", project: ""),
                                 .init(id: child, parentID: root, title: "B", project: "")])
        XCTAssertEqual(cycle.rows().map(\.id), [root, child])
    }

    func testStepClustersRespectTaskPositionsCanvasEdgesAndOtherBranches() {
        var items = ["Work", "Home", "Work", "Home"].map(item)
        let checklist = NextStepChecklist("1. Prepare\n- [x] Check\n- [ ] Ship")
        for i in items.indices { items[i].steps = checklist.items }
        for width: CGFloat in [270, 400, 760, 1000] {
            let base = DeskTaskMapLayout(items: items, width: width)
            let drag = DeskMapDrag(target: .task(items[0].id), translation: CGSize(width: 100, height: 94))
            for layout in [base, base.moving(drag, items: items, width: width)] {
                let cluster = DeskMapSteps(layout: layout, items: items, width: width)
                let area = CGRect(x: 0, y: 0, width: width, height: cluster.height)
                var occupied = layout.nodes.map(\.chipBounds) + layout.groups.map(\.hubBounds)
                XCTAssertEqual(cluster.leaves.count, 12)
                XCTAssertEqual(Set(cluster.leaves.map(\.id)).count, 12)
                for leaf in cluster.leaves {
                    XCTAssertTrue(area.contains(leaf.frame))
                    XCTAssertFalse(occupied.contains { $0.intersects(leaf.frame) })
                    occupied.append(leaf.frame)
                    let index = items.firstIndex { $0.id == leaf.id.task }!
                    XCTAssertEqual(leaf.parent, layout.nodes[index].center)
                    XCTAssertEqual(leaf.step.text, checklist.items[leaf.id.index].text)
                }
            }
        }
    }

    func testFastAndDeliberateClicksAreExclusiveAndTargetTheSameTask() {
        var clicks = DeskMapClicks()
        let a = DeskMapObject.task(UUID()), b = DeskMapObject.project("Build")
        XCTAssertEqual(clicks.record(a, at: 1, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(a, at: 1.2, doubleClickInterval: 0.5), .doubleClick)
        XCTAssertEqual(clicks.record(a, at: 1.3, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(a, at: 2.1, doubleClickInterval: 0.5), .rename)
        XCTAssertEqual(clicks.record(a, at: 3, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(b, at: 3.2, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(b, at: 5, doubleClickInterval: 0.5), .select)
        let owner = UUID()
        let step = DeskMapObject.step(.init(task: owner, index: 0))
        XCTAssertEqual(clicks.record(.task(owner), at: 6, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(step, at: 6.8, doubleClickInterval: 0.5), .select)
        XCTAssertEqual(clicks.record(step, at: 7.6, doubleClickInterval: 0.5), .rename)
    }

    func testDraggedStepFollowsPointerAndParentAndRestoresWithinCanvas() throws {
        var task = item("Work")
        task.steps = NextStepChecklist("Prepare\nSend").items
        let width: CGFloat = 700
        let layout = DeskTaskMapLayout(items: [task], width: width)
        let base = DeskMapSteps(layout: layout, items: [task], width: width)
        let original = base.leaves[0]
        let translation = CGSize(width: -36, height: -30)
        let drag = DeskMapDrag(target: .step(original.key), translation: translation)
        let moved = base.moving(drag, width: width)
        let leaf = moved.leaves[0]
        XCTAssertEqual(leaf.frame, original.frame.offsetBy(dx: -36, dy: -30))
        XCTAssertEqual(leaf.parent, original.parent)
        XCTAssertTrue(leaf.isManuallyPlaced)
        XCTAssertEqual(moved.leaves[1].frame, base.leaves[1].frame)
        XCTAssertFalse(moved.leaves[1].isManuallyPlaced)
        XCTAssertNil(layout.dropTarget(for: drag, items: [task]))

        var arrangement = DeskMapArrangement()
        arrangement.stepOffsets[leaf.key] = leaf.offsetFromParent
        XCTAssertFalse(arrangement.isEmpty)
        let restored = try JSONDecoder().decode(DeskMapArrangement.self, from: JSONEncoder().encode(arrangement))
        let reopened = DeskMapSteps(layout: layout, items: [task], width: width, offsets: restored.stepOffsets)
        XCTAssertEqual(reopened.leaves[0].frame, leaf.frame)
        for target in [DeskMapDrag.Target.task(task.id), .group(layout.groups[0].id)] {
            let shifted = layout.moving(.init(target: target, translation: CGSize(width: 20, height: 15)), items: [task], width: width)
            let branch = DeskMapSteps(layout: shifted, items: [task], width: width, offsets: restored.stepOffsets)
            XCTAssertEqual(branch.leaves[0].frame, leaf.frame.offsetBy(dx: 20, dy: 15))
            XCTAssertEqual(branch.leaves[0].parent, shifted.nodes[0].center)
        }
        let bounded = reopened.moving(.init(target: .step(leaf.key), translation: CGSize(width: -4000, height: 4000)), width: width)
        XCTAssertEqual(bounded.leaves[0].frame.minX, 0)
        XCTAssertEqual(bounded.leaves[0].frame.maxY, bounded.height)
        let narrow = DeskTaskMapLayout(items: [task], width: 260)
        let narrowBranch = DeskMapSteps(layout: narrow, items: [task], width: 260, offsets: restored.stepOffsets)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 260, height: narrowBranch.height).contains(narrowBranch.leaves[0].frame))
    }

    func testStepPlacementSurvivesReorderingAndInlineRenameWithDuplicateNames() {
        let task = UUID()
        let labels = ["Plan", "Check", "Check"]
        let keys = DeskMapSteps.PlacementKey.keys(task: task, labels: labels)
        XCTAssertNotEqual(keys[1], keys[2])
        var saved = DeskMapArrangement()
        for i in keys.indices { saved.stepOffsets[keys[i]] = CGSize(width: i * 10, height: i * 15) }
        let previous = saved.stepOffsets
        let reordered = DeskMapSteps.PlacementKey.keys(task: task, labels: ["New", "Check", "Plan", "Check"])
        XCTAssertEqual(reordered[2], keys[0])
        XCTAssertEqual(reordered[3], keys[2])
        XCTAssertNil(previous[reordered[0]])
        saved.renameStep(at: 1, in: task, labels: labels, to: "Plan")
        let renamed = DeskMapSteps.PlacementKey.keys(task: task, labels: ["Plan", "Plan", "Check"])
        for i in keys.indices { XCTAssertEqual(saved.stepOffsets[renamed[i]], previous[keys[i]]) }
        XCTAssertEqual(saved.stepOffsets.count, 3)
    }

    private func item(_ tag: String?) -> DeskTaskMapLayout.Item {
        .init(id: UUID(), title: "A long task title", tag: tag, palette: .gray)
    }
}
#endif
