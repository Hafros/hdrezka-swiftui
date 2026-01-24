//
//  PersonTextWithPhoto.swift
//  HDrezka
//
//  Created by Alex Hafros on 21.01.2026.
//

import Kingfisher
import SwiftUI

struct PersonTextWithPhoto: View {
    private let person: PersonSimple

    init(person: PersonSimple) {
        self.person = person
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            KFImage
                .url(URL(string: person.photo))
                .placeholder {
                    Color.gray
                }
                .resizable()
                .cancelOnDisappear(true)
                .retry(NetworkRetryStrategy())
                .scaledToFill()
                .frame(width: 36, height: 36)
                .background(.quinary)
                .clipShape(.circle)
                .overlay(.tertiary.opacity(0.2), in: .circle.stroke(lineWidth: 1))

            Text(person.name)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
