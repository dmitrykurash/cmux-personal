import Foundation
import Observation

@MainActor @Observable
final class PersonalChatSidebarState {
    private var collapsedProjects: Set<UUID> = []
    private var openArchives: Set<UUID> = []
    private var archiveLimits: [UUID: Int] = [:]

    func projectIsExpanded(_ id: UUID) -> Bool { !collapsedProjects.contains(id) }
    func toggleProject(_ id: UUID) {
        if !collapsedProjects.insert(id).inserted { collapsedProjects.remove(id) }
    }
    func openProject(_ id: UUID) { collapsedProjects.remove(id) }
    func archiveIsExpanded(_ id: UUID) -> Bool { openArchives.contains(id) }
    func toggleArchive(_ id: UUID) {
        if !openArchives.insert(id).inserted { openArchives.remove(id) }
        archiveLimits[id] = 20
    }
    func archiveLimit(_ id: UUID) -> Int { archiveLimits[id] ?? 20 }
    func loadMore(_ id: UUID) { archiveLimits[id] = archiveLimit(id) + 20 }
    func resetPages() { archiveLimits = [:] }
}
