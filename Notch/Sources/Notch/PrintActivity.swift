import Foundation
import NotchCUPS

struct PrintActivity: Equatable {
    let jobCount: Int
    let progress: Double?

    var label: String { jobCount == 1 ? "1 print job" : "\(jobCount) print jobs" }

    struct Job {
        var state: Int32?
        var impressions: Int32?
        var impressionsCompleted: Int32?
        var sheets: Int32?
        var sheetsCompleted: Int32?

        var progress: Double? {
            guard state == Int32(IPP_JSTATE_PROCESSING.rawValue) else { return nil }
            for (total, completed) in [(impressions, impressionsCompleted), (sheets, sheetsCompleted)] {
                if let total, total > 0, let completed, completed >= 0 {
                    return min(1, Double(completed) / Double(total))
                }
            }
            return nil
        }
    }

    static func summarize(_ jobs: [Job]) -> Self? {
        guard !jobs.isEmpty else { return nil }
        return Self(jobCount: jobs.count, progress: jobs.count == 1 ? jobs[0].progress : nil)
    }

    static func readQueue() -> Self? {
        guard let connection = httpConnect2("/var/run/cupsd", 0, nil, AF_UNSPEC, HTTP_ENCRYPTION_IF_REQUESTED, 1, 1500, nil) else { return nil }
        defer { httpClose(connection) }
        httpSetTimeout(connection, 2, nil, nil)

        guard let request = notchCreatePrintQueueRequest() else { return nil }

        // cupsDoRequest consumes the request, including on failure.
        guard let response = cupsDoRequest(connection, request, "/") else { return nil }
        defer { ippDelete(response) }
        guard ippGetStatusCode(response).rawValue < IPP_STATUS_ERROR_BAD_REQUEST.rawValue else { return nil }

        var jobs: [Job] = []
        var job = Job()
        var hasJobID = false
        var attribute = ippFirstAttribute(response)
        while let current = attribute {
            attribute = ippNextAttribute(response)
            guard let name = ippGetName(current) else {
                if hasJobID { jobs.append(job) }
                job = Job()
                hasJobID = false
                continue
            }
            guard ippGetGroupTag(current) == IPP_TAG_JOB,
                  ippGetValueTag(current) == IPP_TAG_INTEGER || ippGetValueTag(current) == IPP_TAG_ENUM else { continue }
            let value = ippGetInteger(current, 0)
            switch String(cString: name) {
            case "job-id": hasJobID = true
            case "job-state": job.state = value
            case "job-impressions": job.impressions = value
            case "job-impressions-completed": job.impressionsCompleted = value
            case "job-media-sheets": job.sheets = value
            case "job-media-sheets-completed": job.sheetsCompleted = value
            default: break
            }
        }
        if hasJobID { jobs.append(job) }
        return summarize(jobs)
    }
}
