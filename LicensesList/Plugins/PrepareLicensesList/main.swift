import Foundation
import PackagePlugin

@main
struct PrepareLicensesList: BuildToolPlugin {
    struct SourcePackagesNotFoundError: Error & CustomStringConvertible {
        let description: String = "SourcePackages not found"
    }

    private let fileManager = FileManager.default

    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isSourcePackagesDirectory(_ url: URL) -> Bool {
        directoryExists(at: url)
            && fileManager.fileExists(atPath: url.appending(path: "workspace-state.json").path())
            && directoryExists(at: url.appending(path: "checkouts"))
    }

    func ancestorDirectories(of url: URL) -> [URL] {
        var directories: [URL] = []
        var currentURL = url.standardizedFileURL

        while currentURL.pathComponents.count > 1 {
            directories.append(currentURL)
            currentURL.deleteLastPathComponent()
        }

        directories.append(currentURL)

        return directories
    }

    func sourcePackagesNearPluginWorkDirectory(_ pluginWorkDirectory: URL) -> URL? {
        for directoryURL in ancestorDirectories(of: pluginWorkDirectory) {
            let directCandidate = directoryURL.appending(path: "SourcePackages")
            if isSourcePackagesDirectory(directCandidate) {
                return directCandidate
            }

            let siblingCandidate = directoryURL.deletingLastPathComponent().appending(path: "SourcePackages")
            if isSourcePackagesDirectory(siblingCandidate) {
                return siblingCandidate
            }
        }

        return nil
    }

    func xcodeContainerNames(near packageDirectory: URL) -> [String] {
        let repositoryURL = packageDirectory.deletingLastPathComponent()
        let contents = (try? fileManager.contentsOfDirectory(
            at: repositoryURL,
            includingPropertiesForKeys: nil,
        )) ?? []

        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
            .map { $0.replacingOccurrences(of: ".xcodeproj", with: "") }
            .map { $0.replacingOccurrences(of: ".xcworkspace", with: "") }
    }

    func sourcePackagesInDerivedData(near packageDirectory: URL) -> URL? {
        let derivedDataURL = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Developer")
            .appending(path: "Xcode")
            .appending(path: "DerivedData")

        guard directoryExists(at: derivedDataURL) else {
            return nil
        }

        let xcodeContainerNames = xcodeContainerNames(near: packageDirectory)
        let contents = (try? fileManager.contentsOfDirectory(
            at: derivedDataURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        )) ?? []

        let candidates = contents
            .filter { directoryExists(at: $0) }
            .filter { derivedDataDirectoryURL in
                guard !xcodeContainerNames.isEmpty else {
                    return true
                }

                return xcodeContainerNames.contains { name in
                    derivedDataDirectoryURL.lastPathComponent.hasPrefix("\(name)-")
                }
            }
            .map { $0.appending(path: "SourcePackages") }
            .filter(isSourcePackagesDirectory)

        return candidates.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    func sourcePackages(_ pluginWorkDirectory: URL, packageDirectory: URL) throws -> URL {
        if let sourcePackagesURL = sourcePackagesNearPluginWorkDirectory(pluginWorkDirectory) {
            return sourcePackagesURL
        }

        if let sourcePackagesURL = sourcePackagesInDerivedData(near: packageDirectory) {
            return sourcePackagesURL
        }

        throw SourcePackagesNotFoundError()
    }

    func makeBuildCommand(executableURL: URL, sourcePackagesURL: URL, outputURL: URL) -> Command {
        .buildCommand(
            displayName: "Prepare LicensesList",
            executable: executableURL,
            arguments: [
                outputURL.absoluteURL.path(),
                sourcePackagesURL.absoluteURL.path(),
            ],
            outputFiles: [
                outputURL,
            ],
        )
    }

    func createBuildCommands(context: PluginContext, target _: Target) async throws -> [Command] {
        try [
            makeBuildCommand(
                executableURL: context.tool(named: "SourcePackagesParser").url,
                sourcePackagesURL: sourcePackages(
                    context.pluginWorkDirectoryURL,
                    packageDirectory: context.package.directoryURL,
                ),
                outputURL: context.pluginWorkDirectoryURL.appending(path: "LicensesList.swift"),
            ),
        ]
    }
}
