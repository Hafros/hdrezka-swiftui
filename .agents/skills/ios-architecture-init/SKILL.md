---
name: ios-architecture-init
description: >-
  Use when: initializing or migrating an iOS SwiftUI project to a layered architecture with Shared Domain/Data/ViewModels, async/await repositories and use cases, FactoryKit dependency injection, URLSession networking, app shell, tabs, navigation destinations, localization, resources, and Xcode platform filters.
---

# iOS Architecture Initialization

Use this skill to initialize a new iOS SwiftUI project, or to migrate an existing project toward this architecture, without coupling the implementation to any product name or unnecessary third-party framework.

## Load First

Before implementing, load these skills when available:

- `swift-style` for formatting and naming conventions.
- `swiftui-patterns` for `@Observable`, `@State`, `NavigationStack`, `.task`, `.refreshable`, and state placement.
- `swift-concurrency` for async/await, `@MainActor`, cancellation, Sendable boundaries, and structured concurrency.
- `localization` when adding user-visible strings.
- `ios-hig` when adding new user-facing UI surfaces.

## Dependency Rule

Use Apple frameworks and project-local code by default. The only third-party framework assumed by this architecture is `FactoryKit` for dependency injection.

Do not introduce networking, persistence, image loading, parsing, reactive, or state-management dependencies unless the user explicitly asks for them. Prefer:

- `SwiftUI` and Observation for presentation and state observation.
- Swift Concurrency for async work.
- `URLSession` for networking.
- `JSONDecoder`, `PropertyListDecoder`, or project-local parsers for response mapping.
- `FactoryKit` for dependency registration and injection.

## Target Shape

Create a layered project with this ownership model:

```text
App/
  iOS/
    App.swift
    Core/
      AppState.swift
      Const.swift
      Container.swift
    Preferences.swift
      Destinations.swift
      Destinations+View.swift
      Tabs.swift
      Tabs+Views.swift
    Presentations/
      FeatureView.swift
      Components/
    Resources/
      Assets.xcassets/
      Info.plist
    Utils/
  Shared/
    Core/
    Data/
      Network/
      Parsing/
      Repositories/
    Domain/
      Entities/
      Repositories/
      UseCases/
    Resources/
    Utils/
    ViewModels/
```

Keep platform-specific UI, app lifecycle, resources, and platform services under `iOS/`. Keep reusable business logic, entities, repositories, networking, parsing, and view models under `Shared/` unless a dependency is truly platform-specific.

## Initialization Workflow

1. Inspect the destination project before writing files:
   - Current Xcode project format and whether synchronized groups are used.
   - Existing app entry point, resources, and minimum OS versions.
   - Existing Swift language mode and strict concurrency settings.
   - Whether macOS/tvOS targets exist and share files with iOS.

2. Create the folder structure:
   - `iOS/Core`, `iOS/Presentations`, `iOS/Presentations/Components`, `iOS/Resources`, `iOS/Utils`.
   - `Shared/Core`, `Shared/Data/Network`, `Shared/Data/Parsing`, `Shared/Data/Repositories`.
   - `Shared/Domain/Entities`, `Shared/Domain/Repositories`, `Shared/Domain/UseCases`.
   - `Shared/ViewModels`, `Shared/Utils`.

3. Add shared state primitives:
   - `DataState<T: Hashable>` with `.data`, `.loading`, and NSError-backed error state.
   - `DataPaginationState` with `.idle`, `.loading`, and NSError-backed error state.
   - Keep state types value-based and UI-framework agnostic.

4. Add `Core/Container.swift` as FactoryKit extensions grouped by responsibility:
   - Infrastructure factories first, for example `urlSession` and `jsonDecoder`.
   - Repository factories next, for example `featureRepository`.
   - Use case factories grouped by domain area.
   - Use `.singleton` for infrastructure and repositories unless a dependency must be transient.

5. Add networking boundaries:
   - `Shared/Data/Network/<Feature>Endpoint.swift` or `<Feature>Service.swift` for URL construction.
   - Put base URL, path, method, headers, query items, and body creation at the network boundary.
   - Use `URLSession` async APIs.
   - Keep response mapping in `Shared/Data/Parsing/<Feature>Parser.swift` or in `Decodable` DTOs when the response is structured.
   - Keep network calls inside `Shared/Data/Repositories/<Feature>RepositoryImpl.swift`.

6. Add domain boundaries:
   - Entities in `Shared/Domain/Entities` as small, `Hashable`/`Sendable` value types when possible.
   - Repository protocols in `Shared/Domain/Repositories`.
   - Use cases in `Shared/Domain/UseCases/<DomainArea>` as structs with `callAsFunction` async methods.

7. Add view models:
   - `@MainActor @Observable class FeatureViewModel` in `Shared/ViewModels`.
   - Inject use cases with `@ObservationIgnored @LazyInjected(\.useCaseName) private var useCaseName`.
   - Expose mutable UI state as `private(set)` where views should only read.
   - Store any long-lived task handles under `@ObservationIgnored` and cancel them when starting a replacement operation.
   - Use `withAnimation(.easeInOut)` for visible state transitions that should animate.

8. Add the iOS app shell:
   - `App.swift` with project environment values injected using `.environment(...)`.
   - `ContentView` as the main container.
   - `Tabs` enum for root tabs: label, SF Symbol name, role, analytics name, class name, and `Identifiable` conformance when analytics is used.
   - `Tabs+Views.swift` with `NavigationStack` per tab and `.destinations()` attached.
   - `Destinations` enum for push navigation with typed associated values.
   - `Destinations+View.swift` with `navigationDestination(for:)`, stable `.id(...)`, and analytics screen tracking if the app has analytics.

9. Add localization and resources:
   - Put user-visible strings into String Catalogs or project localization resources.
   - Use stable keys like `key.feature`, `key.feature.empty`, and `key.feature.error` when the project already follows key-based localization.

10. Wire the Xcode project:
    - If using Xcode synchronized groups, new files under the synchronized root are discovered automatically.
    - Still update `platformFiltersByRelativePath` for iOS-only, tvOS-only, or macOS-only files so other platform targets do not compile them accidentally.
    - Keep shared files unfiltered only when they compile cleanly for every target that includes `Shared`.

11. Validate:
    - Run the smallest relevant iOS build.
    - If platform filters changed, also run the relevant macOS/tvOS build if those targets exist.
    - Check Problems for Swift compiler errors after edits.

## File Templates

Use case:

```swift
struct LoadFeatureUseCase {
    private let repository: FeatureRepository

    init(repository: FeatureRepository) {
        self.repository = repository
    }

    func callAsFunction(page: Int) async throws -> [FeatureItem] {
        try await repository.loadFeature(page: page)
    }
}
```

Repository protocol:

```swift
protocol FeatureRepository: Sendable {
    func loadFeature(page: Int) async throws -> [FeatureItem]
}
```

Repository implementation:

```swift
import FactoryKit
import Foundation

struct FeatureRepositoryImpl: FeatureRepository {
    @Injected(\.urlSession) private var urlSession

    func loadFeature(page: Int) async throws -> [FeatureItem] {
        let request = try FeatureEndpoint.load(page: page).makeURLRequest()
        let (data, response) = try await urlSession.data(for: request)

        try ResponseValidator.validate(response)

        return try FeatureParser.parse(data)
    }
}
```

Network endpoint:

```swift
import Foundation

enum FeatureEndpoint {
    case load(page: Int)

    func makeURLRequest() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.example.com"
        components.path = "/feature"

        switch self {
        case let .load(page):
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return request
    }
}
```

View model:

```swift
import FactoryKit
import SwiftUI

@MainActor
@Observable
class FeatureViewModel {
    @ObservationIgnored @LazyInjected(\.loadFeatureUseCase) private var loadFeatureUseCase

    private(set) var state: DataState<[FeatureItem]> = .loading

    func load() async {
        state = .loading

        do {
            let items = try await loadFeatureUseCase(page: 1)

            withAnimation(.easeInOut) {
                state = .data(items)
            }
        } catch is CancellationError {
            return
        } catch {
            withAnimation(.easeInOut) {
                state = .error(error)
            }
        }
    }
}
```

SwiftUI screen:

```swift
import SwiftUI

struct FeatureView: View {
    @State private var viewModel = FeatureViewModel()

    var body: some View {
        ScrollView(.vertical) {
            // Feature content
        }
        .overlay {
            if let error = viewModel.state.error {
                ErrorStateView(error) {
                    Task { await viewModel.load() }
                }
            } else if viewModel.state == .loading {
                LoadingStateView()
            }
        }
        .navigationTitle("key.feature")
        .navigationBarTitleDisplayMode(.large)
        .background(.background)
        .task {
            switch viewModel.state {
            case .data:
                break
            default:
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }
}
```

Container registration:

```swift
import FactoryKit
import Foundation

extension Container {
    var urlSession: Factory<URLSession> {
        self { .shared }.singleton
    }
}

extension Container {
    var featureRepository: Factory<FeatureRepository> {
        self { FeatureRepositoryImpl() }.singleton
    }
}

extension Container {
    var loadFeatureUseCase: Factory<LoadFeatureUseCase> {
        self { LoadFeatureUseCase(repository: self.featureRepository()) }
    }
}
```

## Architecture Rules

- Views do not call repositories or network clients directly.
- View models do not parse network responses directly.
- Use cases depend on repository protocols, not concrete repository implementations.
- Repository implementations are the boundary where `URLSession`, endpoints, and parsers meet.
- Public shared models that cross concurrency boundaries should be value types and `Sendable` when possible.
- UI-owned observable view models should be `@MainActor`.
- Shared view models must avoid UIKit-only APIs.
- iOS-only views and utilities must be platform filtered in the Xcode project when the root group is shared with other Apple targets.
- Prefer adding small files in the existing layer over creating nested feature packages unless the destination project already uses feature packages.
