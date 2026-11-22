#if DEBUG
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
        let decoded = try JSONDecoder().decode(DeskMapArrangement.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, arranged)
        let restored = base.placing(decoded, items: items, width: 500)
        XCTAssertEqual(restored.groups[0].label.x, 300, accuracy: 0.001)
        XCTAssertEqual(restored.nodes[0].center.x, 100, accuracy: 0.001)
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

    private func item(_ tag: String?) -> DeskTaskMapLayout.Item {
        .init(id: UUID(), title: "A long task title", tag: tag, palette: .gray)
    }
}
#endif
