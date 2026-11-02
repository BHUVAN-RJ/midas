import XCTest

/// Apple privacy manifest (founder, 2026-10-31): every required-reason API category a target's
/// Swift source uses must be declared, with a reason, in that target's PrivacyInfo.xcprivacy.
/// Targets: the Midas app (Midas/ and Shared/, manifest Midas/PrivacyInfo.xcprivacy) and the
/// widget extension (MidasWidgets/, Shared/ and the Midas/ files project.yml compiles into it,
/// manifest MidasWidgets/PrivacyInfo.xcprivacy; no file there means nothing is declared).
/// Category names and symbols follow Apple's "Describing use of required reason API".
final class RequiredReasonAPIScanTests: XCTestCase {
    private struct APICategory: Sendable {
        let name: String
        /// Regular expressions; any match in a source file means the category is used.
        let symbolPatterns: [String]
    }

    private static let categories = [
        APICategory(name: "NSPrivacyAccessedAPICategoryUserDefaults", symbolPatterns: [
            #"\bUserDefaults\b"#, #"\bNSUserDefaults\b"#, #"@AppStorage\b"#,
        ]),
        APICategory(name: "NSPrivacyAccessedAPICategoryFileTimestamp", symbolPatterns: [
            #"\bcreationDateKey\b"#, #"\bcontentModificationDateKey\b"#, #"\battributeModificationDateKey\b"#,
            #"\bcontentAccessDateKey\b"#, #"FileAttributeKey\.(creationDate|modificationDate)\b"#,
            #"\bNSFile(CreationDate|ModificationDate)\b"#, #"\battributesOfItem\b"#,
            #"\bgetattrlist\b"#, #"\b(f|l)?stat(at)?\("#,
        ]),
        APICategory(name: "NSPrivacyAccessedAPICategorySystemBootTime", symbolPatterns: [
            #"\bsystemUptime\b"#, #"\bmach_absolute_time\b"#, #"kern\.boottime"#,
        ]),
        APICategory(name: "NSPrivacyAccessedAPICategoryDiskSpace", symbolPatterns: [
            #"\bvolumeAvailableCapacity"#, #"\bvolumeTotalCapacity"#, #"\bsystemFreeSize\b"#,
            #"\bsystemSize\b"#, #"\bstatv?fs\b"#, #"\battributesOfFileSystem\b"#,
        ]),
        APICategory(name: "NSPrivacyAccessedAPICategoryActiveKeyboards", symbolPatterns: [
            #"\bactiveInputModes\b"#,
        ]),
    ]

    private var shellDirectory: URL {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testsDirectory.deletingLastPathComponent()
    }

    // MARK: - The two targets

    func testAppDeclaresEveryRequiredReasonCategoryItUses() throws {
        let appSources = try swiftFiles(inFolders: ["Midas", "Shared"])
        let manifestURL = shellDirectory.appending(path: "Midas/PrivacyInfo.xcprivacy")
        try assertSourcesCovered(appSources, byManifestAt: manifestURL, targetName: "Midas")
    }

    func testWidgetDeclaresEveryRequiredReasonCategoryItUses() throws {
        let folderSources = try swiftFiles(inFolders: ["MidasWidgets", "Shared"])
        let sharedAppSources = try widgetSourcesFromAppFolder()
        let manifestURL = shellDirectory.appending(path: "MidasWidgets/PrivacyInfo.xcprivacy")
        try assertSourcesCovered(folderSources + sharedAppSources, byManifestAt: manifestURL, targetName: "MidasWidgets")
    }

    // MARK: - The detector itself

    /// Without this, a broken pattern would make both target checks pass on any source.
    func testDetectorFindsEachCategoryInSampleCode() {
        let samples = [
            "NSPrivacyAccessedAPICategoryUserDefaults": "init(defaults: UserDefaults = .standard)",
            "NSPrivacyAccessedAPICategoryFileTimestamp": "let values = try url.resourceValues(forKeys: [.contentModificationDateKey])",
            "NSPrivacyAccessedAPICategorySystemBootTime": "let uptime = ProcessInfo.processInfo.systemUptime",
            "NSPrivacyAccessedAPICategoryDiskSpace": "let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]",
            "NSPrivacyAccessedAPICategoryActiveKeyboards": "let modes = UITextInputMode.activeInputModes",
        ]
        for (categoryName, sampleCode) in samples {
            XCTAssertEqual(categoriesUsed(in: sampleCode), [categoryName], "sample: \(sampleCode)")
        }
        // EKReminder.creationDate is a Reminders field, not a file timestamp.
        XCTAssertEqual(categoriesUsed(in: "creationDate: isoText(reminder.creationDate, formatter: formatter)"), [])
    }

    // MARK: - Helpers

    private func assertSourcesCovered(_ sourceFiles: [URL], byManifestAt manifestURL: URL, targetName: String) throws {
        XCTAssertGreaterThan(sourceFiles.count, 0, "no Swift sources found for \(targetName)")
        let declaredCategories = try declaredCategoriesWithReasons(manifestURL: manifestURL)
        for sourceFile in sourceFiles {
            let sourceText = try String(contentsOf: sourceFile, encoding: .utf8)
            let usedCategories = categoriesUsed(in: sourceText)
            let undeclaredCategories = usedCategories.subtracting(declaredCategories)
            XCTAssertTrue(
                undeclaredCategories.isEmpty,
                "\(targetName): \(sourceFile.lastPathComponent) uses \(undeclaredCategories.sorted()) not declared with a reason in \(manifestURL.path)"
            )
        }
    }

    /// Categories in the manifest's NSPrivacyAccessedAPITypes that list at least one reason.
    /// A missing manifest declares nothing.
    private func declaredCategoriesWithReasons(manifestURL: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return []
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let propertyList = try PropertyListSerialization.propertyList(from: manifestData, format: nil)
        let manifest = try XCTUnwrap(propertyList as? [String: Any], "\(manifestURL.path) is not a dictionary")
        let accessedTypes = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        var declared = Set<String>()
        for entry in accessedTypes {
            let category = entry["NSPrivacyAccessedAPIType"] as? String
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            if let category, !reasons.isEmpty {
                declared.insert(category)
            }
        }
        return declared
    }

    private func categoriesUsed(in sourceText: String) -> Set<String> {
        var used = Set<String>()
        let fullRange = NSRange(sourceText.startIndex..., in: sourceText)
        for category in Self.categories {
            for pattern in category.symbolPatterns {
                let expression = try! NSRegularExpression(pattern: pattern)
                if expression.firstMatch(in: sourceText, range: fullRange) != nil {
                    used.insert(category.name)
                }
            }
        }
        return used
    }

    /// Every .swift file under the given shell/ folders, subfolders included.
    private func swiftFiles(inFolders folderNames: [String]) throws -> [URL] {
        var found: [URL] = []
        for folderName in folderNames {
            let folderURL = shellDirectory.appending(path: folderName)
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: nil), "cannot read \(folderURL.path)")
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                found.append(fileURL)
            }
        }
        return found
    }

    /// The Midas/*.swift files listed under the MidasWidgets target in project.yml.
    private func widgetSourcesFromAppFolder() throws -> [URL] {
        let projectText = try String(contentsOf: shellDirectory.appending(path: "project.yml"), encoding: .utf8)
        let widgetBlockStart = try XCTUnwrap(projectText.range(of: "\n  MidasWidgets:\n"), "MidasWidgets target not found in project.yml")
        let afterWidgetBlock = projectText[widgetBlockStart.upperBound...]
        // The next target at the same indent ends the widget block.
        let nextTarget = afterWidgetBlock.range(of: #"\n  [A-Za-z]+:\n"#, options: .regularExpression)
        let widgetBlock = afterWidgetBlock[..<(nextTarget?.lowerBound ?? afterWidgetBlock.endIndex)]
        let listedFile = try NSRegularExpression(pattern: #"- (Midas/[^\s]+\.swift)"#)
        let blockText = String(widgetBlock)
        let matches = listedFile.matches(in: blockText, range: NSRange(blockText.startIndex..., in: blockText))
        var files: [URL] = []
        for match in matches {
            if let pathRange = Range(match.range(at: 1), in: blockText) {
                files.append(shellDirectory.appending(path: String(blockText[pathRange])))
            }
        }
        XCTAssertGreaterThan(files.count, 0, "no Midas/*.swift files listed for MidasWidgets in project.yml")
        return files
    }
}
