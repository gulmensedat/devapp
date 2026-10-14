import Foundation

struct GitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Git {
    struct Result {
        let code: Int32
        let output: String
    }

    static func run(_ args: [String], in dir: String) async -> Result {
        await withCheckedContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", dir] + args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: Result(code: proc.terminationStatus, output: text))
            }
            do {
                try process.run()
            } catch {
                cont.resume(returning: Result(code: -1, output: error.localizedDescription))
            }
        }
    }

    static func currentBranch(in dir: String) async -> String? {
        let r = await run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir)
        return r.code == 0 && !r.output.isEmpty ? r.output : nil
    }

    static func isRepository(_ dir: String) async -> Bool {
        await run(["rev-parse", "--is-inside-work-tree"], in: dir).code == 0
    }

    /// ~/.devapp/worktrees/<proje>/<branch> altında yeni bir worktree açar ve yolunu döner.
    static func addWorktree(repo: String, branch: String) async throws -> String {
        let fm = FileManager.default
        let projectName = URL(fileURLWithPath: repo).lastPathComponent
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".devapp/worktrees/\(projectName)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        let safe = branch.replacingOccurrences(of: "/", with: "-")
        var path = base.appendingPathComponent(safe).path
        var n = 2
        while fm.fileExists(atPath: path) {
            path = base.appendingPathComponent("\(safe)-\(n)").path
            n += 1
        }

        let branchExists = await run(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"], in: repo).code == 0
        let args = branchExists
            ? ["worktree", "add", path, branch]
            : ["worktree", "add", "-b", branch, path]
        let r = await run(args, in: repo)
        guard r.code == 0 else { throw GitError(message: r.output) }
        return path
    }
}
