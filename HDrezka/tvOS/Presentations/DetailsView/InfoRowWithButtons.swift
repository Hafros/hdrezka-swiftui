//
//  InfoRowWithButtons.swift
//  HDrezka
//
//  Created by Alex Hafros on 21.01.2026.
//

import SwiftUI

struct InfoRowWithButtons<T: Named>: View {
    private let title: String
    private let description: String
    private let data: [T]

    @State private var isPresented: Bool = false

    @Binding private var countryDestination: MovieCountry?
    @Binding private var genreDestination: MovieGenre?
    @Binding private var personDestination: PersonSimple?
    @Binding private var listDestination: MovieList?
    @Binding private var collectionDestination: MoviesCollection?

    init(_ title: String,
         _ description: String,
         _ data: [T],
         countryDestination: Binding<MovieCountry?>,
         genreDestination: Binding<MovieGenre?>,
         personDestination: Binding<PersonSimple?>,
         listDestination: Binding<MovieList?>,
         collectionDestination: Binding<MoviesCollection?>)
    {
        self.title = title
        self.description = description
        self.data = data
        _countryDestination = countryDestination
        _genreDestination = genreDestination
        _personDestination = personDestination
        _listDestination = listDestination
        _collectionDestination = collectionDestination
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.body)

            Spacer(minLength: 10)

            HStack(alignment: .center, spacing: 4) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(data.prefix(2)) { item in
                        NavigationLink(value: Destinations.fromNamed(item)) {
                            if let person = item as? PersonSimple, !person.photo.isEmpty {
                                PersonTextWithPhoto(person: person)
                                    .contentShape(.rect)
                            } else if let list = item as? MovieList, let position = list.moviePosition?.toNumeral() {
                                let place = Text("key.place-\(position)").foregroundStyle(.tertiary)

                                Text("key.list-\(list.name)-\(place)")
                                    .foregroundStyle(.secondary)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .contentShape(.rect)
                            } else {
                                Text(item.name)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .contentShape(.rect)
                            }
                        }
                        .buttonStyle(.plain)

                        if item != data.prefix(2).last {
                            Text(verbatim: ", ")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if data.count > 2 {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        VStack(alignment: .center, spacing: 6) {
                            Text(title)
                                .font(.body.bold())
                                .multilineTextAlignment(.center)

                            Text(description)
                                .font(.caption)
                                .multilineTextAlignment(.center)

                            VStack(alignment: .center, spacing: 0) {
                                ForEach(data) { item in
                                    Button {
                                        switch Destinations.fromNamed(item) {
                                        case let .country(country):
                                            countryDestination = country
                                        case let .genre(genre):
                                            genreDestination = genre
                                        case let .person(person):
                                            personDestination = person
                                        case let .list(list):
                                            listDestination = list
                                        case let .collection(collection):
                                            collectionDestination = collection
                                        default:
                                            fatalError("Need \"named\" implementation")
                                        }
                                    } label: {
                                        if let person = item as? PersonSimple, !person.photo.isEmpty {
                                            HStack(alignment: .center, spacing: 8) {
                                                KFImage
                                                    .url(URL(string: person.photo))
                                                    .placeholder {
                                                        Color.gray.shimmering()
                                                    }
                                                    .resizable()
                                                    .loadTransition(.blurReplace, animation: .easeInOut)
                                                    .removeBackground()
                                                    .cancelOnDisappear(true)
                                                    .retry(NetworkRetryStrategy())
                                                    .imageFill(2 / 3)
                                                    .frame(width: 36, height: 36)
                                                    .background(.quinary)
                                                    .clipShape(.circle)
                                                    .padding(2)
                                                    .overlay(.tertiary.opacity(0.2), in: .circle.stroke(lineWidth: 1))

                                                Text(person.name)
                                                    .font(.body)
                                                    .lineLimit(nil)
                                                    .multilineTextAlignment(.center)
                                            }
                                            .contentShape(.rect)
                                        } else if let list = item as? MovieList, let position = list.moviePosition?.toNumeral() {
                                            let place = Text("key.place-\(position)").foregroundStyle(.secondary)

                                            Text("key.list-\(list.name)-\(place)")
                                                .font(.body)
                                                .lineLimit(nil)
                                                .multilineTextAlignment(.center)
                                                .contentShape(.rect)
                                        } else {
                                            Text(item.name)
                                                .font(.body)
                                                .lineLimit(nil)
                                                .multilineTextAlignment(.center)
                                                .contentShape(.rect)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 6)

                                    if item != data.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(width: 200)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
