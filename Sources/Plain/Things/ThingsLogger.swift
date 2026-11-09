import Foundation

/// One session waiting to reach Things. Progress is saved step by step, so a retry never
/// creates a second to-do or logs the time twice.
struct LogJob: Codable, Equatable, Identifiable {
    var id = UUID()
    var session: CompletedSession
    /// The to-do the time lands on: the picked one, or the Focus Log entry once created.
    var taskID: String?
    var createdLogEntry = false
    var timeLogged = false
    var completed = false
    var attempts = 0
    var lastError: String?

    init(session: CompletedSession) {
        self.session = session
        taskID = session.taskID
    }

    var isFreeText: Bool { session.taskID == nil }
    var isDone: Bool { timeLogged && (!isFreeText || completed) }
}

/// Sends finished sessions to Things 4, queueing them in things-queue.json when it's away.
final class ThingsLogger {
    private let client: ThingsClient
    private let queueURL: URL
    private(set) var queue: [LogJob]
    private var running = false
    private var timer: Timer?
    var onChange: (() -> Void)?

    init(client: ThingsClient, queueURL: URL = PlainPaths.file("things-queue.json")) {
        self.client = client
        self.queueURL = queueURL
        queue = JSONFiles.load([LogJob].self, from: queueURL) ?? []
    }

    func startRetrying() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { await self?.flush() }
        }
        Task { await flush() }
    }

    /// Queues a session and tries to send everything now. Returns the to-do id the time landed on.
    @discardableResult
    func log(_ session: CompletedSession) async -> (taskID: String?, error: String?) {
        let job = LogJob(session: session)
        await MainActor.run {
            queue.append(job)
            save()
        }
        await flush()
        let left = await MainActor.run { queue.first { $0.id == job.id } }
        if let left { return (left.taskID, left.lastError ?? "Queued; will retry") }
        return (await MainActor.run { lastTaskIDs[job.id] } ?? session.taskID, nil)
    }

    private var lastTaskIDs: [UUID: String] = [:]

    func flush() async {
        let busy = await MainActor.run { () -> Bool in
            if running { return true }
            running = true
            return false
        }
        guard !busy else { return }
        defer { Task { @MainActor in self.running = false } }
        let jobs = await MainActor.run { queue }
        for var job in jobs {
            do {
                try await run(&job)
                let doneJob = job
                await MainActor.run {
                    if let id = doneJob.taskID { lastTaskIDs[doneJob.id] = id }
                    queue.removeAll { $0.id == doneJob.id }
                    save()
                }
            } catch {
                job.attempts += 1
                job.lastError = (error as? ThingsError)?.description ?? error.localizedDescription
                let transient = (error as? ThingsError)?.isTransient ?? true
                let jobCopy = job
                await MainActor.run {
                    if let i = queue.firstIndex(where: { $0.id == jobCopy.id }) {
                        // Give up on permanent errors after a few tries.
                        if !transient && jobCopy.attempts >= 3 { queue.remove(at: i) } else { queue[i] = jobCopy }
                    }
                    save()
                }
                if transient { break }
            }
        }
    }

    /// Performs the remaining steps for one job, saving progress after each.
    func run(_ job: inout LogJob) async throws {
        let s = job.session
        if job.isFreeText && !job.createdLogEntry {
            let area = try await client.ensureArea()
            job.taskID = try await client.create(ThingsPayload.createBody(s, areaID: area))
            job.createdLogEntry = true
            persist(job)
        }
        guard let id = job.taskID else { throw ThingsError.http(400, "No to-do to log onto") }
        if !job.timeLogged {
            do {
                switch try await client.addTime(id, ThingsPayload.timeBody(s)) {
                case .logged: break
                case .endpointMissing:
                    // Older Things 4: the free-text entry already carries the times in its notes.
                    if !job.isFreeText { try await client.appendNotes(id, ThingsPayload.appendNotesBody(s)) }
                }
            } catch ThingsError.http(404, _) where !job.isFreeText {
                // The picked to-do is gone (deleted, emptied from Trash): keep the time in the Focus Log instead.
                job.session.taskID = nil
                job.taskID = nil
                job.createdLogEntry = false
                persist(job)
                try await run(&job)
                return
            }
            job.timeLogged = true
            persist(job)
        }
        if job.isFreeText && !job.completed {
            try await client.complete(id)
            job.completed = true
            persist(job)
        }
    }

    private func persist(_ job: LogJob) {
        let copy = job
        DispatchQueue.main.async {
            if let i = self.queue.firstIndex(where: { $0.id == copy.id }) {
                self.queue[i] = copy
                self.save()
            }
        }
    }

    private func save() {
        JSONFiles.save(queue, to: queueURL)
        onChange?()
    }
}
