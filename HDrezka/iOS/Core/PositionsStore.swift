import CoreData
import Foundation

struct PlayerPositionSnapshot {
    let id: String
    let acting: String
    let season: String?
    let episode: String?
    let position: Double
}

struct SelectPositionSnapshot {
    let id: String
    let acting: String
    let season: String?
    let episode: String?
    let subtitles: String?
}

enum PositionsStore {
    static func fetchPlayerPositions() -> [PlayerPositionSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: playerEntityName)

        return performFetch(request: request) { object in
            guard let id = object.value(forKey: "id") as? String,
                  let acting = object.value(forKey: "acting") as? String
            else {
                return nil
            }

            return PlayerPositionSnapshot(
                id: id,
                acting: acting,
                season: object.value(forKey: "season") as? String,
                episode: object.value(forKey: "episode") as? String,
                position: object.value(forKey: "position") as? Double ?? 0,
            )
        }
    }

    static func fetchSelectPositions() -> [SelectPositionSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: selectEntityName)

        return performFetch(request: request) { object in
            guard let id = object.value(forKey: "id") as? String,
                  let acting = object.value(forKey: "acting") as? String
            else {
                return nil
            }

            return SelectPositionSnapshot(
                id: id,
                acting: acting,
                season: object.value(forKey: "season") as? String,
                episode: object.value(forKey: "episode") as? String,
                subtitles: object.value(forKey: "subtitles") as? String,
            )
        }
    }

    static func upsertPlayerPosition(id: String, acting: String, season: String?, episode: String?, position: Double) {
        let object = fetchOrCreate(entityName: playerEntityName, id: id)

        object.setValue(id, forKey: "id")
        object.setValue(acting, forKey: "acting")
        object.setValue(season, forKey: "season")
        object.setValue(episode, forKey: "episode")
        object.setValue(position, forKey: "position")

        saveIfNeeded()
    }

    static func upsertSelectPosition(id: String, acting: String, season: String?, episode: String?, subtitles: String? = nil) {
        let object = fetchOrCreate(entityName: selectEntityName, id: id)

        object.setValue(id, forKey: "id")
        object.setValue(acting, forKey: "acting")
        object.setValue(season, forKey: "season")
        object.setValue(episode, forKey: "episode")

        if subtitles != nil || object.value(forKey: "subtitles") == nil {
            object.setValue(subtitles, forKey: "subtitles")
        }

        saveIfNeeded()
    }

    static func clearPlayerPositions() {
        deleteAll(entityName: playerEntityName)
    }

    static func clearSelectPositions() {
        deleteAll(entityName: selectEntityName)
    }

    static func playerPositionsCount() -> Int {
        count(entityName: playerEntityName)
    }

    static func selectPositionsCount() -> Int {
        count(entityName: selectEntityName)
    }

    private static func performFetch<T>(request: NSFetchRequest<NSManagedObject>, map: (NSManagedObject) -> T?) -> [T] {
        context.performAndWait {
            (try? context.fetch(request).compactMap(map)) ?? []
        }
    }

    private static func fetchOrCreate(entityName: String, id: String) -> NSManagedObject {
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id)

            if let existing = (try? context.fetch(request))?.first {
                return existing
            }

            let entity = container.managedObjectModel.entities.first { $0.name == entityName } ?? NSEntityDescription()
            return NSManagedObject(entity: entity, insertInto: context)
        }
    }

    private static func deleteAll(entityName: String) {
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let objects = (try? context.fetch(request)) ?? []
            objects.forEach(context.delete)
            saveIfNeeded()
        }
    }

    private static func count(entityName: String) -> Int {
        context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            return (try? context.count(for: request)) ?? 0
        }
    }

    private static func saveIfNeeded() {
        context.performAndWait {
            guard context.hasChanges else { return }
            try? context.save()
        }
    }

    private static let playerEntityName = "PlayerPositionEntity"
    private static let selectEntityName = "SelectPositionEntity"

    private static let container: NSPersistentContainer = {
        let model = NSManagedObjectModel()

        let playerEntity = NSEntityDescription()
        playerEntity.name = playerEntityName
        playerEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let playerId = NSAttributeDescription()
        playerId.name = "id"
        playerId.attributeType = .stringAttributeType
        playerId.isOptional = false

        let playerActing = NSAttributeDescription()
        playerActing.name = "acting"
        playerActing.attributeType = .stringAttributeType
        playerActing.isOptional = false

        let playerSeason = NSAttributeDescription()
        playerSeason.name = "season"
        playerSeason.attributeType = .stringAttributeType
        playerSeason.isOptional = true

        let playerEpisode = NSAttributeDescription()
        playerEpisode.name = "episode"
        playerEpisode.attributeType = .stringAttributeType
        playerEpisode.isOptional = true

        let playerPosition = NSAttributeDescription()
        playerPosition.name = "position"
        playerPosition.attributeType = .doubleAttributeType
        playerPosition.isOptional = false

        playerEntity.properties = [playerId, playerActing, playerSeason, playerEpisode, playerPosition]

        let selectEntity = NSEntityDescription()
        selectEntity.name = selectEntityName
        selectEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let selectId = NSAttributeDescription()
        selectId.name = "id"
        selectId.attributeType = .stringAttributeType
        selectId.isOptional = false

        let selectActing = NSAttributeDescription()
        selectActing.name = "acting"
        selectActing.attributeType = .stringAttributeType
        selectActing.isOptional = false

        let selectSeason = NSAttributeDescription()
        selectSeason.name = "season"
        selectSeason.attributeType = .stringAttributeType
        selectSeason.isOptional = true

        let selectEpisode = NSAttributeDescription()
        selectEpisode.name = "episode"
        selectEpisode.attributeType = .stringAttributeType
        selectEpisode.isOptional = true

        let selectSubtitles = NSAttributeDescription()
        selectSubtitles.name = "subtitles"
        selectSubtitles.attributeType = .stringAttributeType
        selectSubtitles.isOptional = true

        selectEntity.properties = [selectId, selectActing, selectSeason, selectEpisode, selectSubtitles]

        model.entities = [playerEntity, selectEntity]

        let container = NSPersistentContainer(name: "HDrezkaPositionsStore", managedObjectModel: model)

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let storeURL = baseURL.appendingPathComponent("HDrezkaPositions.sqlite")

        let description = NSPersistentStoreDescription(url: storeURL)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores(completionHandler: { _, _ in })
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    private static var context: NSManagedObjectContext {
        container.viewContext
    }
}
