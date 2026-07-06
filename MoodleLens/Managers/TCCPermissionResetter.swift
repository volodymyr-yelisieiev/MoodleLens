//
//  TCCPermissionResetter.swift
//  MoodleLens
//

import Foundation

enum TCCPermissionResetter {
    static let bundleIdentifier = "io.github.volodymyryelisieiev.moodlelens"

    static func reset(service: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleIdentifier]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                DispatchQueue.main.async {
                    completion(success)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
}
