import Foundation
import Combine

enum PaperStyle: String, Codable, CaseIterable {
    case grid = "Клетка", ruled = "Линии", dots = "Точки", cornell = "Корнелл", music = "Нотный стан", plain = "Без разметки"
}

enum CoverColor: String, Codable, CaseIterable {
    case blue = "Синяя", red = "Красная", orange = "Оранжевая", green = "Зелёная", purple = "Фиолетовая", gray = "Серая"
}

struct Notebook: Codable, Identifiable {
    var id = UUID()
    var title: String
    var pages = [UUID()]
    var created = Date()
    var folderID: UUID?
    var isBoard: Bool?
    var bookmarks: Set<UUID>?
    var importedPages: [UUID: Int]?
    var paperStyle: PaperStyle?
    var pageText: [UUID: String]?
    var recognizedText: [UUID: String]?
    var coverColor: CoverColor?

    var board: Bool { isBoard == true }
}

struct NoteFolder: Codable, Identifiable {
    var id = UUID()
    var title: String
    var parent: UUID?
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var folders: [NoteFolder] = []
    @Published var error: String?

    private let folder: URL
    private var index: URL { folder.appendingPathComponent("library.json") }
    private var folderIndex: URL { folder.appendingPathComponent("folders.json") }
    private var canWrite = false

    init(folder: URL = URL.documentsDirectory.appendingPathComponent("Polya", isDirectory: true)) {
        self.folder = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                notebooks = try JSONDecoder().decode([Notebook].self, from: Data(contentsOf: index))
            }
            if FileManager.default.fileExists(atPath: folderIndex.path) {
                folders = try JSONDecoder().decode([NoteFolder].self, from: Data(contentsOf: folderIndex))
            }
            canWrite = true
        } catch {
            self.error = "Не удалось открыть библиотеку: \(error.localizedDescription)"
        }
    }

    func create(_ title: String, folderID: UUID? = nil, board: Bool = false) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let book = Notebook(title: title, folderID: folderID, isBoard: board)
        return commit([book] + notebooks) ? book.id : nil
    }

    func importPDF(title: String, data: Data, count: Int, folderID: UUID?) throws -> UUID {
        guard canWrite, count > 0 else { throw CocoaError(.fileWriteUnknown) }
        let pages = (0..<count).map { _ in UUID() }
        let book = Notebook(title: title, pages: pages, folderID: folderID,
                            importedPages: Dictionary(uniqueKeysWithValues: zip(pages, 0..<count)))
        let file = importedPDFURL(book.id)
        try data.write(to: file, options: .atomic)
        guard commit([book] + notebooks) else {
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileWriteUnknown)
        }
        return book.id
    }

    func delete(_ id: UUID) -> Bool {
        guard let book = notebooks.first(where: { $0.id == id }),
              commit(notebooks.filter { $0.id != id }) else { return false }

        let audio = folder.appendingPathComponent(id.uuidString + "-audio", isDirectory: true)
        for file in book.pages.map(pageURL) + [importedPDFURL(id), audio] {
            do {
                try FileManager.default.removeItem(at: file)
            } catch let failure as CocoaError where failure.code == .fileNoSuchFile || failure.code == .fileReadNoSuchFile {
                continue
            } catch {
                self.error = "Запись удалена из библиотеки. Не удалось очистить все её файлы: \(error.localizedDescription)"
            }
        }
        return true
    }

    func importedPDFURL(_ book: UUID) -> URL {
        folder.appendingPathComponent(book.uuidString + ".pdf")
    }

    func recordings(_ book: UUID) throws -> [URL] {
        let directory = try recordingFolder(book)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "m4a" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func recordingFolder(_ book: UUID) throws -> URL {
        let directory = folder.appendingPathComponent(book.uuidString + "-audio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func createFolder(_ title: String, parent: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = commitFolders([NoteFolder(title: title, parent: parent)] + folders)
    }

    func moveFolder(_ id: UUID, to parent: UUID?) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }), parent != id else { return false }
        var cursor = parent
        while let current = cursor {
            if current == id { return false }
            cursor = folders.first(where: { $0.id == current })?.parent
        }
        var next = folders
        next[index].parent = parent
        return commitFolders(next)
    }

    func deleteFolder(_ id: UUID) -> Bool {
        guard let removed = folders.first(where: { $0.id == id }) else { return false }
        var books = notebooks
        for index in books.indices where books[index].folderID == id {
            books[index].folderID = removed.parent
        }
        guard commit(books) else { return false }
        var remaining = folders.filter { $0.id != id }
        for index in remaining.indices where remaining[index].parent == id {
            remaining[index].parent = removed.parent
        }
        return commitFolders(remaining)
    }

    private func commitFolders(_ next: [NoteFolder]) -> Bool {
        do {
            guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
            try JSONEncoder().encode(next).write(to: folderIndex, options: .atomic)
            folders = next
            return true
        } catch {
            self.error = "Не удалось сохранить папки: \(error.localizedDescription)"
            return false
        }
    }

    func setPaper(_ style: PaperStyle, for book: UUID) {
        guard let position = notebooks.firstIndex(where: { $0.id == book }) else { return }
        var next = notebooks
        next[position].paperStyle = style
        _ = commit(next)
    }

    func setCover(_ color: CoverColor?, for book: UUID) {
        guard let position = notebooks.firstIndex(where: { $0.id == book }) else { return }
        var next = notebooks
        next[position].coverColor = color
        _ = commit(next)
    }

    func move(_ book: UUID, to folder: UUID?) {
        guard let position = notebooks.firstIndex(where: { $0.id == book }) else { return }
        var next = notebooks
        next[position].folderID = folder
        _ = commit(next)
    }

    func toggleBookmark(_ book: UUID, page: UUID) {
        guard let position = notebooks.firstIndex(where: { $0.id == book }),
              notebooks[position].pages.contains(page) else { return }
        var next = notebooks
        var marks = next[position].bookmarks ?? []
        if marks.remove(page) == nil { marks.insert(page) }
        next[position].bookmarks = marks
        _ = commit(next)
    }

    func rename(_ book: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let position = notebooks.firstIndex(where: { $0.id == book }) else { return }
        var next = notebooks
        next[position].title = title
        _ = commit(next)
    }

    func addPage(_ book: UUID) -> Int? {
        guard let position = notebooks.firstIndex(where: { $0.id == book }), !notebooks[position].board else { return nil }
        var next = notebooks
        next[position].pages.append(UUID())
        return commit(next) ? next[position].pages.count - 1 : nil
    }

    func duplicatePage(_ book: UUID, page: UUID) -> UUID? {
        guard let index = notebooks.firstIndex(where: { $0.id == book }),
              !notebooks[index].board,
              let source = notebooks[index].pages.firstIndex(of: page) else { return nil }
        let copy = UUID()
        do {
            if let data = try drawing(page) { try save(data, page: copy) }
            var next = notebooks
            next[index].pages.insert(copy, at: source + 1)
            next[index].pageText?[copy] = notebooks[index].pageText?[page]
            next[index].recognizedText?[copy] = notebooks[index].recognizedText?[page]
            if let background = next[index].importedPages?[page] {
                next[index].importedPages?[copy] = background
            }
            guard commit(next) else {
                try? FileManager.default.removeItem(at: pageURL(copy))
                return nil
            }
            return copy
        } catch {
            self.error = "Не удалось скопировать лист: \(error.localizedDescription)"
            return nil
        }
    }

    func movePage(_ book: UUID, page: UUID, by offset: Int) {
        guard let index = notebooks.firstIndex(where: { $0.id == book }),
              let source = notebooks[index].pages.firstIndex(of: page),
              offset == -1 || offset == 1,
              notebooks[index].pages.indices.contains(source + offset) else { return }
        var next = notebooks
        next[index].pages.swapAt(source, source + offset)
        _ = commit(next)
    }

    func deletePage(_ book: UUID, page: UUID) -> Bool {
        guard let index = notebooks.firstIndex(where: { $0.id == book }),
              notebooks[index].pages.count > 1,
              notebooks[index].pages.contains(page) else { return false }
        var next = notebooks
        next[index].pages.removeAll { $0 == page }
        next[index].bookmarks?.remove(page)
        next[index].pageText?.removeValue(forKey: page)
        next[index].recognizedText?.removeValue(forKey: page)
        next[index].importedPages?.removeValue(forKey: page)
        guard commit(next) else { return false }
        do {
            if FileManager.default.fileExists(atPath: pageURL(page).path) {
                try FileManager.default.removeItem(at: pageURL(page))
            }
        } catch {
            self.error = "Лист удалён. Не удалось очистить его файл: \(error.localizedDescription)"
        }
        return true
    }

    @discardableResult
    func setText(_ text: String, book: UUID, page: UUID, recognized: Bool = false) -> Bool {
        guard let index = notebooks.firstIndex(where: { $0.id == book }),
              notebooks[index].pages.contains(page) else { return false }
        var next = notebooks
        if recognized {
            if next[index].recognizedText == nil { next[index].recognizedText = [:] }
            next[index].recognizedText?[page] = text
        } else {
            if next[index].pageText == nil { next[index].pageText = [:] }
            next[index].pageText?[page] = text
        }
        return commit(next)
    }

    func drawing(_ page: UUID) throws -> Data? {
        do {
            return try Data(contentsOf: pageURL(page))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ data: Data, page: UUID) throws {
        guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: pageURL(page), options: .atomic)
    }

    private func pageURL(_ page: UUID) -> URL {
        folder.appendingPathComponent(page.uuidString + ".drawing")
    }

    private func commit(_ next: [Notebook]) -> Bool {
        do {
            guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
            try JSONEncoder().encode(next).write(to: index, options: .atomic)
            notebooks = next
            return true
        } catch {
            self.error = "Не удалось сохранить библиотеку: \(error.localizedDescription)"
            return false
        }
    }
}
