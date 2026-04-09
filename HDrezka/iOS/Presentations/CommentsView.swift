import Algorithms
import Combine
import Defaults
import Perception
import Pow
import SwiftUI

struct CommentsView: View {
    private let title: String

    @State private var viewModel: CommentsViewModel

    init(details: MovieDetailed) {
        title = details.commentsCount > 0 ? String(localized: "key.comments-\(details.commentsCount)") : String(localized: "key.comments")
        viewModel = CommentsViewModel(id: details.movieId, adb: details.adb, type: details.type)
    }

    @Default(.isLoggedIn) private var isLoggedIn

    @State private var movieDestination: MovieSimple?

    var body: some View {
        WithPerceptionTracking {
            ScrollView(.vertical) {
                if viewModel.state.data?.isEmpty == false, viewModel.reply == nil {
                    CommentTextArea()
                        .padding(.top, 18)
                        .padding(.horizontal, 36)
                }

                LazyVStack(alignment: .leading, spacing: 16) {
                    if let comments = viewModel.state.data, !comments.isEmpty {
                        ForEach(comments) { comment in
                            CommentsViewComponent(comment: comment, movieDestination: $movieDestination)
                                .onAppear {
                                    guard viewModel.paginationState == .idle,
                                          let last = viewModel.state.data?.last,
                                          comment.id == last.id
                                    else {
                                        return
                                    }

                                    viewModel.loadMore()
                                }
                        }
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 36)

                if viewModel.paginationState == .loading {
                    LoadingPaginationStateView()
                }
            }
            .scrollIndicators(.visible, axes: .vertical)
            .viewModifier { view in
                if #available(iOS 26, *) {
                    view.scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    view
                }
            }
            .environment(viewModel)
            .overlay {
                if let error = viewModel.state.error {
                    ErrorStateView(error) {
                        viewModel.load()
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 36)
                } else if let comments = viewModel.state.data, comments.isEmpty {
                    ScrollView(.vertical) {
                        CommentTextArea()
                            .padding(.vertical, 18)
                            .padding(.horizontal, 36)
                    }
                    .scrollIndicators(.visible, axes: .vertical)
                    .viewModifier { view in
                        if #available(iOS 26, *) {
                            view.scrollEdgeEffectStyle(.soft, for: .all)
                        } else {
                            view
                        }
                    }
                    .environment(viewModel)
                } else if viewModel.state == .loading {
                    LoadingStateView()
                        .padding(.vertical, 18)
                        .padding(.horizontal, 36)
                }
            }
            .transition(.opacity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .task(id: isLoggedIn) {
                switch viewModel.state {
                case .data:
                    break
                default:
                    viewModel.load()
                }
            }
            .refreshable {
                if viewModel.state.data?.isEmpty == false {
                    viewModel.load()
                }
            }
            .alert("key.ops", isPresented: $viewModel.isErrorPresented) {
                Button(role: .cancel) {} label: { Text("key.ok") }
            } message: {
                if let message = viewModel.message {
                    Text(message)
                } else if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
            .alert("key.comments.success", isPresented: $viewModel.isOnModerationPresented) {
                Button(role: .cancel) {} label: { Text("key.ok") }
            } message: {
                if let message = viewModel.message {
                    Text(message)
                }
            }
            .sheet(isPresented: $viewModel.isCommentPresented) {
                VStack(alignment: .center, spacing: 25) {
                    if let comment = viewModel.comment {
                        ScrollView(.vertical) {
                            CommentsViewComponent(comment: comment, movieDestination: $movieDestination)
                        }
                        .scrollIndicators(.never)
                        .environment(viewModel)
                    } else {
                        ProgressView()
                    }

                    Button {
                        viewModel.isCommentPresented = false
                    } label: {
                        Text("key.done")
                            .frame(width: 250, height: 30)
                            .contentShape(.rect(cornerRadius: 6))
                            .background(.quinary.opacity(0.5), in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 35)
                .padding(.top, 35)
                .padding(.bottom, 25)
                .frame(width: 650)
                .frame(maxHeight: 520)
            }
            .sheet(item: $viewModel.reportComment) { comment in
                CommentReportSheet(comment: comment)
            }
            .confirmationDialog("key.comment.delete.label", isPresented: Binding {
                viewModel.deleteComment != nil
            } set: {
                if !$0 {
                    viewModel.deleteComment = nil
                }
            }) {
                if let comment = viewModel.deleteComment {
                    Button {
                        viewModel.deleteComment(comment: comment)
                    } label: {
                        Text("key.comment.delete.confirm")
                    }
                }
            } message: {
                Text("key.comment.delete")
            }
            .background(.background)
            .navigationDestination(isPresented: Binding(
                get: { movieDestination != nil },
                set: { isPresented in
                    if !isPresented {
                        movieDestination = nil
                    }
                },
            )) {
                if let movieDestination {
                    DetailsView(movie: movieDestination)
                }
            }
        }
    }

    private struct CommentsViewComponent: View {
        private let comment: Comment

        @Binding private var movieDestination: MovieSimple?

        init(comment: Comment, movieDestination: Binding<MovieSimple?>) {
            self.comment = comment
            _movieDestination = movieDestination
        }

        @State private var delayShow: DispatchWorkItem?

        @Default(.isLoggedIn) private var isLoggedIn

        @Environment(AppState.self) private var appState
        @Environment(CommentsViewModel.self) private var viewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        AsyncImage(url: URL(string: comment.photo), transaction: .init(animation: .easeInOut)) { phase in
                            if let image = phase.image {
                                image.resizable()
                            } else {
                                Color.gray.shimmering()
                            }
                        }
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(.circle)
                        .overlay(.tertiary.opacity(0.2), in: .circle.stroke(lineWidth: 1))

                        Text(comment.author)
                            .font(.body.bold())
                            .textSelection(.enabled)

                        Text(comment.date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    CommentText(comment: comment, movieDestination: $movieDestination)

                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            if isLoggedIn {
                                viewModel.like(comment: comment)
                            } else {
                                appState.isSignInPresented = true
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                if comment.isLiked {
                                    Image(systemName: "hand.thumbsup.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.title2)
                                        .transition(.movingParts.pop(Color.accentColor))
                                } else {
                                    Image(systemName: "hand.thumbsup")
                                        .foregroundColor(.accentColor)
                                        .font(.title2)
                                }

                                if comment.likesCount > 0 {
                                    Text(verbatim: "\(comment.likesCount)")
                                        .font(.system(.body, weight: .semibold).monospacedDigit())
                                }
                            }
                            .frame(height: 28)
                            .padding(.horizontal, 16)
                            .background(.tertiary.opacity(0.05), in: .capsule)
                            .overlay(.tertiary.opacity(0.2), in: .capsule.stroke(lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(comment.selfComment)
                        .onHover { hovering in
                            delayShow?.cancel()

                            if hovering {
                                delayShow = DispatchWorkItem {
                                    viewModel.getLikes(comment: comment)
                                }

                                if let delayShow {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: delayShow)
                                }
                            }
                        }
                        .popover(item: Binding(
                            get: { viewModel.likes[comment.commentId] },
                            set: { viewModel.likes[comment.commentId] = $0 },
                        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) { like in
                            VStack(alignment: .center, spacing: 10) {
                                if !like.likes.isEmpty {
                                    let chunks = like.likes.chunks(ofCount: 8)

                                    ForEach(chunks.indices, id: \.self) { chunkIndex in
                                        let likes = chunks[chunkIndex]

                                        HStack(alignment: .center, spacing: 10) {
                                            ForEach(likes) { like in
                                                VStack(alignment: .center, spacing: 5) {
                                                    AsyncImage(url: URL(string: like.photo), transaction: .init(animation: .easeInOut)) { phase in
                                                        if let image = phase.image {
                                                            image.resizable()
                                                        } else {
                                                            Color.gray.shimmering()
                                                        }
                                                    }
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(.circle)

                                                    Text(like.name)
                                                        .lineLimit(1)
                                                        .font(.body)
                                                }
                                                .frame(width: 60)
                                            }
                                        }
                                    }
                                } else {
                                    ProgressView()
                                }
                            }
                            .padding(15)
                        }

                        Button {
                            withAnimation(.easeInOut) {
                                viewModel.reply = (viewModel.reply == comment.commentId) ? nil : comment.commentId
                            }
                        } label: {
                            Group {
                                if viewModel.reply == comment.commentId {
                                    Image(systemName: "chevron.up")
                                } else {
                                    Text("key.reply")
                                }
                            }
                            .font(.system(.body, weight: .semibold))
                            .frame(height: 28)
                            .padding(.horizontal, 16)
                            .contentShape(.capsule)
                            .background(.tertiary.opacity(0.05), in: .capsule)
                            .overlay(.tertiary.opacity(0.2), in: .capsule.stroke(lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        if !comment.isAdmin {
                            Button {
                                viewModel.reportComment = comment
                            } label: {
                                Image(systemName: "exclamationmark.bubble.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.title2)
                                    .frame(height: 28)
                                    .padding(.horizontal, 16)
                                    .contentShape(.capsule)
                                    .background(.tertiary.opacity(0.05), in: .capsule)
                                    .overlay(.tertiary.opacity(0.2), in: .capsule.stroke(lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        if comment.deleteHash != nil {
                            Button {
                                viewModel.deleteComment = comment
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.accentColor)
                                    .font(.title2)
                                    .frame(height: 28)
                                    .padding(.horizontal, 16)
                                    .contentShape(.capsule)
                                    .background(.tertiary.opacity(0.05), in: .capsule)
                                    .overlay(.tertiary.opacity(0.2), in: .capsule.stroke(lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.reply == comment.commentId {
                        CommentTextArea()
                    }
                }

                if !comment.replies.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(comment.replies) { reply in
                            CommentsViewComponent(comment: reply, movieDestination: $movieDestination)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private struct CommentText: View {
        @State private var comment: Comment

        @Environment(CommentsViewModel.self) private var viewModel

        @Binding private var movieDestination: MovieSimple?

        init(comment: Comment, movieDestination: Binding<MovieSimple?>) {
            self.comment = comment
            _movieDestination = movieDestination
        }

        var body: some View {
            Text(comment.text)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    comment.updateRects(containerWidth: width)
                }
                .overlay {
                    ZStack(alignment: .topLeading) {
                        ForEach(comment.spoilers) { spoiler in
                            ForEach(spoiler.rects.indices, id: \.self) { rectIndex in
                                let rect = spoiler.rects[rectIndex]

//                                        Rectangle()
//                                            .stroke(.red, lineWidth: 1)
//                                            .frame(width: rect.width, height: rect.height)
//                                            .position(x: rect.x + rect.width * 0.5, y: rect.y + rect.height * 0.5)

                                SpoilerView()
                                    .contentShape(.rect)
                                    .background(.background, in: .rect)
                                    .clipShape(.rect)
                                    .onTapGesture {
                                        withAnimation(.easeInOut) {
                                            comment.removeSpoiler(spoiler.id)
                                        }
                                    }
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .environment(\.openURL, OpenURLAction { url in
                    if let fragment = url.fragment(), fragment.contains("comment"), !url.path().isEmpty {
                        let movieId = String(url.path().dropFirst())
                        let commentId = fragment.replacingOccurrences(of: "comment", with: "")

                        viewModel.getComment(movieId: movieId, commentId: commentId)

                        return .handled
                    } else if !url.path().isEmpty, String(url.path().dropFirst()).id != nil {
                        movieDestination = .init(movieId: String(url.path().dropFirst()))

                        return .handled
                    }

                    return .systemAction
                })
        }
    }

    private struct CommentTextArea: View {
        @State private var feedback: String = ""
        @State private var name: String = ""

        @Default(.isLoggedIn) private var isLoggedIn
        @Default(.allowedComments) private var allowedComments

        @Environment(AppState.self) private var appState
        @Environment(CommentsViewModel.self) private var viewModel

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if !isLoggedIn {
                        TextField("key.name", text: $name, prompt: Text(String(localized: "key.name.full").lowercased()))
                            .textFieldStyle(.plain)
                            .font(.body)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .onChange(of: name) { _ in
                                if name.count > 60 {
                                    name = String(name.prefix(60))
                                }
                            }
                    }

                    Spacer(minLength: 0)

                    Button {
                        viewModel.sendComment(name: isLoggedIn ? nil : name, text: feedback)

                        name = ""
                        feedback = ""
                    } label: {
                        Text("key.send")
                            .font(.system(.title3, weight: .bold))
                            .frame(height: 28)
                            .padding(.horizontal, 16)
                            .contentShape(.capsule)
                            .background(.tertiary.opacity(0.05), in: .capsule)
                            .overlay(.tertiary.opacity(0.2), in: .capsule.stroke(lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(feedback.trim().isEmpty || (!isLoggedIn && name.trim().isEmpty) || !allowedComments)
                    .animation(.easeInOut, value: feedback.trim().isEmpty || (!isLoggedIn && name.trim().isEmpty) || !allowedComments)
                }

                TextField("key.comments", text: $feedback, prompt: Text(String(localized: "key.comments.placeholder").lowercased()))
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .overlay(.tertiary.opacity(0.2), in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
            .onChange(of: feedback) { _ in
                if !allowedComments, !feedback.trim().isEmpty {
                    appState.commentsRulesPresented = true
                }
            }
        }
    }
}
