---
name: ios-feature-module
description: >-
  Use when: creating a new iOS SwiftUI feature, screen, module, tab, navigation destination, @Observable view model, async/await use case, repository protocol/implementation, URLSession endpoint, parser, entity, FactoryKit DI registration, or Xcode platform filter.
---

# iOS Feature And Module Creation

Use this skill whenever adding a new feature, screen, data flow, module, tab, or navigation destination to this layered iOS architecture.

## Load First

Before editing, load these skills when relevant:

- `swift-style` for Swift formatting and naming.
- `swiftui-patterns` for `@Observable`, SwiftUI view composition, `NavigationStack`, `.task`, and `.refreshable`.
- `swift-concurrency` for async/await, `@MainActor`, cancellation, Sendable boundaries, and structured concurrency.
- `localization` for String Catalog or `LocalizedStringKey` work.
- `ios-hig` for new user-facing interaction patterns.
- `swift-testing` if adding tests.

## Dependency Rule

Use Apple frameworks and project-local code by default. The only third-party framework assumed by this architecture is `FactoryKit`.

Do not add third-party networking, parsing, image loading, persistence, reactive, or state-management frameworks unless the user explicitly asks for them. New data flows should use `async/await` and `URLSession`.

## First Pass: Classify The Feature

Decide the smallest shape that satisfies the request:

- **Presentation-only component**: add under `iOS/Presentations/Components` and reuse existing view models/state.
- **New iOS screen using existing data**: add `FeatureView` under `iOS/Presentations` and maybe a `FeatureViewModel` under `Shared/ViewModels`.
- **New navigable destination**: add the screen, then update `Destinations` and `Destinations+View`.
- **New root tab**: add the screen, then update `Tabs` and `Tabs+Views`.
- **New data flow**: add entity, endpoint, parser/DTO, repository protocol, repository implementation, use case, DI registration, view model, and view.
- **Platform-specific feature**: keep UIKit/iOS APIs under `iOS`; keep reusable logic under `Shared`.

## Discovery Checklist

Before writing files, inspect nearby examples:

- Similar view in `iOS/Presentations`.
- Similar view model in `Shared/ViewModels`.
- Similar use case folder in `Shared/Domain/UseCases`.
- Matching repository protocol in `Shared/Domain/Repositories`.
- Matching repository implementation in `Shared/Data/Repositories`.
- Matching endpoint/service in `Shared/Data/Network`.
- Matching parser or DTO in `Shared/Data/Parsing`.
- Current `iOS/Core/Container.swift` grouping.
- Current platform filters in the Xcode project if new files are platform-specific.

When applying this skill inside an existing repository, map these generic paths to the project’s real root folder instead of hard-coding a product name.

## Naming Rules

Use existing names as the source of truth:

- Screen: `FeatureView`.
- View model: `FeatureViewModel`.
- Entity: `FeatureItem`, `FeatureDetails`, or a domain-specific noun.
- Repository protocol: `FeatureRepository`.
- Repository implementation: `FeatureRepositoryImpl`.
- Network endpoint/service: `FeatureEndpoint` or `FeatureService`, matching the project convention.
- Parser: `FeatureParser`.
- Use case: verb phrase ending with `UseCase`, for example `GetFeatureUseCase`, `LoadFeaturePageUseCase`, `CreateFeatureUseCase`.
- DI property: lower camel case, for example `getFeatureUseCase`, `featureRepository`.
- Localization keys: `key.feature`, `key.feature.empty`, `key.feature.error`, or an existing domain prefix.
- Analytics name: snake case, for example `feature`, `feature_details`.
- Analytics class: Swift type name, for example `FeatureView`.

## New Data Flow Workflow

Follow this order so compiler errors guide integration cleanly:

1. Add entities in `Shared/Domain/Entities`.
   - Use `struct` by default.
   - Conform to `Hashable`; add `Identifiable` when used in `ForEach` or navigation identity.
   - Add `Sendable` when values cross concurrency boundaries and their stored properties support it.
   - Keep parsing helpers out of entities.

2. Add the repository protocol in `Shared/Domain/Repositories`.
   - Use `async throws` return values.
   - Keep protocol methods domain-oriented, not HTTP-oriented.
   - Mark protocols `Sendable` when implementations can safely cross concurrency boundaries.

3. Add use cases in `Shared/Domain/UseCases/<DomainArea>`.
   - Use `struct`.
   - Store the repository protocol in a private property.
   - Expose `callAsFunction(...) async throws`.
   - Do not add UI state to use cases.

4. Add endpoint or service in `Shared/Data/Network`.
   - Use an enum or struct that builds `URLRequest`.
   - Keep base URL, path, method, headers, query items, and body creation together.
   - Throw an explicit error for invalid URLs or invalid request construction.

5. Add parser or DTO mapping in `Shared/Data/Parsing`.
   - Prefer `Decodable` DTOs for structured data.
   - Keep parser functions `static` when manual mapping is needed.
   - Throw parsing errors instead of swallowing missing required fields.
   - Do not add a third-party parsing framework unless explicitly requested.

6. Add repository implementation in `Shared/Data/Repositories`.
   - Inject `URLSession` or a project-local network client with `@Injected`.
   - Use `try await urlSession.data(for: request)` or the project-local async network client.
   - Validate HTTP response status in one reusable helper.
   - Decode or parse data, then return domain entities.

7. Register dependencies in `iOS/Core/Container.swift`.
   - Add infrastructure factories such as `urlSession` if missing.
   - Add repository factory in the repository extension.
   - Add use case factories in a domain-grouped extension.
   - Use `.singleton` for infrastructure and repositories unless a dependency must be transient.
   - If another platform has its own `Container.swift`, mirror the registration there only when that platform uses the feature.

8. Add view model in `Shared/ViewModels`.
   - Use `@MainActor @Observable class` for UI-owned state.
   - Inject dependencies with `@ObservationIgnored @LazyInjected(\.useCaseName) private var useCaseName`.
   - Use `private(set)` for read-only state exposed to views.
   - Use `DataState` and `DataPaginationState` for loading, error, and pagination state if the project has those primitives.
   - Handle `CancellationError` separately and avoid showing it as a user-facing failure.
   - Keep long-lived replacement tasks in `@ObservationIgnored` properties and cancel them before starting a replacement.

9. Add SwiftUI view in `iOS/Presentations`.
   - Own the view model with `@State private var viewModel = FeatureViewModel()` unless the initializer needs route input.
   - Use existing components such as loading, error, empty, and pagination state views.
   - Use `NavigationLink(value: Destinations.someCase(...))` for push navigation.
   - Use `.task { await viewModel.load() }` for initial async loading.
   - Use `.refreshable { await viewModel.load() }` for refresh.
   - Avoid direct networking or parsing in views.

10. Wire navigation or tabs if needed.
    - Destination: add a case to `Destinations`, update `name`, `className`, and `Destinations+View` when those computed properties exist.
    - Tab: add a case to `Tabs`, update `CaseIterable`, `label`, `image`, `role`, `name`, `className`, and `Tabs+Views`.
    - Give destination views stable `.id(...)` values.
    - Add screen analytics consistently only when the project already uses analytics.

11. Add localization and resources.
    - Add user-visible strings to the String Catalog or existing localization files.
    - Add assets under the correct platform resource folder.

12. Update Xcode project platform filters when required.
    - If the app folder is a synchronized root group, new files may be discovered automatically.
    - Platform-specific compilation is still controlled by `platformFiltersByRelativePath` when the project uses synchronized group filters.
    - Add iOS-only files with `(ios, )`.
    - Add shared iOS/tvOS files with `(ios, tvos, )` only when they compile on both platforms.
    - Do not let UIKit or iOS-only SwiftUI APIs compile for macOS/tvOS.

13. Validate.
    - Run the smallest relevant build, usually the iOS scheme/destination.
    - Check VS Code Problems for compiler errors.
    - If platform filters were touched, validate the affected non-iOS targets too.

## Presentation Pattern

Use the current screen skeleton unless a nearby screen suggests a better match:

```swift
import SwiftUI

struct FeatureView: View {
    @State private var viewModel = FeatureViewModel()

    var body: some View {
        ScrollView(.vertical) {
            // Content
        }
        .scrollIndicators(.visible, axes: .vertical)
        .overlay {
            if let error = viewModel.state.error {
                ErrorStateView(error) {
                    Task { await viewModel.load() }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)
            } else if viewModel.state == .loading {
                LoadingStateView()
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
            }
        }
        .transition(.opacity)
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

For paginated lists, trigger loading from visibility and let the view model guard duplicate calls:

```swift
.onScrollTargetVisibilityChange(idType: FeatureItem.ID.self) { onScreenItems in
    if let items = viewModel.state.data,
       let last = items.last,
       onScreenItems.contains(where: { $0 == last.id })
    {
        Task { await viewModel.loadMore() }
    }
}
```

## View Model Patterns

Initial loading:

```swift
@MainActor
@Observable
class FeatureViewModel {
    @ObservationIgnored @LazyInjected(\.getFeatureUseCase) private var getFeatureUseCase

    private(set) var state: DataState<[FeatureItem]> = .loading

    func load() async {
        state = .loading

        do {
            let items = try await getFeatureUseCase()

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

Pagination:

```swift
func loadMore() async {
    guard paginationState == .idle else { return }

    withAnimation(.easeInOut) {
        paginationState = .loading
    }

    do {
        let items = try await getFeatureUseCase(page: page)
        page += 1

        withAnimation(.easeInOut) {
            state.append(items)
            paginationState = .idle
        }
    } catch is CancellationError {
        paginationState = .idle
    } catch {
        withAnimation(.easeInOut) {
            paginationState = .error(error)
        }
    }
}
```

Debounced search with cancellation:

```swift
@ObservationIgnored private var searchTask: Task<Void, Never>?

func search(query: String) {
    searchTask?.cancel()

    searchTask = Task { [weak self] in
        do {
            try await Task.sleep(for: .milliseconds(500))
            await self?.load(query: query)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }
}
```

## Repository Pattern

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

## Navigation Patch Checklist

When adding `FeatureView` as a destination:

```swift
enum Destinations: Hashable, Identifiable {
    case feature(FeatureItem)
}
```

Update `name` when present:

```swift
case .feature:
    "feature"
```

Update `className` when present:

```swift
case .feature:
    "FeatureView"
```

Update `Destinations+View`:

```swift
case let .feature(item):
    FeatureView(item: item)
        .id(item.id)
```

## Common Mistakes To Avoid

- Adding a view model under `iOS/` when it has no platform-specific code.
- Calling `URLSession` from a view model or view.
- Returning concrete repository implementations from use cases.
- Forgetting `@ObservationIgnored` on injected dependencies and long-lived task handles.
- Showing `CancellationError` as a real user-facing error.
- Mutating UI-owned observed state outside the main actor.
- Adding any third-party framework other than FactoryKit without explicit approval.
- Adding an iOS-only file without a platform filter in a synchronized Xcode project.
- Adding a destination case without updating `name`, `className`, and `Destinations+View` when those exist.
- Adding user-visible text directly in views instead of localization keys.
