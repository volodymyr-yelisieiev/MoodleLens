//
//  BrowserContextProvider.swift
//  MoodleLens
//

import AppKit
import Carbon
import Foundation

enum BrowserContextProvider {
    static let contextInfoKey = "browserContext"
    static let failureReasonKey = "browserContextFailureReason"
    static let failureMessageKey = "browserContextFailureMessage"
    private static let maxContextLength = 20_000
    private static let logFileName = "browser-context.log"
    private static let askRecentBrowserFallbackSeconds: TimeInterval = 10
    private static let settingsRecentBrowserFallbackSeconds: TimeInterval = 300
    private static var lastStatus = "Not checked yet."
    private static var activationObserver: NSObjectProtocol?
    private static var recentBrowser: (browser: BrowserTarget, activatedAt: Date)?

    static var lastStatusSummary: String {
        lastStatus
    }

    private struct BrowserTarget {
        let bundleID: String
        let name: String
    }

    private static let supportedBrowsers = [
        BrowserTarget(bundleID: "com.google.Chrome", name: "Google Chrome"),
        BrowserTarget(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary"),
        BrowserTarget(bundleID: "company.thebrowser.Browser", name: "Arc"),
        BrowserTarget(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        BrowserTarget(bundleID: "com.brave.Browser", name: "Brave Browser"),
        BrowserTarget(bundleID: "org.chromium.Chromium", name: "Chromium")
    ]

    enum FailureReason: String {
        case noSupportedBrowser = "no_supported_browser"
        case automationNotGranted = "automation_not_granted"
        case snapshotFailed = "snapshot_failed"
        case javascriptFromAppleEventsDisabled = "javascript_from_apple_events_disabled"
        case nonMoodlePage = "non_moodle_page"
        case noExtractableMoodleTask = "no_task_found"
        case emptySnapshot = "empty_snapshot"

        var userMessage: String {
            switch self {
            case .noSupportedBrowser:
                return "Open a supported browser with a Moodle page, then press Ask again."
            case .automationNotGranted:
                return "Browser Context permission is not granted. Open Settings and grant Browser Context access."
            case .snapshotFailed:
                return "Could not read the active browser page. Refresh the Moodle tab or repair Browser Context in Settings."
            case .javascriptFromAppleEventsDisabled:
                return "Browser Context can reach the browser, but JavaScript from Apple Events is disabled. In the browser menu, enable View > Developer > Allow JavaScript from Apple Events."
            case .nonMoodlePage:
                return "The active browser page is not Moodle. Open a Moodle quiz or assignment page and try again."
            case .noExtractableMoodleTask:
                return "Moodle is open, but I could not find an extractable question or assignment on this page."
            case .emptySnapshot:
                return "Moodle is open, but the browser snapshot was empty. Refresh the page and try again."
            }
        }
    }

    enum ContextResult: Equatable {
        case attached(String)
        case failure(FailureReason)
    }

    static func startTrackingFrontmostBrowser() {
        guard activationObserver == nil else { return }
        _ = rememberFrontmostBrowserIfSupported()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let browser = supportedBrowser(for: app.bundleIdentifier) else {
                return
            }
            recentBrowser = (browser, Date())
        }
    }

    static func currentContext() -> String? {
        guard case .attached(let context) = currentContextResult() else { return nil }
        return context
    }

    static func currentContextResult() -> ContextResult {
        guard let browser = frontmostSupportedBrowser(allowRecentFallback: true) else {
            let app = NSWorkspace.shared.frontmostApplication
            record("skip=no_supported_frontmost frontmost=\(app?.localizedName ?? "unknown") bundle=\(app?.bundleIdentifier ?? "unknown") \(recentBrowserSummary())")
            return .failure(.noSupportedBrowser)
        }

        guard automationAllowed(for: browser.bundleID, askUserIfNeeded: false) else {
            record("skip=automation_not_granted browser=\(browser.name) bundle=\(browser.bundleID) \(frontmostSummary()) \(recentBrowserSummary())")
            return .failure(.automationNotGranted)
        }

        let snapshot = runSnapshotScript(in: browser.bundleID)
        guard let json = snapshot.json else {
            let reason = snapshotFailureReason(for: snapshot.error)
            record("skip=\(reason.rawValue) browser=\(browser.name) bundle=\(browser.bundleID) \(frontmostSummary()) \(recentBrowserSummary()) error=\(snapshot.error ?? "unknown")")
            return .failure(reason)
        }

        let result = contextResult(from: json, browserName: browser.name)
        switch result {
        case .attached(let context):
            record("attached browser=\(browser.name) bundle=\(browser.bundleID) json_length=\(json.count) context_length=\(context.count) moodle=true")
        case .failure(let reason):
            record("skip=\(reason.rawValue) browser=\(browser.name) bundle=\(browser.bundleID) json_length=\(json.count)")
        }
        return result
    }

    static func addCurrentContext(to contextInfo: [String: Any]?) -> [String: Any]? {
        var updated = contextInfo ?? [:]
        switch currentContextResult() {
        case .attached(let context):
            updated[contextInfoKey] = context
            updated.removeValue(forKey: failureReasonKey)
            updated.removeValue(forKey: failureMessageKey)
        case .failure(let reason):
            updated[failureReasonKey] = reason.rawValue
            updated[failureMessageKey] = reason.userMessage
        }
        return updated
    }

    static func frontmostBrowserName() -> String? {
        frontmostSupportedBrowser()?.name
    }

    static func automationTargetNameForSettings() -> String? {
        automationTargetForSettings()?.name
    }

    static func frontmostBrowserHasAutomationPermission() -> Bool {
        guard let browser = automationTargetForSettings() else { return false }
        return automationAllowed(for: browser.bundleID, askUserIfNeeded: false)
    }

    @discardableResult
    static func requestAutomationForFrontmostBrowser() -> Bool {
        guard let browser = automationTargetForSettings() else { return false }
        let granted = automationAllowed(for: browser.bundleID, askUserIfNeeded: true)
        record("grant browser=\(browser.name) bundle=\(browser.bundleID) granted=\(granted)")
        return granted
    }

    static func resetAutomationPermission(completion: @escaping (Bool) -> Void) {
        TCCPermissionResetter.reset(service: "AppleEvents", completion: completion)
    }

    static func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func compactContext(from json: String, browserName: String = "Browser") -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var lines: [String] = ["Browser Context (\(browserName))"]
        append("URL", object["url"], to: &lines)
        append("Title", object["title"], to: &lines)
        append("Course", object["moodleCourse"], to: &lines)
        append("Activity", object["moodleActivity"], to: &lines)
        appendMoodleTasks(object["moodleTasks"], to: &lines)
        appendList("Moodle Questions", object["moodleQuestions"], to: &lines)
        appendList("Moodle Activities", object["moodleActivities"], to: &lines)
        append("Visible Text", object["text"], to: &lines, limit: 6_000)
        append("All Text", object["fullText"], to: &lines, limit: 4_000)
        appendList("Inputs", object["inputs"], to: &lines)
        appendList("Buttons", object["buttons"], to: &lines)
        appendList("Select Options", object["selects"], to: &lines)
        appendList("Menu Controls", object["menuControls"], to: &lines)
        appendList("Aria Menu Items", object["ariaMenuItems"], to: &lines)
        appendList("Controls", object["controls"], to: &lines)
        appendList("Menu Linked Items", object["controlLinkedMenus"], to: &lines)
        appendList("Deep Menu Items", object["menuItems"], to: &lines)
        appendList("Lists", object["lists"], to: &lines)
        appendList("Datalist Options", object["datalistOptions"], to: &lines)
        appendList("Datalists", object["datalists"], to: &lines)
        appendList("ARIA/Menu Options", object["options"], to: &lines)
        appendList("Links", object["links"], to: &lines)

        let context = lines.joined(separator: "\n")
        return String(context.prefix(maxContextLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contextResult(from json: String, browserName: String = "Browser") -> ContextResult {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.snapshotFailed)
        }

        guard isMoodleSnapshot(object) else {
            return .failure(.nonMoodlePage)
        }

        guard hasExtractableMoodleTask(object) else {
            return .failure(.noExtractableMoodleTask)
        }

        guard let context = compactContext(from: json, browserName: browserName), !context.isEmpty else {
            return .failure(.emptySnapshot)
        }

        return .attached(context)
    }

    private static func isMoodleSnapshot(_ object: [String: Any]) -> Bool {
        if object["moodleConfig"] as? Bool == true {
            return true
        }

        let url = lowercasedString(object["url"])
        if isMoodleURL(url) {
            return true
        }

        let markers = [
            object["generator"],
            object["bodyID"],
            object["bodyClasses"],
            object["htmlClasses"]
        ].map(lowercasedString).joined(separator: " ")
        return markers.contains("moodle") || markers.contains("page-mod-")
    }

    private static func isMoodleURL(_ rawURL: String) -> Bool {
        guard let components = URLComponents(string: rawURL),
              let host = components.host?.lowercased() else {
            return false
        }

        let labels = host.split(separator: ".").map(String.init)
        let moodleHost = labels.contains { label in
            label == "moodle" || label == "moodledemo" || label.hasPrefix("moodle-") || label.hasPrefix("moodle")
        }
        guard moodleHost else { return false }

        let path = components.percentEncodedPath.lowercased()
        guard !path.isEmpty, path != "/" else { return true }

        let moodlePaths = [
            "/mod/",
            "/course/",
            "/login/",
            "/my/",
            "/user/",
            "/grade/",
            "/question/",
            "/blocks/",
            "/pluginfile.php",
            "/calendar/",
            "/admin/"
        ]
        return moodlePaths.contains { path.contains($0) }
    }

    private static func hasExtractableMoodleTask(_ object: [String: Any]) -> Bool {
        if let tasks = object["moodleTasks"] as? [[String: Any]],
           tasks.contains(where: hasStructuredTaskEvidence) {
            return true
        }

        let explicitEvidence = stringArray(object["moodleQuestions"]) + stringArray(object["moodleActivities"])
        if explicitEvidence.contains(where: { $0.count >= 20 }) {
            return true
        }

        let evidenceText = [
            object["title"],
            object["text"],
            object["fullText"]
        ].map(lowercasedString).joined(separator: " ")
        guard evidenceText.count >= 40 else { return false }

        let taskMarkers = [
            "question",
            "answer",
            "quiz",
            "attempt",
            "assignment",
            "submission",
            "submit",
            "points",
            "grade",
            "due date",
            "multiple choice",
            "frage",
            "antwort",
            "versuch",
            "abgabe",
            "einreichen",
            "punkte",
            "bewertung",
            "fällig",
            "aufgabe"
        ]
        return taskMarkers.contains { evidenceText.contains($0) }
    }

    private static func hasStructuredTaskEvidence(_ task: [String: Any]) -> Bool {
        let text = lowercasedString(task["questionText"])
        if text.count >= 12 { return true }
        if let options = task["options"] as? [[String: Any]],
           options.contains(where: { lowercasedString($0["text"]).count >= 2 }) {
            return true
        }
        return lowercasedString(task["feedback"]).count >= 12
    }

    private static func lowercasedString(_ value: Any?) -> String {
        cleaned(value as? String)?.lowercased() ?? ""
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String])?.compactMap(cleaned) ?? []
    }

    private static func frontmostSupportedBrowser(allowRecentFallback: Bool = false) -> BrowserTarget? {
        if let browser = rememberFrontmostBrowserIfSupported() {
            return browser
        }

        guard allowRecentFallback,
              let recentBrowser,
              Date().timeIntervalSince(recentBrowser.activatedAt) < askRecentBrowserFallbackSeconds else {
            return nil
        }
        return recentBrowser.browser
    }

    private static func rememberFrontmostBrowserIfSupported() -> BrowserTarget? {
        guard let browser = supportedBrowser(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else {
            return nil
        }
        recentBrowser = (browser, Date())
        return browser
    }

    private static func supportedBrowser(for bundleID: String?) -> BrowserTarget? {
        guard let bundleID else { return nil }
        return supportedBrowsers.first { $0.bundleID == bundleID }
    }

    private static func automationTargetForSettings() -> BrowserTarget? {
        if let frontmost = frontmostSupportedBrowser() {
            return frontmost
        }

        if let recentBrowser,
           Date().timeIntervalSince(recentBrowser.activatedAt) < settingsRecentBrowserFallbackSeconds {
            return recentBrowser.browser
        }

        for browser in supportedBrowsers where NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty == false {
            return browser
        }
        return nil
    }

    private static func automationAllowed(for bundleID: String, askUserIfNeeded: Bool) -> Bool {
        var target = AEAddressDesc()
        let createStatus = bundleID.withCString { pointer in
            AECreateDesc(DescType(typeApplicationBundleID), pointer, bundleID.utf8.count, &target)
        }
        guard createStatus == noErr else { return false }
        defer { AEDisposeDesc(&target) }

        return AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        ) == noErr
    }

    private static func runSnapshotScript(in bundleID: String) -> (json: String?, error: String?) {
        let encodedJavaScript = Data(snapshotJavaScript.utf8).base64EncodedString()
        let source = """
        tell application id "\(bundleID)"
            if (count of windows) is 0 then return ""
            set js to "eval(atob('\(encodedJavaScript)'))"
            return execute front window's active tab javascript js
        end tell
        """

        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil else {
            let code = error?[NSAppleScript.errorNumber] ?? "unknown"
            let message = error?[NSAppleScript.errorMessage] ?? "unknown"
            return (nil, "code=\(code) message=\(message)")
        }
        return (result?.stringValue, nil)
    }

    static func snapshotFailureReason(for error: String?) -> FailureReason {
        let error = error?.lowercased() ?? ""
        if error.contains("allow javascript from apple events") ||
            error.contains("javascript through applescript is turned off") {
            return .javascriptFromAppleEventsDisabled
        }
        return .snapshotFailed
    }

    private static func frontmostSummary() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        return "frontmost=\(app?.localizedName ?? "unknown") bundle=\(app?.bundleIdentifier ?? "unknown")"
    }

    private static func recentBrowserSummary() -> String {
        guard let recentBrowser else { return "recent=none" }
        let age = Int(Date().timeIntervalSince(recentBrowser.activatedAt).rounded())
        return "recent=\(recentBrowser.browser.name) recent_bundle=\(recentBrowser.browser.bundleID) recent_age_s=\(age)"
    }

    private static func record(_ summary: String) {
        lastStatus = summary

        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(summary)\n"
        do {
            let directory = try logDirectory()
            let file = directory.appendingPathComponent(logFileName)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Browser Context log failed: \(error.localizedDescription)")
        }
    }

    private static func logDirectory() throws -> URL {
        guard let baseDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "BrowserContextProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Library directory for Browser Context logging"]
            )
        }

        let base = baseDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MoodleLens", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func append(_ label: String, _ value: Any?, to lines: inout [String], limit: Int = 1_000) {
        guard let text = cleaned(value as? String), !text.isEmpty else { return }
        lines.append("\(label): \(String(text.prefix(limit)))")
    }

    private static func appendList(_ label: String, _ value: Any?, to lines: inout [String]) {
        guard let values = value as? [String] else { return }
        let cleanedValues = values.compactMap(cleaned).filter {
            !$0.isEmpty && !(label == "Inputs" && $0.localizedCaseInsensitiveContains("password"))
        }
        guard !cleanedValues.isEmpty else { return }
        lines.append("\(label):")
        lines.append(contentsOf: cleanedValues.prefix(80).map { "- \(String($0.prefix(160)))" })
    }

    private static func appendMoodleTasks(_ value: Any?, to lines: inout [String]) {
        guard let tasks = value as? [[String: Any]], !tasks.isEmpty else { return }
        lines.append("Moodle Structured Tasks:")
        for task in tasks.prefix(20) {
            let id = cleaned(task["id"] as? String) ?? "unknown"
            let type = cleaned(task["type"] as? String) ?? "unknown"
            let text = cleaned(task["questionText"] as? String) ?? ""
            lines.append("- \(id) [\(type)]: \(String(text.prefix(500)))")

            if let options = task["options"] as? [[String: Any]], !options.isEmpty {
                lines.append("  Options:")
                for option in options.prefix(40) {
                    let selected = (option["selected"] as? Bool) == true ? "* " : ""
                    let label = cleaned(option["text"] as? String) ?? ""
                    let value = cleaned(option["value"] as? String)
                    let suffix = value.map { " (\($0))" } ?? ""
                    if !label.isEmpty {
                        lines.append("  - \(selected)\(String(label.prefix(200)))\(suffix)")
                    }
                }
            }

            if let feedback = cleaned(task["feedback"] as? String), !feedback.isEmpty {
                lines.append("  Feedback: \(String(feedback.prefix(300)))")
            }

            if let controls = task["controls"] as? [String], !controls.isEmpty {
                lines.append("  Controls: \(controls.compactMap(cleaned).prefix(12).joined(separator: " / "))")
            }
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let snapshotJavaScript = #"""
    (function () {
      function clean(value) {
        return String(value || "").replace(/\s+/g, " ").trim();
      }
      function textValue(value) {
        return String(value || "").replace(/\s+/g, " ").trim();
      }
      function textOf(element) {
        if (!element) return "";
        if (element.type && String(element.type).toLowerCase() === "password") return "";
        var labels = [];
        if (element.labels && element.labels.length) {
          labels.push(clean(element.labels[0].innerText));
        }
        if (element.id) {
          try {
            Array.prototype.slice.call(document.querySelectorAll('label[for="' + element.id + '"]')).forEach(function (label) {
              if (label && label.innerText) {
                labels.push(clean(label.innerText));
              }
            });
          } catch (_) {}
        }
        if (element.getAttribute) {
          ["aria-label", "title", "aria-labelledby", "placeholder", "name", "id"].forEach(function (attribute) {
            var value = element.getAttribute(attribute);
            if (value) labels.push(clean(value));
          });
        }
        var value = element.value || "";
        if (Array.isArray(element.selectedOptions) && element.selectedOptions.length === 1) {
          value = clean(element.selectedOptions[0].text) || value;
        }
        if (value) {
          labels.push(clean(value));
        }
        var byLabelledBy = [];
        if (element.getAttribute && element.getAttribute("aria-labelledby")) {
          element.getAttribute("aria-labelledby").split(/\s+/).forEach(function (labelId) {
            var referenced = document.getElementById(labelId);
            if (referenced) byLabelledBy.push(clean(referenced.innerText || referenced.textContent || ""));
          });
        }
        labels = labels.concat(byLabelledBy);
        var innerText = textValue(element.innerText || element.textContent || "");
        if (innerText && innerText !== labels.join(" ")) {
          labels.push(innerText);
        }
        return clean(labels.filter(Boolean).join(" | "));
      }
      function visible(element) {
        var style = window.getComputedStyle(element);
        var rect = element.getBoundingClientRect();
        return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
      }
      function uniq(values, limit) {
        var seen = new Set();
        return values.map(clean).filter(function (value) {
          if (!value || seen.has(value)) return false;
          seen.add(value);
          return true;
        }).slice(0, limit || 80);
      }
      function collectWindows(win, windows, visited) {
        if (!win || visited.has(win)) return;
        try {
          if (!win.document) return;
        } catch (_) {
          return;
        }

        visited.add(win);
        windows.push(win);
        try {
          Array.prototype.slice.call(win.document.querySelectorAll("iframe, frame")).forEach(function (frame) {
            try {
              collectWindows(frame.contentWindow, windows, visited);
            } catch (_) {}
          });
        } catch (_) {}
      }
      function roots(root) {
        var found = [root];
        Array.prototype.slice.call(root.querySelectorAll("*")).forEach(function (element) {
          if (element.tagName && element.tagName.toLowerCase() === "slot") {
            var assigned = [];
            if (typeof element.assignedElements === "function") {
              try { assigned = Array.prototype.slice.call(element.assignedElements({ flatten: true })); } catch (_) {}
            } else if (typeof element.assignedNodes === "function") {
              try {
                assigned = Array.prototype.slice.call(element.assignedNodes({ flatten: true })).filter(function (node) {
                  return node && node.nodeType === 1;
                });
              } catch (_) {}
            }
            assigned.forEach(function (node) {
              if (node && node.querySelectorAll) {
                found = found.concat(roots(node));
              }
            });
          }

          if (element.shadowRoot) found = found.concat(roots(element.shadowRoot));
        });
        return found;
      }
      function all(selector) {
        var elements = [];
        var windows = [];
        var visited = new Set();
        collectWindows(window, windows, visited);
        windows.forEach(function (win) {
          try {
            var doc = win.document;
            roots(doc).forEach(function (root) {
              elements = elements.concat(Array.prototype.slice.call(root.querySelectorAll(selector)));
            });
          } catch (_) {}
        });
        return elements;
      }
      function collectOptionText(container, selectors) {
        try {
          var list = [];
          var nodes = Array.prototype.slice.call(container.querySelectorAll(selectors));
          for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var marker = node.getAttribute && (node.getAttribute("aria-selected") === "true" || node.selected) ? "* " : "";
            var fallback = "";
            if (node.value) fallback = node.value;
            if (!fallback && node.getAttribute) {
              ["value", "data-value", "aria-label", "title"].forEach(function (attribute) {
                if (!fallback) fallback = node.getAttribute(attribute);
              });
            }
            var value = clean(marker + textValue(node.textContent || node.innerText || fallback));
            if (value) {
              list.push(value);
            }
          }
          return list;
        } catch (_) {
          return [];
        }
      }
      function referencedControlValues(control) {
        var linkedValues = [];
        ["aria-controls", "aria-owns"].forEach(function (attribute) {
          var raw = control.getAttribute && control.getAttribute(attribute);
          if (!raw) return;
          raw.split(/\s+/).forEach(function (id) {
            if (!id) return;
            var referenced = document.getElementById(id);
            if (!referenced) return;
            var options = collectOptionText(referenced, "option, [role='option'], [role='menuitem'], [role='menuitemcheckbox'], [role='menuitemradio'], [role='tab'], li");
            if (!options.length) {
              options = collectOptionText(referenced, "*");
            }
            if (!options.length) return;
            var controlLabel = clean((control.getAttribute("aria-label") || control.tagName || "").toString());
            if (controlLabel) {
              linkedValues.push(controlLabel + ": " + options.join(" / "));
            } else {
              linkedValues.push(clean((control.id || "menu") + ": " + options.join(" / ")));
            }
          });
        });
        return linkedValues;
      }
      function list(selector, mapper, limit, requireVisible) {
        return uniq(all(selector).filter(function (element) {
          return requireVisible === false || visible(element);
        }).map(mapper), limit);
      }
      var inputs = list('input:not([type="hidden"]):not([type="password"]), textarea, [contenteditable="true"], [role="textbox"]', function (element) {
        return [element.labels && element.labels[0] && element.labels[0].innerText, element.name, element.id, element.placeholder, element.getAttribute("aria-label"), element.value, element.checked === true ? "checked" : ""].filter(Boolean).join(" | ");
      }, 80, true);
      var buttons = list('button, [role="button"], input[type="button"], input[type="submit"]', textOf, 80, true);
      var links = list('a[href]', textOf, 80, true);
      var selects = list('select', function (element) {
        var label = clean([element.name, element.id, element.getAttribute("aria-label")].filter(Boolean).join(" "));
        var selected = Array.prototype.slice.call(element.selectedOptions || []).map(function (option) { return clean(option.text); }).filter(Boolean).join(", ");
        var options = Array.prototype.slice.call(element.options).map(function (option) { return clean((option.selected ? "* " : "") + option.text); }).filter(Boolean).slice(0, 120).join(" / ");
        return clean(label + (selected ? " selected " + selected : "") + ": " + options);
      }, 80, false);
      var menuControls = list('[role="combobox"], [role="menu"], [role="listbox"], [role="tablist"], [role="tree"], [aria-haspopup], [aria-expanded]', function (element) {
        return clean([
          element.getAttribute("role") || element.tagName.toLowerCase(),
          element.getAttribute("aria-label"),
          element.getAttribute("aria-expanded") ? "expanded=" + element.getAttribute("aria-expanded") : "",
          element.getAttribute("aria-controls") ? "controls=" + element.getAttribute("aria-controls") : "",
          element.getAttribute("aria-owns") ? "owns=" + element.getAttribute("aria-owns") : "",
          textOf(element)
        ].filter(Boolean).join(" | "));
      }, 160, false);
      var controls = list('[role="combobox"], [role="menu"], [role="listbox"], [aria-haspopup], [aria-expanded], [aria-controls], [aria-owns]', function (element) {
        return clean([
          element.getAttribute("role"),
          element.getAttribute("aria-label"),
          element.getAttribute("aria-expanded") ? "expanded=" + element.getAttribute("aria-expanded") : "",
          element.getAttribute("aria-controls") ? "controls=" + element.getAttribute("aria-controls") : "",
          textOf(element)
        ].filter(Boolean).join(" | "));
      }, 120, false);
      var options = list('option, [role="option"], [role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"], [role="treeitem"], [role="listitem"], [role="tab"], [data-value], [aria-selected], li', function (element) {
        return clean([
          element.getAttribute("aria-selected") === "true" || element.selected ? "* " : "",
          element.getAttribute("data-value"),
          element.getAttribute("id"),
          textOf(element)
        ].filter(Boolean).join(" "));
      }, 180, false);
      var ariaMenuItems = list('[role="option"], [role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"], [role="treeitem"], [role="listitem"], [role="tab"]', function (element) {
        var marker = element.getAttribute && (element.getAttribute("aria-selected") === "true" || element.selected) ? "* " : "";
        return clean([
          marker,
          element.getAttribute("data-value"),
          element.getAttribute("id"),
          textOf(element)
        ].filter(Boolean).join(" "));
      }, 240, false);
      function collectDeepMenuValues(control) {
        var entries = [];
        var controlLabel = clean((control.getAttribute && (control.getAttribute("aria-label") || control.id) || control.tagName || "").toString());
        var optionSelector = "option, [role='option'], [role='menuitem'], [role='menuitemcheckbox'], [role='menuitemradio'], [role='tab'], [role='treeitem'], [role='listitem'], [data-value], li";
        function appendWithLabel(list, label) {
          if (!list.length) return;
          for (var i = 0; i < list.length; i++) {
            if (label) {
              entries.push(label + ": " + list[i]);
            } else {
              entries.push(list[i]);
            }
          }
        }
        ["aria-controls", "aria-owns"].forEach(function (attribute) {
          var raw = control.getAttribute && control.getAttribute(attribute);
          if (!raw) return;
          raw.split(/\s+/).forEach(function (id) {
            if (!id) return;
            var referenced = document.getElementById(id);
            if (!referenced) return;
            var firstPass = collectOptionText(referenced, optionSelector);
            if (!firstPass.length && referenced.querySelectorAll) {
              firstPass = collectOptionText(referenced, "[data-value], [aria-selected], [role], *");
            }
            appendWithLabel(firstPass, controlLabel);
          });
        });
        appendWithLabel(collectOptionText(control, optionSelector), controlLabel);
        return uniq(entries, 120);
      }
      var controlLinkedMenus = [];
      all('[aria-controls], [aria-owns]').forEach(function (control) {
        controlLinkedMenus = controlLinkedMenus.concat(referencedControlValues(control));
      });
      var menuItems = [];
      all('[role="combobox"], [role="menu"], [role="listbox"], [role="tablist"], [role="tree"], [aria-haspopup="true"]').forEach(function (control) {
        menuItems = menuItems.concat(collectDeepMenuValues(control));
      });
      menuItems = uniq(menuItems, 240);
      var lists = list('ul, ol, [role="list"], [role="menubar"], [role="tree"]', textOf, 120, false);
      var datalists = list('datalist', function (element) {
        var label = element.id || element.getAttribute("aria-label") || "datalist";
        var options = Array.prototype.slice.call(element.querySelectorAll("option")).map(function (option) { return clean(option.label || option.value || option.text); }).filter(Boolean).slice(0, 120).join(" / ");
        return clean(label + ": " + options);
      }, 40, false);
      var datalistOptions = [];
      all('datalist').forEach(function (datalist) {
        datalistOptions.push.apply(datalistOptions, collectOptionText(datalist, "option"));
      });
      function firstText(selector) {
        var values = list(selector, textOf, 1, false);
        return values.length ? values[0] : "";
      }
      function closestText(element, selector) {
        try {
          var found = element.closest(selector);
          return found ? textOf(found) : "";
        } catch (_) {
          return "";
        }
      }
      function labelForInput(input) {
        var labels = [];
        if (input.labels && input.labels.length) {
          labels.push(textOf(input.labels[0]));
        }
        if (input.id) {
          try {
            Array.prototype.slice.call(document.querySelectorAll('label[for="' + input.id + '"]')).forEach(function (label) {
              labels.push(textOf(label));
            });
          } catch (_) {}
        }
        labels.push(closestText(input, "label"));
        labels.push(closestText(input, ".answer, .r0, .r1, li, p, div"));
        labels.push(input.getAttribute && (input.getAttribute("aria-label") || input.getAttribute("title") || input.getAttribute("placeholder")));
        labels.push(input.value);
        return clean(labels.filter(Boolean).join(" | "));
      }
      function taskType(container) {
        if (container.querySelector('input[type="checkbox"]')) return "multiple_choice";
        if (container.querySelector('input[type="radio"]')) return "single_choice";
        if (container.querySelector("select")) return "select";
        if (container.querySelector('textarea, input[type="text"], input[type="number"], input:not([type]), [contenteditable="true"]')) return "short_answer";
        return "question";
      }
      function optionsForTask(container) {
        var found = [];
        Array.prototype.slice.call(container.querySelectorAll('input[type="radio"], input[type="checkbox"]')).forEach(function (input) {
          found.push({
            text: labelForInput(input),
            value: clean(input.value),
            selected: input.checked === true,
            control: clean(input.type || "")
          });
        });
        Array.prototype.slice.call(container.querySelectorAll("select")).forEach(function (select) {
          var selectLabel = clean([select.name, select.id, select.getAttribute("aria-label")].filter(Boolean).join(" "));
          Array.prototype.slice.call(select.options || []).forEach(function (option) {
            found.push({
              text: clean((selectLabel ? selectLabel + ": " : "") + textOf(option)),
              value: clean(option.value),
              selected: option.selected === true,
              control: "select"
            });
          });
        });
        Array.prototype.slice.call(container.querySelectorAll('textarea, input[type="text"], input[type="number"], input:not([type]), [contenteditable="true"]')).forEach(function (input) {
          if (input.type && String(input.type).toLowerCase() === "password") return;
          found.push({
            text: clean([input.name, input.id, input.getAttribute && (input.getAttribute("aria-label") || input.getAttribute("placeholder")), input.value || input.textContent].filter(Boolean).join(" | ")),
            value: clean(input.value || input.textContent || ""),
            selected: !!clean(input.value || input.textContent || ""),
            control: input.tagName ? input.tagName.toLowerCase() : "text"
          });
        });
        return uniq(found.map(function (option) {
          return JSON.stringify(option);
        }), 80).map(function (raw) {
          try { return JSON.parse(raw); } catch (_) { return null; }
        }).filter(Boolean);
      }
      function feedbackForTask(container) {
        return uniq(Array.prototype.slice.call(container.querySelectorAll(".feedback, .outcome, .validationerror, .error, .incorrect, .correct, .specificfeedback, .generalfeedback")).map(textOf), 10).join(" / ");
      }
      function controlsForTask(container) {
        return uniq(Array.prototype.slice.call(container.querySelectorAll('button, input[type="submit"], input[type="button"], a.btn, .submitbtns a')).map(textOf), 20);
      }
      function questionTextForTask(container) {
        var specific = [];
        Array.prototype.slice.call(container.querySelectorAll(".qtext, .question-text, [data-region='question-text'], .formulation")).forEach(function (node) {
          specific.push(textOf(node));
        });
        return clean((specific.filter(Boolean)[0] || textOf(container)).slice(0, 1800));
      }
      function parseQuestionTasks() {
        var containers = [];
        all('.que, [id^="question-"]').forEach(function (element) {
          if (!containers.some(function (existing) { return existing === element || existing.contains(element); })) {
            containers.push(element);
          }
        });
        if (!containers.length) {
          all(".qtext, .formulation, [data-region='question']").forEach(function (element) {
            var parent = element.closest && element.closest(".que, [id^='question-']");
            containers.push(parent || element);
          });
        }
        return uniq(containers.map(function (container, index) {
          var id = clean(container.id || container.getAttribute("data-qid") || container.getAttribute("data-region") || "question-" + (index + 1));
          return JSON.stringify({
            id: id,
            type: taskType(container),
            questionText: questionTextForTask(container),
            options: optionsForTask(container),
            feedback: feedbackForTask(container),
            controls: controlsForTask(container)
          });
        }), 80).map(function (raw) {
          try { return JSON.parse(raw); } catch (_) { return null; }
        }).filter(function (task) {
          return task && (task.questionText || (task.options && task.options.length));
        });
      }
      function parseAssignmentTasks() {
        var blocks = all("#region-main .activity-description, #intro, #region-main .submissionstatustable, #region-main .assignsubmission, #region-main .activity-information");
        return uniq(blocks.map(function (block, index) {
          return JSON.stringify({
            id: clean(block.id || "assignment-" + (index + 1)),
            type: "assignment",
            questionText: textOf(block).slice(0, 1800),
            options: [],
            feedback: feedbackForTask(block),
            controls: controlsForTask(block)
          });
        }), 20).map(function (raw) {
          try { return JSON.parse(raw); } catch (_) { return null; }
        }).filter(function (task) {
          return task && task.questionText && task.questionText.length > 20;
        });
      }
      var generator = "";
      try {
        var generatorMeta = document.querySelector('meta[name="generator"]');
        generator = generatorMeta ? clean(generatorMeta.getAttribute("content")) : "";
      } catch (_) {}
      var moodleCourse = firstText(".page-header-headings h1, header h1, .breadcrumb li:nth-last-child(2), .navbar .breadcrumb li:nth-last-child(2)");
      var moodleActivity = firstText("#page-header h1, .activity-header h1, #region-main h1, .breadcrumb li:last-child");
      var moodleTasks = parseQuestionTasks();
      if (!moodleTasks.length) {
        moodleTasks = parseAssignmentTasks();
      }
      var moodleQuestions = list('.que, [id^="question-"], .qtext, .formulation, .answer, [data-region="question"], .quiz-question, .question-text', textOf, 80, false);
      var moodleActivities = list('#region-main .activity-description, #region-main .activity-information, #region-main .submissionstatustable, #region-main .feedback, #region-main .assignsubmission, #region-main .contentwithoutlink, #region-main .activityinstance', textOf, 80, false);
      return JSON.stringify({
        url: location.href,
        title: document.title,
        moodleCourse: moodleCourse,
        moodleActivity: moodleActivity,
        generator: generator,
        bodyID: document.body ? clean(document.body.id) : "",
        bodyClasses: document.body ? clean(document.body.className) : "",
        htmlClasses: document.documentElement ? clean(document.documentElement.className) : "",
        moodleConfig: !!(window.M && window.M.cfg),
        text: clean(document.body ? document.body.innerText : "").slice(0, 6000),
        fullText: clean(document.body ? document.body.textContent : "").slice(0, 6000),
        moodleTasks: moodleTasks,
        moodleQuestions: moodleQuestions,
        moodleActivities: moodleActivities,
        inputs: inputs,
        buttons: buttons,
        links: links,
        selects: selects,
        menuControls: menuControls,
        ariaMenuItems: ariaMenuItems,
        controls: controls,
        menuItems: menuItems,
        lists: lists,
        datalists: datalists,
        datalistOptions: uniq(datalistOptions, 120),
        controlLinkedMenus: uniq(controlLinkedMenus, 120),
        options: options
      });
    })()
    """#
}
