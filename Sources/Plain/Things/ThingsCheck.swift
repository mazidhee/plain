import Foundation

/// `Plain --things-check`: logs sessions to a scratch Things 4 instance and reads them back.
/// Refuses to run against the real Things 4 data (PLAIN_THINGS_CONFIG must point elsewhere).
enum ThingsCheck {
    static func run() -> Bool {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Things4/api.json")
        guard let env = ProcessInfo.processInfo.environment["PLAIN_THINGS_CONFIG"], !env.isEmpty,
              URL(fileURLWithPath: env).standardizedFileURL != real.standardizedFileURL else {
            print("Refusing: set PLAIN_THINGS_CONFIG to a scratch instance's api.json (never the real one).")
            return false
        }
        guard let config = ThingsClient.loadConfig(), config.baseURL.port != 7474 else {
            print("Refusing: the scratch config is missing or uses the real port 7474.")
            return false
        }
        print("Things check against \(config.baseURL)")
        var ok = true
        func check(_ cond: Bool, _ name: String, _ detail: String = "") {
            print("\(cond ? "ok  " : "FAIL") \(name) \(detail)")
            if !cond { ok = false }
        }

        var finished = false
        Task {
            let client = ThingsClient()
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("plain-check-\(UUID().uuidString).json")
            let logger = ThingsLogger(client: client, queueURL: tmp)
            let start = Date().addingTimeInterval(-41 * 60)

            // 0. Things away: the entry waits in the queue, and goes out once Things is back.
            let away = FileManager.default.temporaryDirectory.appendingPathComponent("plain-away-\(UUID().uuidString).json")
            try? #"{"port": 9, "token": "nope-nope-nope-nope-nope-nope-nope-nope"}"#.write(to: away, atomically: true, encoding: .utf8)
            ThingsClient.configOverride = away
            let queued = CompletedSession(title: "Offline session", category: .work, start: start, end: start.addingTimeInterval(600),
                                          minutes: 10, plannedMinutes: 10)
            let r0 = await logger.log(queued)
            check(r0.error != nil && logger.queue.count == 1, "offline: queued", r0.error ?? "")
            let onDisk = JSONFiles.load([LogJob].self, from: tmp) ?? []
            check(onDisk.count == 1, "offline: queue saved to disk")
            ThingsClient.configOverride = nil
            try? FileManager.default.removeItem(at: away)
            await logger.flush()
            check(logger.queue.isEmpty, "back online: queue flushed")

            // 1. Free text → completed Focus Log entry with tracked time.
            let free = CompletedSession(title: "System design docs", category: .study, start: start, end: start.addingTimeInterval(40 * 60),
                                        minutes: 40, plannedMinutes: 40)
            let r1 = await logger.log(free)
            check(r1.error == nil && r1.taskID != nil, "free-text session logged", r1.error ?? "")
            if let id = r1.taskID, let json = try? await client.request("GET", "tasks/\(id)") as? [String: Any] {
                check(json["title"] as? String == "📖 System design docs — 40 min", "title", "\(json["title"] ?? "")")
                check(json["status"] as? String == "completed", "completed (in Logbook)", "\(json["status"] ?? "")")
                check((json["area"] as? [String: Any])?["title"] as? String == "Focus Log", "in Focus Log area", "\(json["area"] ?? "none")")
                let tags = json["tags"] as? [String] ?? []
                check(tags.contains("focus") && tags.contains("study"), "tagged focus + study", "\(tags)")
                check(json["tracked_minutes"] as? Int == 40, "tracked 40 min", "\(json["tracked_minutes"] ?? "nil")")
                check((json["notes"] as? String ?? "").contains("Started:"), "notes have start/end")
            } else { check(false, "read back free-text entry") }

            // 2. A picked to-do: time lands on it, nothing new is created.
            do {
                let id = try await client.create(["title": "Read chapter 6 (Plain check)", "when": "today"])
                let today = try await client.today()
                check(today.contains { $0.id == id }, "picker sees today's to-do")
                let found = try await client.search("chapter 6")
                check(found.contains { $0.id == id }, "search finds it")
                var linked = free
                linked.id = UUID()
                linked.title = "Read chapter 6 (Plain check)"
                linked.taskID = id
                linked.minutes = 25
                let r2 = await logger.log(linked)
                check(r2.error == nil && r2.taskID == id, "linked session logged", r2.error ?? "")
                var partial = linked
                partial.id = UUID()
                partial.minutes = 7
                partial.canceled = true
                _ = await logger.log(partial)
                let after = try await client.task(id)
                check(after?.trackedMinutes == 32, "tracked 25 + 7 on the to-do", "\(after?.trackedMinutes ?? -1)")
                let entries = try await client.request("GET", "tasks/\(id)/time") as? [String: Any]
                check((entries?["entries"] as? [Any])?.count == 2, "two time entries", "\(entries?["tracked"] ?? "")")
                try await client.complete(id)
                let doneJSON = try await client.request("GET", "tasks/\(id)") as? [String: Any]
                check(doneJSON?["status"] as? String == "completed", "Mark done in Things")
                let total = try await client.trackedToday()
                check(total >= 72, "GET /v1/time?since=today total", "\(total)")
            } catch { check(false, "linked flow", "\(error)") }

            // 2b. Modes only see their own area.
            do {
                _ = try await client.request("POST", "areas", body: ["title": "Work"])
                _ = try await client.request("POST", "areas", body: ["title": "Learning"])
                let w = try await client.create(["title": "Work thing (Plain check)", "list": "Work"])
                let l = try await client.create(["title": "Learning thing (Plain check)", "list": "Learning"])
                let titles = try await client.areaTitles()
                let workArea = AreaMatcher.area(for: .work, chosen: nil, titles: titles)
                let studyArea = AreaMatcher.area(for: .study, chosen: nil, titles: titles)
                check(workArea == "Work" && studyArea == "Learning", "modes match areas", "\(titles)")
                let work = try await client.list("Work"), learning = try await client.list("Learning")
                check(work.contains { $0.id == w } && !work.contains { $0.id == l }, "Work shows only work", "\(work.map(\.title))")
                check(learning.contains { $0.id == l } && !learning.contains { $0.id == w }, "Study shows only learning", "\(learning.map(\.title))")
                let all = try await client.allOpen()
                check(all.contains { $0.id == w } && all.contains { $0.id == l }, "all open to-dos load", "\(all.count)")
                check(TaskSearch.rank("learnin thing", in: all).first?.title == "Learning thing (Plain check)", "fuzzy search finds it")
            } catch { check(false, "area flow", "\(error)") }

            // 3. Missing to-do falls back to the Focus Log.
            var ghost = free
            ghost.id = UUID()
            ghost.taskID = "NO-SUCH-TASK"
            ghost.title = "Ghost task"
            ghost.minutes = 5
            let r3 = await logger.log(ghost)
            check(r3.error == nil && r3.taskID != "NO-SUCH-TASK", "unknown to-do falls back to Focus Log", r3.error ?? "")
            check(logger.queue.isEmpty, "queue empty after success")
            try? FileManager.default.removeItem(at: tmp)
            finished = true
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        return ok
    }
}
