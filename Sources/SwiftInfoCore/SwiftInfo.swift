import Foundation

public struct SwiftInfo {
    public let projectInfo: ProjectInfo
    public let fileUtils: FileUtils
    public let slackFormatter: SlackFormatter
    public let client: HTTPClient
    public let sourceKit: SourceKit

    public init(projectInfo: ProjectInfo,
                fileUtils: FileUtils = .init(),
                slackFormatter: SlackFormatter = .init(),
                client: HTTPClient = .init(),
                sourceKit: SourceKit? = nil) {
        self.projectInfo = projectInfo
        self.fileUtils = fileUtils
        self.slackFormatter = slackFormatter
        self.client = client
        if let sourceKit = sourceKit {
            self.sourceKit = sourceKit
        } else {
            let toolchain = UserDefaults.standard.string(forKey: "toolchain") ?? ""
            self.sourceKit = SourceKit(path: toolchain)
        }
    }

    public func extract<T: InfoProvider>(_ provider: T.Type,
                                         args: T.Arguments? = nil) -> Output {
        do {
            log("Extracting \(provider.identifier)")
            let extracted = try provider.extract(fromApi: self, args: args)
            log("\(provider.identifier): Parsing previously extracted info", verbose: true)
            let other = try fileUtils.lastOutput().extractedInfo(ofType: provider)
            log("\(provider.identifier): Comparing with previously extracted info", verbose: true)
            let summary = extracted.summary(comparingWith: other, args: args)
            log("\(provider.identifier): Finishing", verbose: true)
            let info = ExtractedInfo(data: extracted, summary: summary)
            return try Output(info: info)
        } catch {
            let message = "**\(provider.identifier):** \(error.localizedDescription)"
            log(message)
            return Output(rawDictionary: [:],
                          summaries: [],
                          errors: [message])
        }
    }

    public func sendToSlack(output: Output, webhookUrl: String) {
        log("Sending to Slack")
        log("Slack Webhook: \(webhookUrl)", verbose: true)
        let formatted = slackFormatter.format(output: output, projectInfo: projectInfo)
        client.syncPost(urlString: webhookUrl, json: formatted)
    }

    public func save(output: Output,
                     timestamp: TimeInterval = Date().timeIntervalSince1970) {
        log("Saving output to disk")
        var dict = output.rawDictionary
        dict["swiftinfo_run_project_info"] = [
            "xcodeproj": projectInfo.xcodeproj,
            "target": projectInfo.target,
            "configuration": projectInfo.configuration,
            "versionString": (try? projectInfo.versionString()) ?? "(Failed to parse version)",
            "buildNumber": (try? projectInfo.buildNumber()) ?? "(Failed to parse build number)",
            "description": projectInfo.description,
            "timestamp": timestamp
        ]
        do {
            let outputFile = try fileUtils.outputArray()
            try fileUtils.save(output: [dict] + outputFile)
        } catch {
            fail(error.localizedDescription)
        }
    }
}

public func fail(_ message: String) -> Never {
    log("Fatal error: \(message)")
    exit(-1)
}
