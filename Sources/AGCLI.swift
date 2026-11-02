import Foundation
import AppKit
import Darwin

/// Uses the vendor's documented usage command. No OAuth tokens are read or copied by this app.
enum AGCLI {
    static let executable = "/Applications/Gemini.app/Contents/Helpers/agy"
    static func parse(_ data: Data) throws -> [AGQuota] {
        guard let report = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AGError.unavailable }
        if report["status"] as? String != "SUCCESS" {
            let reason = (report["error"] as? String ?? "").lowercased()
            if reason.contains("auth") || reason.contains("login") || reason.contains("sign in") { throw AGError.hostAuthentication }
            throw AGError.unavailable
        }
        guard let command = report["command"] as? [String:Any], command["name"] as? String == "usage",
              let payload = command["data"] as? [String:Any], let groups = payload["groups"] as? [[String:Any]] else { throw AGError.unavailable }
        var result:[AGQuota] = []
        let formatter=ISO8601DateFormatter()
        for group in groups {
            let groupName = group["display_name"] as? String ?? group["displayName"] as? String ?? group["name"] as? String ?? "模型组"
            for bucket in group["buckets"] as? [[String:Any]] ?? [] {
                guard bucket["disabled"] as? Bool != true else { continue }
                let nested = bucket["remaining"] as? [String:Any] ?? [:]
                guard let fraction = (bucket["remaining_fraction"] ?? bucket["remainingFraction"] ?? nested["remaining_fraction"] ?? nested["remainingFraction"]) as? NSNumber,
                      CFGetTypeID(fraction) != CFBooleanGetTypeID(), fraction.doubleValue.isFinite, (0...1).contains(fraction.doubleValue) else { continue }
                let title = bucket["display_name"] as? String ?? bucket["displayName"] as? String ?? bucket["name"] as? String ?? bucket["window"] as? String ?? bucket["bucket_id"] as? String ?? bucket["bucketId"] as? String ?? "额度"
                let raw = bucket["reset_time"] as? String ?? bucket["resetTime"] as? String
                formatter.formatOptions = [.withInternetDateTime]
                var date = raw.flatMap { formatter.date(from:$0) }
                if date == nil { formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; date = raw.flatMap { formatter.date(from:$0) } }
                let hint = title.lowercased()
                let window = bucket["window"] as? String ?? (hint.contains("five hour") || hint.contains("五小时") ? "5h" : hint.contains("weekly") || hint.contains("每周") ? "weekly" : "")
                result.append(AGQuota(name:groupName+" · "+title,remaining:fraction.doubleValue*100,reset:date,group:groupName,window:window))
            }
        }
        guard !result.isEmpty else { throw AGError.unavailable }
        return Dictionary(result.map{($0.name,$0)},uniquingKeysWith:{$0.remaining < $1.remaining ? $0 : $1}).values.sorted{$0.name < $1.name}
    }
    static func fetch() throws -> [AGQuota] {
        guard FileManager.default.isExecutableFile(atPath:executable) else { throw AGError.notRunning }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quota-usage-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:directory) }
        // Passive refresh must never open an OAuth browser window on its own.
        for name in ["open","xdg-open"] {
            let path=directory.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to:path)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:path.path)
        }
        let p=Process(), pipe=Pipe()
        p.executableURL=URL(fileURLWithPath:executable)
        p.arguments=["-p","/usage","--output-format","json","--print-timeout","20s"]
        p.currentDirectoryURL=directory;p.standardOutput=pipe;p.standardError=FileHandle.nullDevice;p.standardInput=FileHandle.nullDevice
        var env=ProcessInfo.processInfo.environment
        env["AGY_CLI_DISABLE_AUTO_UPDATE"]="true";env["BROWSER"]="/usr/bin/false"
        env["PATH"]=directory.path+":/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment=env
        try p.run()
        defer {
            if p.isRunning { p.terminate() }
            let grace=Date().addingTimeInterval(0.3)
            while p.isRunning && Date()<grace { usleep(10_000) }
            if p.isRunning { kill(p.processIdentifier,SIGKILL) }
            p.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        var data=Data();let deadline=Date().addingTimeInterval(25)
        while Date()<deadline {
            var fd=pollfd(fd:pipe.fileHandleForReading.fileDescriptor,events:Int16(POLLIN|POLLHUP),revents:0)
            let ready=poll(&fd,1,200)
            if ready < 0 { if errno==EINTR { continue };throw AGError.unavailable }
            if ready==0 { continue }
            var bytes=[UInt8](repeating:0,count:8192)
            let count=bytes.withUnsafeMutableBytes{Darwin.read(fd.fd,$0.baseAddress,$0.count)}
            if count==0 { return try parse(data) }
            if count<0 { if errno==EINTR {continue};throw AGError.unavailable }
            data.append(contentsOf:bytes.prefix(count))
            guard data.count<=1_048_576 else { throw AGError.unavailable }
        }
        throw AGError.unavailable
    }
    @MainActor static func connect() throws {
        guard FileManager.default.isExecutableFile(atPath:executable) else { throw AGError.notRunning }
        let folder=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("QuotaCompanion")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let script=folder.appendingPathComponent("Connect-Antigravity.command")
        let text="""
        #!/bin/zsh
        export AGY_CLI_DISABLE_AUTO_UPDATE=true
        QUOTA_LOGIN_DIR="$(mktemp -d)"
        trap 'rmdir "$QUOTA_LOGIN_DIR" 2>/dev/null || true' EXIT
        cd "$QUOTA_LOGIN_DIR" || exit 1
        echo '请在官方 CLI 中完成 Google 登录。完成后返回额度助手，点击刷新。不要输入开发任务。'
        '/Applications/Gemini.app/Contents/Helpers/agy'
        """
        try Data(text.utf8).write(to:script,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        NSWorkspace.shared.open(script)
    }
}
import CoreFoundation
