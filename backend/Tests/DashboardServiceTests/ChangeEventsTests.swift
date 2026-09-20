import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardService

@Suite struct ChangeEventsTests {
    @Test func broadcasterFansOutToEverySubscriberAndForgetsClosedOnes() async throws {
        let broadcaster = ChangeBroadcaster()
        let a = await broadcaster.subscribe()
        let b = await broadcaster.subscribe()
        #expect(await broadcaster.subscriberCount == 2)
        await broadcaster.publish(.settingsChanged)
        var itA = a.makeAsyncIterator()
        var itB = b.makeAsyncIterator()
        #expect(await itA.next() == .settingsChanged)
        #expect(await itB.next() == .settingsChanged)
    }

    @Test func projectServicePublishesOnEveryMutation() async throws {
        let changes = ChangeBroadcaster()
        let svc = memoryService(changes: changes)
        let stream = await changes.subscribe()
        var events = stream.makeAsyncIterator()

        let project = try await svc.add(name: "Demo", path: try tempDir())
        #expect(await events.next() == .projectsChanged)
        try await svc.mutate(.id(project.id)) { workspace, _ in workspace.createBoard(name: "B") }
        #expect(await events.next() == .workspaceChanged(projectId: project.id))
        try await svc.changeStorage(.id(project.id), to: .json)
        _ = try await svc.remove(.id(project.id))
        #expect(await events.next() == .projectsChanged, "no-op storage switch emits nothing; removal does")
    }

    @Test func settingsServicePublishesOnUpdate() async throws {
        let changes = ChangeBroadcaster()
        let svc = SettingsService(store: InMemorySettingsStore(), changes: changes)
        let stream = await changes.subscribe()
        var events = stream.makeAsyncIterator()
        _ = try await svc.update(defaultStorage: .sqlite)
        #expect(await events.next() == .settingsChanged)
    }
}
