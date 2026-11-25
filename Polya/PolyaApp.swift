import PencilKit
import PDFKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

private enum PolyaColors {
    static let accent = Color(uiColor: .systemBlue)
    static let background = Color(uiColor: .systemBackground)
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let desk = Color(uiColor: .systemGroupedBackground)
}

private extension CoverColor {
    var color: Color {
        switch self {
        case .blue: Color(uiColor: .systemBlue)
        case .red: Color(uiColor: .systemRed)
        case .orange: Color(uiColor: .systemOrange)
        case .green: Color(uiColor: .systemGreen)
        case .purple: Color(uiColor: .systemPurple)
        case .gray: Color(uiColor: .systemGray)
        }
    }
}

private struct GlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(PolyaColors.panel, in: Capsule())
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.quaternary).allowsHitTesting(false) }
        }
    }
}

private enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list, finder
    var id: Self { self }
    var title: String {
        switch self {
        case .grid: "Сетка"
        case .list: "Список"
        case .finder: "Папки, как в Finder"
        }
    }
    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        case .finder: "folder"
        }
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, notebooks, boards, pdfs, folders
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Всё"
        case .notebooks: "Тетради"
        case .boards: "Доски"
        case .pdfs: "Импортированные PDF"
        case .folders: "Папки"
        }
    }
    func accepts(_ book: Notebook) -> Bool {
        switch self {
        case .all: true
        case .notebooks: !book.board
        case .boards: book.board
        case .pdfs: book.importedPages != nil
        case .folders: false
        }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case created, name, pages
    var id: Self { self }
    var title: String {
        switch self {
        case .created: "Сначала новые"
        case .name: "По названию"
        case .pages: "По числу листов"
        }
    }
    func ordered(_ lhs: Notebook, _ rhs: Notebook) -> Bool {
        switch self {
        case .created: lhs.created > rhs.created
        case .name: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .pages: lhs.pages.count > rhs.pages.count
        }
    }
}

private enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, png, jpeg, text, notion
    var id: Self { self }
    var title: String {
        switch self {
        case .pdf: "PDF"
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .text: "Текст"
        case .notion: "Notion"
        }
    }
    var detail: String {
        switch self {
        case .pdf: "Вся тетрадь, с рукописью и текстом"
        case .png: "Текущий лист, без сжатия"
        case .jpeg: "Текущий лист, меньший размер"
        case .text: "Распечатанный текст всех листов"
        case .notion: "Создать страницу с PDF в Notion"
        }
    }
    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .png: "photo"
        case .jpeg: "photo.on.rectangle"
        case .text: "doc.plaintext"
        case .notion: "arrow.up.right.square"
        }
    }
    var pageOnly: Bool { self == .png || self == .jpeg }
    var contentType: UTType {
        switch self {
        case .pdf, .notion: .pdf
        case .png: .png
        case .jpeg: .jpeg
        case .text: .plainText
        }
    }
}

@main
struct PolyaApp: App {
    @StateObject private var library = Library()

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library)
                .tint(PolyaColors.accent)
        }
    }
}

private struct LibraryView: View {
    @ObservedObject var library: Library
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }
    @State private var path: [UUID] = []
    @State private var openBooks: [UUID] = []
    @State private var positions: [UUID: UUID] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            Shelf(library: library, dark: dark, path: $path)
                .navigationDestination(for: UUID.self) { id in
                    if let book = library.notebooks.first(where: { $0.id == id }) {
                        NotebookView(library: library, book: book, dark: dark, position: Binding(
                            get: { positions[id] }, set: { positions[id] = $0 }
                        ), tabs: openBooks.compactMap { tab in library.notebooks.first { $0.id == tab } },
                        showLibrary: { _ = path.popLast() },
                        selectTab: { tab in
                            guard path.last == id, tab != id else { return }
                            path[path.count - 1] = tab
                        }, closeTab: { tab in
                            openBooks.removeAll { $0 == tab }
                            positions[tab] = nil
                            if tab == id { _ = path.popLast() }
                        })
                        .id(id)
                        .onAppear {
                            if !openBooks.contains(id) { openBooks.append(id) }
                        }
                    } else if let folder = library.folders.first(where: { $0.id == id }) {
                        Shelf(library: library, dark: dark, path: $path, folder: folder)
                    }
                }
        }
        .alert("Хранилище", isPresented: Binding(
            get: { library.error != nil },
            set: { if !$0 { library.error = nil } }
        )) {
            Button("OK") { library.error = nil }
        } message: {
            Text(library.error ?? "")
        }
    }
}

private struct Shelf: View {
    private enum Creation: String, CaseIterable, Identifiable {
        case notebook = "Тетрадь", board = "Доска", folder = "Папка"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .notebook: "book.closed"
            case .board: "rectangle.dashed"
            case .folder: "folder"
            }
        }
    }

    @ObservedObject var library: Library
    let dark: Bool
    @Binding var path: [UUID]
    var folder: NoteFolder?
    @State private var creation: Creation?
    @State private var pendingDeletion: (id: UUID, title: String, isFolder: Bool)?
    @State private var title = ""
    @State private var search = ""
    @State private var showsSearch = false
    @FocusState private var searchFocused: Bool
    @State private var notion = false
    @State private var importing = false
    @AppStorage("libraryFavorites") private var favoritesRaw = ""
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var favoritesOnly = false
    @AppStorage("libraryLayout") private var layout = LibraryLayout.grid
    @AppStorage("libraryFilter") private var filter = LibraryFilter.all
    @AppStorage("librarySort") private var sort = LibrarySort.created
    @AppStorage("libraryRailVisible") private var railVisible = true

    private var favorites: Set<String> { Set(favoritesRaw.split(separator: ",").map(String.init)) }

    private var heading: String {
        if let folder { return folder.title }
        if filter != .all { return filter.title }
        return favoritesOnly ? "Избранное" : "Документы"
    }

    private var books: [Notebook] {
        let scope = favoritesOnly ? library.notebooks.filter { favorites.contains($0.id.uuidString) } : library.notebooks
        let matching: [Notebook]
        if !search.isEmpty {
            matching = scope.filter { $0.title.localizedCaseInsensitiveContains(search) || ($0.pageText?.values.contains { $0.localizedCaseInsensitiveContains(search) } ?? false) || ($0.recognizedText?.values.contains { $0.localizedCaseInsensitiveContains(search) } ?? false) }
        } else {
            matching = favoritesOnly ? scope : scope.filter { $0.folderID == folder?.id }
        }
        return matching.filter { filter.accepts($0) }.sorted(by: sort.ordered)
    }

    private var folders: [NoteFolder] {
        guard filter == .all || filter == .folders else { return [] }
        let scope = favoritesOnly ? library.folders.filter { favorites.contains($0.id.uuidString) } : library.folders
        if !search.isEmpty { return scope.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        return (favoritesOnly ? scope : scope.filter { $0.parent == folder?.id })
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var showsRail: Bool { folder == nil && horizontalSize == .regular && !showsSearch }

    var body: some View {
        HStack(spacing: 0) {
            if showsRail && railVisible {
                rail
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            content
        }
        .animation(.smooth(duration: 0.25), value: railVisible)
        .background(PolyaColors.background)
        .navigationTitle(heading)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if showsRail {
                ToolbarItem(placement: .topBarLeading) {
                    Button(railVisible ? "Скрыть панель" : "Показать панель", systemImage: "sidebar.left") {
                        railVisible.toggle()
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Фильтр и сортировка", systemImage: "line.3.horizontal.decrease.circle") {
                    Picker("Показать", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Сортировка", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                }
                .labelStyle(.iconOnly)
                Menu("Вид", systemImage: layout.symbol) {
                    Picker("Вид", selection: $layout) {
                        ForEach(LibraryLayout.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                }
                .labelStyle(.iconOnly)
                Menu("Настройки", systemImage: "ellipsis.circle") {
                    Button("Настройки Notion", systemImage: "gearshape") { notion = true }
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                createMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(showsSearch ? "Закрыть поиск" : "Поиск",
                       systemImage: showsSearch ? "xmark" : "magnifyingglass") {
                    showsSearch.toggle()
                    if !showsSearch { search = "" }
                }
                .labelStyle(.iconOnly)
            }
        }
        .alert(creation?.rawValue ?? "", isPresented: Binding(
            get: { creation != nil }, set: { if !$0 { creation = nil } }
        ), presenting: creation) { kind in
            TextField("Название", text: $title)
            Button("Отмена", role: .cancel) {}
            Button("Создать") {
                favoritesOnly = false
                search = ""
                if kind == .folder {
                    library.createFolder(title, parent: folder?.id)
                } else if let id = library.create(title, folderID: folder?.id, board: kind == .board) {
                    path.append(id)
                }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Удалить «\(pendingDeletion?.title ?? "")»?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { item in
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if item.isFolder ? library.deleteFolder(item.id) : library.delete(item.id) {
                    favoritesRaw = favorites.subtracting([item.id.uuidString]).sorted().joined(separator: ",")
                }
            }
        } message: { item in
            Text(item.isFolder ? "Содержимое переместится на уровень выше." : "Страницы и аудиозаписи будут удалены без возможности восстановления.")
        }
        .sheet(isPresented: $notion) { NotionSettings() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            do {
                var imported: [UUID] = []
                var failures: [String] = []
                for url in try result.get() {
                    do {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        imported.append(try library.importPDF(title: url.deletingPathExtension().lastPathComponent,
                                                              data: data, count: document.pageCount, folderID: folder?.id))
                    } catch { failures.append(url.lastPathComponent) }
                }
                if !failures.isEmpty {
                    library.error = "Не удалось импортировать: " + failures.joined(separator: ", ")
                }
                if let last = imported.last {
                    favoritesOnly = false
                    search = ""
                    if imported.count == 1 { path.append(last) }
                }
            } catch { library.error = "Не удалось импортировать PDF: \(error.localizedDescription)" }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if folder == nil && horizontalSize != .regular {
                    Picker("Раздел библиотеки", selection: $favoritesOnly) {
                        Text("Документы").tag(false)
                        Text("Избранное").tag(true)
                    }.pickerStyle(.segmented)
                }
                if showsSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Название или текст", text: $search)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .onSubmit { searchFocused = false }
                        if !search.isEmpty {
                            Button("Очистить поиск", systemImage: "xmark.circle.fill") { search = "" }
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .frame(minHeight: 48)
                    .frame(maxWidth: 320)
                    .modifier(GlassPanel())
                    .frame(maxWidth: .infinity)
                    .task { searchFocused = true }
                }
                if books.isEmpty && folders.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Здесь пока пусто" : "Ничего не найдено",
                        systemImage: search.isEmpty ? "books.vertical" : "magnifyingglass",
                        description: search.isEmpty ? Text("Создай тетрадь, доску или папку.") : nil
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    cards
                }
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 9) {
            railButton("Документы", symbol: "tray.full", favorites: false)
            railButton("Избранное", symbol: "star", favorites: true)
            Spacer()
        }
        .padding(16)
        .padding(.top, 12)
        .frame(width: 218, alignment: .leading)
        .background(.regularMaterial)
    }

    private func railButton(_ title: String, symbol: String, favorites: Bool) -> some View {
        Button {
            favoritesOnly = favorites
            search = ""
        } label: {
            Label(title, systemImage: symbol)
                .font(.body.weight(favoritesOnly == favorites ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .foregroundStyle(favoritesOnly == favorites ? PolyaColors.accent : .primary)
                .background(favoritesOnly == favorites ? PolyaColors.accent.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(favoritesOnly == favorites ? .isSelected : [])
    }

    private var createMenu: some View {
        Menu {
            ForEach(Creation.allCases) { kind in
                Button(kind.rawValue, systemImage: kind.symbol) {
                    title = ""
                    creation = kind
                }
            }
            Button("Импортировать PDF", systemImage: "doc.badge.plus") { importing = true }
        } label: {
            Label("Создать", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(layout == .grid ? .adaptive(minimum: 190) : .flexible(), spacing: 20)], alignment: .leading, spacing: layout == .grid ? 24 : 4) {
            if layout == .finder, let folder {
                Button { _ = path.popLast() } label: {
                    Label("Вверх", systemImage: "arrow.turn.left.up")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .dropDestination(for: String.self) { items, _ in moveItems(items, into: folder.parent) }
                .accessibilityLabel("Вверх, в папку уровнем выше")
            }
            ForEach(folders) { item in
                shelfItem(item.title, subtitle: "Папка", symbol: "folder.fill", id: item.id, folderTarget: true) {
                    favoriteButton(item.id)
                    Button("Удалить…", systemImage: "trash", role: .destructive) {
                        pendingDeletion = (item.id, item.title, true)
                    }
                    Menu("Переместить", systemImage: "folder") {
                        Button("В библиотеку") { _ = library.moveFolder(item.id, to: nil) }
                        ForEach(library.folders.filter { $0.id != item.id }) { target in
                            Button(folderPath(target)) { _ = library.moveFolder(item.id, to: target.id) }
                        }
                    }
                }
            }
            ForEach(books) { book in
                shelfItem(book.title, subtitle: book.board ? "Доска" : "Листов: \(book.pages.count)",
                          symbol: book.board ? "rectangle.dashed" : "book.closed",
                          id: book.id, book: book) {
                    favoriteButton(book.id)
                    Button("Удалить…", systemImage: "trash", role: .destructive) {
                        pendingDeletion = (book.id, book.title, false)
                    }
                    Menu("Переместить", systemImage: "folder") {
                        Button("В библиотеку") { library.move(book.id, to: nil) }
                        ForEach(library.folders) { folder in
                            Button(folderPath(folder)) { library.move(book.id, to: folder.id) }
                        }
                    }
                    Menu("Цвет обложки", systemImage: "paintpalette") {
                        Button("Без цвета") { library.setCover(nil, for: book.id) }
                        ForEach(CoverColor.allCases, id: \.self) { cover in
                            Button(cover.rawValue) { library.setCover(cover, for: book.id) }
                        }
                    }
                }
            }
        }
    }

    private func shelfItem<Actions: View>(_ title: String, subtitle: String, symbol: String,
                                          id: UUID, book: Notebook? = nil, folderTarget: Bool = false,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        let menu = actions()
        return NavigationLink(value: id) {
            if layout != .grid {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .foregroundStyle(book?.coverColor?.color ?? PolyaColors.accent)
                        .frame(width: 44, height: 44)
                        .background(PolyaColors.panel, in: .rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 48)
                .frame(minHeight: 56)
                .contentShape(.rect)
            } else {
                card(title, subtitle: subtitle, symbol: symbol, id: id, book: book)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Действия: \(title)")
        }
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard folderTarget else { return false }
            return moveItems(items, into: id)
        }
    }

    private func moveItems(_ items: [String], into parent: UUID?) -> Bool {
        var moved = false
        for raw in items {
            guard let id = UUID(uuidString: raw), id != parent else { continue }
            if library.folders.contains(where: { $0.id == id }) {
                moved = library.moveFolder(id, to: parent) || moved
            } else if library.notebooks.contains(where: { $0.id == id }) {
                library.move(id, to: parent)
                moved = true
            }
        }
        return moved
    }

    private func folderPath(_ folder: NoteFolder) -> String {
        guard let parent = library.folders.first(where: { $0.id == folder.parent }) else { return folder.title }
        return folderPath(parent) + " / " + folder.title
    }

    private func favoriteButton(_ id: UUID) -> some View {
        let marked = favorites.contains(id.uuidString)
        return Button(marked ? "Убрать из избранного" : "В избранное", systemImage: marked ? "star.slash" : "star") {
            var next = favorites
            if next.remove(id.uuidString) == nil { next.insert(id.uuidString) }
            favoritesRaw = next.sorted().joined(separator: ",")
        }
    }

    private func card(_ title: String, subtitle: String, symbol: String, id: UUID, book: Notebook?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(book?.coverColor.map { $0.color.opacity(0.14) } ?? PolyaColors.panel)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                if let book, !book.board, let page = book.pages.first {
                    FirstPageCover(library: library, book: book, page: page, dark: dark,
                                   visible: path.last == folder?.id)
                        .id(dark)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(book?.coverColor?.color ?? PolyaColors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 230)
            .overlay(alignment: .leading) {
                if let cover = book?.coverColor {
                    Rectangle().fill(cover.color).frame(width: 8)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if favorites.contains(id.uuidString) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(PolyaColors.accent)
                        .padding(8)
                        .background(PolyaColors.panel, in: .circle)
                        .padding(6)
                        .accessibilityLabel("В избранном")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.trailing, 44)
        }
        .contentShape(.rect)
    }
}

private struct FirstPageCover: View {
    let library: Library
    let book: Notebook
    let page: UUID
    let dark: Bool
    let visible: Bool
    @State private var preview: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .padding(9)
                }
            }
            .accessibilityHidden(true)
            .task(id: visible) {
                guard visible else { return }
                let pdf = (book.importedPages?[page]).flatMap { number in
                    PDFDocument(url: library.importedPDFURL(book.id))?.page(at: number)
                }
                let drawing = (try? library.drawing(page)).flatMap { try? PKDrawing(data: $0) }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let scale: CGFloat = 0.25
                let size = CGSize(width: Paper.size.width * scale, height: Paper.size.height * scale)
                let appearance = UITraitCollection(userInterfaceStyle: dark && pdf == nil ? .dark : .light)
                preview = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                    let context = renderer.cgContext
                    context.scaleBy(x: scale, y: scale)
                    Paper.paint(context, dark: dark && pdf == nil,
                                style: pdf == nil ? book.paperStyle ?? .grid : .plain)
                    if let pdf { Paper.drawPDFPage(pdf, in: context) }
                    Paper.drawText(book.pageText?[page] ?? "", dark: dark && pdf == nil)
                    if let drawing, !drawing.strokes.isEmpty {
                        appearance.performAsCurrent {
                            drawing.image(from: Paper.bounds, scale: scale).draw(in: Paper.bounds)
                        }
                    }
                }
            }
    }
}

private struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf, .png, .jpeg, .plainText] }
    let data: Data
    let type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
        type = .pdf
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let pageName: String
    let board: Bool
    let render: (ExportFormat) throws -> Data
    let notion: () -> Void
    @State private var file: ExportFile?
    @State private var fileName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases.filter { $0 != .notion }) { format in
                        Button { save(format) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.title)
                                    Text(format.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: format.symbol)
                            }
                            .frame(minHeight: 44)
                        }
                        .disabled(board && format.pageOnly)
                    }
                } header: {
                    Text("Сохранить файл")
                } footer: {
                    if board { Text("Для доски доступен экспорт в PDF и текст.") }
                }
                Section {
                    Button("Отправить в Notion", systemImage: ExportFormat.notion.symbol) {
                        dismiss()
                        notion()
                    }
                } footer: {
                    Text(ExportFormat.notion.detail)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
        .fileExporter(isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
                      document: file, contentType: file?.type ?? .pdf, defaultFilename: fileName) { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
            file = nil
        }
    }

    private func save(_ format: ExportFormat) {
        error = nil
        do {
            let data = try render(format)
            fileName = format.pageOnly ? pageName : name
            file = ExportFile(data: data, type: format.contentType)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct NotebookView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var library: Library
    let book: Notebook
    let dark: Bool
    @AppStorage("notionParent") private var notionParent = ""
    @Binding var position: UUID?
    let tabs: [Notebook]
    let showLibrary: () -> Void
    let selectTab: (UUID) -> Void
    let closeTab: (UUID) -> Void
    @State private var writingMode = false
    @State private var pullingForPage = false
    @State private var pagePull: CGFloat = 0
    @State private var pageBrowser = false
    @State private var bookmarksOnly = false
    @State private var textPage: UUID?
    @State private var textDraft = ""
    @State private var recognizing = false
    @State private var focusMode = false
    @State private var pageToDelete: UUID?
    @State private var unsaved: [UUID: PKDrawing] = [:]
    @State private var tool = WritingTool.pen
    @AppStorage("writingEraserMode") private var eraserMode = EraserMode.strokes
    @State private var ink = Color.black
    @State private var neutralInk = true
    @State private var previousTool = WritingTool.pen
    @State private var lastInkTool = WritingTool.pen
    @State private var paletteOpen = false
    @State private var paletteTool: WritingTool?
    @State private var toolsOpen = false
    @State private var ruler = false
    @AppStorage("straightenLines") private var straighten = false
    @AppStorage("scratchErase") private var scratchErase = true
    @AppStorage("pinnedWritingTools") private var pinnedRaw = WritingTool.defaults.map(\.rawValue).joined(separator: ",")
    @AppStorage("writingWidths") private var writingWidths = Data()
    @State private var canvases = NSMapTable<NSUUID, WritingCanvas>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    @State private var renaming = false
    @State private var name = ""
    @State private var settings = false
    @State private var exporting = false
    @State private var exportError: String?
    @State private var notionURL: URL?
    @State private var exportSheet = false
    @State private var sourcePDF: PDFDocument?
    @State private var showAudio = false
    @StateObject private var audio = LectureAudio()

    private var pinned: [WritingTool] {
        pinnedRaw.split(separator: ",").compactMap { WritingTool(rawValue: String($0)) }
    }

    private var style: PaperStyle { book.paperStyle ?? (book.board ? .dots : .grid) }
    private var editorMotion: Animation? { reduceMotion ? nil : .smooth(duration: 0.24) }
    private var activePage: UUID? { position ?? book.pages.first }
    private var pageNumber: Int { activePage.flatMap { book.pages.firstIndex(of: $0) }.map { $0 + 1 } ?? 1 }
    private var savedWidths: [String: CGFloat] { (try? JSONDecoder().decode([String: CGFloat].self, from: writingWidths)) ?? [:] }
    private var uiInk: UIColor { neutralInk ? .black : UIColor(ink) }

    private func toolWidth(_ item: WritingTool) -> Binding<CGFloat> {
        let isEraser = item == .eraser
        let key = isEraser ? "eraser.\(eraserMode.rawValue)" : item.rawValue
        let widths = isEraser ? eraserMode.widths : item.inkWidths
        let fallback = isEraser ? eraserMode.defaultWidth : (item == .highlighter ? 15 : 3)
        return Binding {
            guard let saved = savedWidths[key], widths.contains(saved) else { return fallback }
            return saved
        } set: { size in
            var updated = savedWidths
            updated[key] = size
            if let data = try? JSONEncoder().encode(updated) { writingWidths = data }
        }
    }

    var body: some View {
        if #available(iOS 17.5, *) {
            editorScreen
                .onPencilDoubleTap { _ in pencilAction(UIPencilInteraction.preferredTapAction) }
                .onPencilSqueeze { phase in
                    if case .ended = phase { pencilAction(UIPencilInteraction.preferredSqueezeAction) }
                }
        } else {
            editorScreen
        }
    }

    private var editorScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !focusMode && !writingMode {
                    tabBar.transition(.opacity)
                }
                if !focusMode {
                    header.transition(.opacity)
                }
            }
            .animation(editorMotion, value: focusMode)
            .animation(editorMotion, value: writingMode)
            if !unsaved.isEmpty {
                Button("Повторить сохранение", systemImage: "exclamationmark.triangle") { _ = flush() }
                    .padding(8)
            }
            if book.board, let id = book.pages.first {
                editor(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                pages
                    .overlay(alignment: .bottomTrailing) { pageControls.padding(8) }
            }
        }
        .overlay(alignment: .topTrailing) {
            Group {
                if focusMode {
                    Button("Выйти из полноэкранного режима", systemImage: "arrow.down.right.and.arrow.up.left") {
                        focusMode = false
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .padding(8)
                    .keyboardShortcut(.cancelAction)
                    .transition(.opacity)
                }
            }
            .animation(editorMotion, value: focusMode)
        }
        .toolbar(focusMode || writingMode ? .hidden : .visible, for: .navigationBar)
        .persistentSystemOverlays(focusMode ? .hidden : .automatic)
        .statusBarHidden(focusMode)
        .background(PolyaColors.desk)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!unsaved.isEmpty)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Аудиозаписи", systemImage: audio.recording ? "waveform.circle.fill" : "waveform") {
                    showAudio = true
                }.labelStyle(.iconOnly)
                Button("На весь экран", systemImage: "arrow.up.left.and.arrow.down.right") { focusMode = true }
                Menu("Действия", systemImage: "ellipsis.circle") {
                    Button("Переименовать", systemImage: "square.and.pencil") { name = book.title; renaming = true }
                    Menu("Разметка бумаги", systemImage: "square.grid.3x3") {
                        ForEach(PaperStyle.allCases, id: \.self) { kind in
                            Button(kind.rawValue, systemImage: style == kind ? "checkmark" : "square") {
                                library.setPaper(kind, for: book.id)
                            }
                        }
                    }
                    Button("Текст на листе", systemImage: "textformat") {
                        guard let page = activePage else { return }
                        textDraft = book.pageText?[page] ?? ""
                        textPage = page
                    }.disabled(book.board)
                    Button(recognizing ? "Распознавание…" : "Распознать текст листа", systemImage: "text.viewfinder") { recognizePage() }
                        .disabled(recognizing || book.board)
                    Button("Экспорт…", systemImage: "square.and.arrow.up") {
                        guard flush() else { return }
                        exportSheet = true
                    }
                    Button("Отправить в Notion", systemImage: "arrow.up.right.square") { sendToNotion() }
                        .disabled(exporting || !unsaved.isEmpty)
                    if exporting { Text("Отправка…") }
                    if let notionURL { Link("Открыть в Notion", destination: notionURL) }
                    Button("Настройки Notion", systemImage: "gearshape") { settings = true }
                }
            }
        }
        .alert("Переименовать", isPresented: $renaming) {
            TextField("Название", text: $name)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") { library.rename(book.id, to: name) }
        }
        .sheet(isPresented: Binding(get: { textPage != nil }, set: { if !$0 { textPage = nil } })) {
            NavigationStack {
                VStack {
                    if !Paper.textFits(textDraft) {
                        Text("Текст не помещается на листе. Сократи его или перенеси часть на следующий лист.")
                            .font(.callout).foregroundStyle(.red).padding()
                    }
                    TextEditor(text: $textDraft).font(.body).padding()
                }
                    .accessibilityLabel("Текст текущего листа")
                    .navigationTitle("Текст на листе")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { textPage = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                if let page = textPage, library.setText(textDraft, book: book.id, page: page) { textPage = nil }
                            }.disabled(!Paper.textFits(textDraft))
                        }
                    }
            }
        }
        .confirmationDialog("Удалить лист?", isPresented: Binding(
            get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Удалить лист", role: .destructive) {
                guard let id = pageToDelete, flush() else { return }
                let remaining = book.pages.filter { $0 != id }
                if library.deletePage(book.id, page: id) {
                    position = remaining.first
                }
                pageToDelete = nil
            }
        } message: { Text("Рукопись на этом листе будет удалена без возможности отмены.") }
        .sheet(isPresented: $pageBrowser) { pageOverview }
        .sheet(isPresented: $settings) { NotionSettings() }
        .sheet(isPresented: $showAudio) { AudioSheet(audio: audio, library: library, book: book.id) }
        .task(id: book.id) {
            guard book.importedPages != nil else { return }
            sourcePDF = PDFDocument(url: library.importedPDFURL(book.id))
            if sourcePDF == nil { library.error = "Не удалось открыть исходный PDF." }
        }
        .onDisappear { audio.stop() }
        .sheet(isPresented: $exportSheet) {
            ExportSheet(name: book.title, pageName: "\(book.title), лист \(pageNumber)", board: book.board,
                        render: { try exportData($0) }, notion: { sendToNotion() })
        }
        .alert("Экспорт", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var pages: some View {
        GeometryReader { viewport in
            let width = viewport.size.width
            let height = focusMode ? viewport.size.height : width * Paper.size.height / Paper.size.width
            let scroll = ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(book.pages, id: \.self) { id in
                        editor(id)
                            .frame(width: width, height: height)
                            .clipped()
                            .id(id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $position, anchor: .top)
            .scrollBounceBehavior(.always, axes: .vertical)
            if #available(iOS 18.0, *) {
                scroll
                    .onScrollGeometryChange(for: CGFloat.self, of: pagePullProgress) { _, progress in
                        if pullingForPage { pagePull = progress }
                    }
                    .onScrollPhaseChange { old, new, context in
                        pullingForPage = new == .interacting
                        pagePull = pullingForPage ? pagePullProgress(context.geometry) : 0
                        if old == .interacting, new == .decelerating || new == .idle,
                           pagePullProgress(context.geometry) == 1 {
                            appendPage()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        ZStack {
                            Circle().strokeBorder(.secondary.opacity(0.25), lineWidth: 3)
                            Circle().trim(from: 0, to: pagePull)
                                .stroke(PolyaColors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: pagePull == 1 ? "checkmark" : "plus")
                        }
                        .frame(width: 36, height: 36)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                        .opacity(min(1, pagePull * 4))
                        .animation(editorMotion, value: pullingForPage)
                        .accessibilityHidden(pagePull == 0)
                        .accessibilityLabel("Новый лист")
                        .accessibilityValue(Text(pagePull, format: .percent.precision(.fractionLength(0))))
                    }
            } else {
                scroll
            }
        }
    }

    @available(iOS 18.0, *)
    private func pagePullProgress(_ geometry: ScrollGeometry) -> CGFloat {
        let bottom = max(-geometry.contentInsets.top,
                         geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
        return min(1, max(0, (geometry.contentOffset.y - bottom) / 52))
    }

    private func appendPage() {
        guard flush(), let next = library.addPage(book.id),
              let updated = library.notebooks.first(where: { $0.id == book.id }) else { return }
        go(to: updated.pages[next])
    }

    private func editor(_ id: UUID) -> some View {
        StoredPage(library: library, id: id, text: book.pageText?[id] ?? "", tool: tool, eraserMode: eraserMode, dark: dark, style: style,
                   ink: uiInk, width: toolWidth(tool).wrappedValue,
                   ruler: ruler && id == activePage, straighten: straighten, scratchErase: scratchErase,
                   board: book.board, backgroundPage: background(id),
                   toggleTabs: focusMode ? nil : { writingMode.toggle() }, didChange: { changed in
            unsaved[id] = changed
            _ = flush()
        }, registerCanvas: { view in
            canvases.setObject(view, forKey: id as NSUUID)
        })
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            Button("Открыть библиотеку", systemImage: "books.vertical") {
                if flush() { showLibrary() }
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        HStack(spacing: 0) {
                            Button(tab.title) {
                                if flush() { selectTab(tab.id) }
                            }
                            .lineLimit(1)
                            .padding(.leading, 14)
                            .frame(minHeight: 44)
                            .accessibilityAddTraits(tab.id == book.id ? .isSelected : [])
                            Button("Закрыть вкладку «\(tab.title)»", systemImage: "xmark") {
                                if flush() { closeTab(tab.id) }
                            }
                            .labelStyle(.iconOnly)
                            .imageScale(.small)
                            .frame(width: 44, height: 44)
                        }
                        .background(tab.id == book.id ? PolyaColors.accent.opacity(0.18) : PolyaColors.panel, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 3) {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(pinned, id: \.self) { item in
                        Button {
                            let alreadySelected = tool == item
                            selectTool(item)
                            if alreadySelected && (item.drawsInk || item == .eraser) {
                                paletteOpen = false
                                paletteTool = item
                            }
                        } label: {
                            Image(systemName: item.icon)
                                .frame(width: 44, height: 44)
                                .background(isSelected(item) ? PolyaColors.accent.opacity(0.18) : .clear,
                                            in: Capsule())
                                .foregroundStyle(isSelected(item) ? PolyaColors.accent : Color.primary)
                                .animation(editorMotion, value: isSelected(item))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item == .eraser ? eraserMode.title : "")
                        .accessibilityHint(isSelected(item) && (item.drawsInk || item == .eraser) ? "Нажмите ещё раз, чтобы настроить инструмент" : "")
                        .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
                        .popover(isPresented: Binding(
                            get: { paletteTool == item },
                            set: { if !$0 && paletteTool == item { paletteTool = nil } }
                        ), arrowEdge: .top) {
                            if item == .eraser { eraserOptions } else { palette(for: item) }
                        }
                    }
                }
                .padding(.leading, 6)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: CGFloat(max(pinned.count, 1)) * 47 + 6)
            Divider().frame(height: 22)
            Button {
                paletteTool = nil
                paletteOpen.toggle()
            } label: {
                Circle()
                    .fill(neutralInk ? Color.primary : ink)
                    .frame(width: 20, height: 20)
                    .padding(3)
                    .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Палитра")
            .popover(isPresented: $paletteOpen, arrowEdge: .top) { palette(for: lastInkTool) }
            Button("Настроить инструменты", systemImage: "plus.circle") { toolsOpen = true }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .popover(isPresented: $toolsOpen, arrowEdge: .top) { tools }
            Divider().frame(height: 22)
            Button("Отменить", systemImage: "arrow.uturn.backward") {
                if let activePage { canvases.object(forKey: activePage as NSUUID)?.undoManager?.undo() }
            }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            Button("Повторить", systemImage: "arrow.uturn.forward") {
                if let activePage { canvases.object(forKey: activePage as NSUUID)?.undoManager?.redo() }
            }.labelStyle(.iconOnly).frame(width: 44, height: 44)

        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .modifier(GlassPanel())
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var eraserOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ластик").font(.headline)
            Picker("Режим ластика", selection: $eraserMode) {
                ForEach(EraserMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            widthPicker("Размер, пт", widths: eraserMode.widths, selection: toolWidth(.eraser), color: .secondary)
            Button("Готово") { paletteTool = nil }
        }
        .padding(20)
        .frame(width: 290)
        .presentationCompactAdaptation(.popover)
    }

    private func palette(for item: WritingTool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Цвет чернил").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 7), count: 5), spacing: 7) {
                ForEach(InkTone.allCases, id: \.self) { tone in
                    Button {
                        neutralInk = tone == .neutral
                        ink = Color(uiColor: tone.uiColor)
                    } label: {
                        Circle()
                            .fill(tone == .neutral ? Color.primary : Color(uiColor: tone.uiColor))
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .overlay {
                                let selected = tone == .neutral ? neutralInk : !neutralInk && ink == Color(uiColor: tone.uiColor)
                                Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tone.rawValue)
                }
            }
            ColorPicker("Свой цвет", selection: Binding(get: { ink }, set: { ink = $0; neutralInk = false }),
                        supportsOpacity: false)
            Divider()
            let previewColor = neutralInk && item != .highlighter ? Color.primary : Color(uiColor: item.inkColor(uiInk))
            widthPicker("Толщина, пт", widths: item.inkWidths, selection: toolWidth(item), color: previewColor)
            Button("Готово") { paletteOpen = false; paletteTool = nil }
        }
        .padding(20)
        .frame(width: 290)
        .presentationCompactAdaptation(.popover)
    }

    private func widthPicker(_ title: LocalizedStringKey, widths: [CGFloat], selection: Binding<CGFloat>, color: Color) -> some View {
        let previewScale = min(1, 28 / max(1, widths.last ?? 1))
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 5) {
                ForEach(widths, id: \.self) { width in
                    let selected = selection.wrappedValue == width
                    let formatted = Double(width).formatted(.number.precision(.fractionLength(0...1)))
                    Button {
                        selection.wrappedValue = width
                    } label: {
                        VStack(spacing: 4) {
                            Capsule().fill(color)
                                .frame(width: 28, height: width * previewScale)
                                .frame(height: 28)
                            Text(formatted).font(.caption.monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(selected ? PolyaColors.accent.opacity(0.18) : PolyaColors.panel,
                                    in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(formatted) пт")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var tools: some View {
        Form {
            Section("На панели") {
                ForEach(WritingTool.allCases, id: \.self) { item in
                    Toggle(isOn: Binding(get: { pinned.contains(item) }, set: { visible in
                        var list = pinned
                        if visible {
                            if !list.contains(item) { list.append(item) }
                        } else {
                            list.removeAll { $0 == item }
                            if item == .ruler { ruler = false }
                            if tool == item { selectTool(.pen) }
                        }
                        pinnedRaw = list.map(\.rawValue).joined(separator: ",")
                    })) { Label(item.title, systemImage: item.icon) }
                    .disabled(item == .pen)
                }
            }
            Section("Геометрия") {
                Toggle("Выпрямлять почти прямые штрихи", isOn: $straighten)
                Toggle("Стирать зачёркиванием", isOn: $scratchErase)
            }
        }
        .frame(width: 340, height: 455)
        .presentationCompactAdaptation(.popover)
    }

    private func isSelected(_ item: WritingTool) -> Bool {
        item == .ruler ? ruler : tool == item
    }

    private func selectTool(_ item: WritingTool) {
        if item == .ruler {
            ruler.toggle()
            if ruler && !tool.drawsInk { selectTool(lastInkTool) }
        } else if item != tool {
            previousTool = tool
            tool = item
            if item.drawsInk { lastInkTool = item }
            if !item.drawsInk { ruler = false }
        }
    }

    @available(iOS 17.5, *)
    private func pencilAction(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser: selectTool(tool == .eraser ? lastInkTool : .eraser)
        case .switchPrevious: selectTool(previousTool)
        case .showColorPalette, .showContextualPalette, .showInkAttributes:
            if paletteTool != nil { paletteTool = nil }
            else { paletteOpen.toggle() }
        case .ignore, .runSystemShortcut: break
        @unknown default: break
        }
    }

    private var pageControls: some View {
        Menu {
            Button("Все листы", systemImage: "square.grid.2x2") {
                if flush() { pageBrowser = true }
            }
            Button("Добавить лист", systemImage: "plus", action: appendPage)
            if let activePage {
                let marked = book.bookmarks?.contains(activePage) == true
                Button(marked ? "Убрать закладку" : "Добавить закладку", systemImage: marked ? "bookmark.fill" : "bookmark") {
                    library.toggleBookmark(book.id, page: activePage)
                }
                Button("Дублировать лист", systemImage: "doc.on.doc") {
                    guard flush(), let copy = library.duplicatePage(book.id, page: activePage) else { return }
                    position = copy
                }
                Button("Переместить раньше", systemImage: "arrow.up") {
                    guard flush() else { return }
                    library.movePage(book.id, page: activePage, by: -1)
                }.disabled(pageNumber == 1)
                Button("Переместить позже", systemImage: "arrow.down") {
                    guard flush() else { return }
                    library.movePage(book.id, page: activePage, by: 1)
                }.disabled(pageNumber == book.pages.count)
                Button("Удалить лист…", systemImage: "trash", role: .destructive) {
                    pageToDelete = activePage
                }.disabled(book.pages.count == 1)
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.subheadline)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Листы, \(pageNumber) из \(book.pages.count)")
    }

    private var pageOverview: some View {
        NavigationStack {
            ScrollView {
                if bookmarksOnly && book.bookmarks?.isEmpty != false {
                    ContentUnavailableView("Нет закладок", systemImage: "bookmark")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 16)], spacing: 16) {
                        ForEach(Array(book.pages.enumerated()), id: \.element) { index, id in
                            if !bookmarksOnly || book.bookmarks?.contains(id) == true {
                                Button {
                                    go(to: id)
                                    pageBrowser = false
                                } label: {
                                    VStack(spacing: 6) {
                                        FirstPageCover(library: library, book: book, page: id, dark: dark, visible: true)
                                            .frame(height: 156)
                                            .background(PolyaColors.panel, in: .rect(cornerRadius: 12))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(activePage == id ? PolyaColors.accent : .clear, lineWidth: 2)
                                            }
                                        Label("Лист \(index + 1)", systemImage: book.bookmarks?.contains(id) == true ? "bookmark.fill" : "doc")
                                            .font(.subheadline)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(activePage == id ? .isSelected : [])
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(PolyaColors.background)
            .navigationTitle("Листы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(bookmarksOnly ? "Все листы" : "Только закладки",
                           systemImage: bookmarksOnly ? "bookmark.fill" : "bookmark") { bookmarksOnly.toggle() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { pageBrowser = false } }
            }
        }
    }

    private func go(to id: UUID) {
        guard flush() else { return }
        withAnimation(editorMotion) { position = id }
    }

    private func flush() -> Bool {
        do {
            for (id, drawing) in unsaved {
                try library.save(drawing.dataRepresentation(), page: id)
                unsaved.removeValue(forKey: id)
            }
            return true
        } catch {
            if library.error == nil { library.error = "Не удалось сохранить лист: \(error.localizedDescription)" }
            return false
        }
    }

    private func background(_ id: UUID) -> PDFPage? {
        book.importedPages?[id].flatMap { sourcePDF?.page(at: $0) }
    }

    private func makePDF() throws -> Data {
        if book.importedPages != nil && sourcePDF == nil { throw CocoaError(.fileReadCorruptFile) }
        let drawings = try book.pages.map { id in
            try library.drawing(id).map { try PKDrawing(data: $0) } ?? PKDrawing()
        }
        return Paper.pdf(drawings, dark: dark, board: book.board, style: style, backgrounds: book.pages.map { background($0) }, texts: book.pages.map { book.pageText?[$0] ?? "" })
    }

    private func recognizePage() {
        guard let page = activePage, !recognizing, flush() else { return }
        do {
            let drawing = try library.drawing(page).map { try PKDrawing(data: $0) } ?? PKDrawing()
            if book.importedPages?[page] != nil && background(page) == nil { throw CocoaError(.fileReadCorruptFile) }
            let image = UIGraphicsImageRenderer(size: Paper.size).image { renderer in
                Paper.paint(renderer.cgContext, dark: false, style: .plain)
                if let pdf = background(page) { Paper.drawPDFPage(pdf, in: renderer.cgContext) }
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    drawing.image(from: Paper.bounds, scale: 2).draw(in: Paper.bounds)
                }
            }
            guard let cgImage = image.cgImage else { return }
            recognizing = true
            Task {
                defer { recognizing = false }
                do {
                    let result = try await Paper.recognize(cgImage)
                    guard library.setText(result, book: book.id, page: page, recognized: true) else { return }
                    let existing = library.notebooks.first { $0.id == book.id }?.pageText?[page] ?? ""
                    textDraft = [existing, result].filter { !$0.isEmpty }.joined(separator: "\n\n")
                    textPage = page
                } catch { exportError = error.localizedDescription }
            }
        } catch { exportError = error.localizedDescription }
    }

    private func exportData(_ format: ExportFormat) throws -> Data {
        guard flush() else { throw CocoaError(.fileWriteUnknown) }
        switch format {
        case .pdf, .notion:
            return try makePDF()
        case .png, .jpeg:
            guard let page = activePage else { throw CocoaError(.fileReadNoSuchFile) }
            let image = try pageImage(page)
            if format == .png {
                guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                return data
            }
            guard let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
            return data
        case .text:
            let text = book.pages.map { book.pageText?[$0] ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            return Data(text.utf8)
        }
    }

    private func pageImage(_ id: UUID) throws -> UIImage {
        let pdf = background(id)
        if book.importedPages?[id] != nil && pdf == nil { throw CocoaError(.fileReadCorruptFile) }
        let drawing = try library.drawing(id).map { try PKDrawing(data: $0) } ?? PKDrawing()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let appearance = UITraitCollection(userInterfaceStyle: dark && pdf == nil ? .dark : .light)
        return UIGraphicsImageRenderer(size: Paper.size, format: format).image { renderer in
            let context = renderer.cgContext
            Paper.paint(context, dark: dark && pdf == nil, style: pdf == nil ? style : .plain)
            if let pdf { Paper.drawPDFPage(pdf, in: context) }
            Paper.drawText(book.pageText?[id] ?? "", dark: dark && pdf == nil)
            if !drawing.strokes.isEmpty {
                appearance.performAsCurrent {
                    drawing.image(from: Paper.bounds, scale: 2).draw(in: Paper.bounds)
                }
            }
        }
    }

    private func sendToNotion() {
        guard !exporting, flush() else { return }
        do {
            let token = try Notion.token()
            guard !token.isEmpty, Notion.pageID(notionParent) != nil else {
                settings = true
                return
            }
            let pdf = try makePDF()
            exporting = true
            notionURL = nil
            Task {
                defer { exporting = false }
                do {
                    notionURL = try await Notion.export(pdf, title: book.title, parent: notionParent, token: token)
                } catch { exportError = error.localizedDescription }
            }
        } catch { exportError = error.localizedDescription }
    }
}

private enum InkTone: String, CaseIterable {
    case neutral = "Основной", red = "Красный", orange = "Оранжевый", yellow = "Жёлтый", green = "Зелёный"
    case teal = "Бирюзовый", blue = "Синий", purple = "Фиолетовый", pink = "Розовый", gray = "Серый"

    var uiColor: UIColor {
        switch self {
        case .neutral: .black
        case .red: .systemRed
        case .blue: .systemBlue
        case .green: .systemGreen
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .teal: .systemTeal
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}

private struct StoredPage: View {
    let library: Library
    let id: UUID
    var text = ""
    let tool: WritingTool
    let eraserMode: EraserMode
    let dark: Bool
    let style: PaperStyle
    let ink: UIColor
    let width: CGFloat
    let ruler: Bool
    let straighten: Bool
    let scratchErase: Bool
    let board: Bool
    let backgroundPage: PDFPage?
    let toggleTabs: (() -> Void)?
    let didChange: (PKDrawing) -> Void
    let registerCanvas: (WritingCanvas) -> Void
    @State private var drawing: PKDrawing?
    @State private var failure = false

    var body: some View {
        Group {
            if let drawing {
                PaperEditor(drawing: drawing, text: text, tool: tool, eraserMode: eraserMode, dark: dark, style: style, ink: ink, width: width, ruler: ruler, straighten: straighten, scratchErase: scratchErase, board: board, backgroundPage: backgroundPage,
                            toggleTabs: toggleTabs,
                            didChange: { newest in
                                self.drawing = newest
                                didChange(newest)
                            }, registerCanvas: registerCanvas)
            } else if failure {
                ContentUnavailableView("Лист недоступен", systemImage: "doc.badge.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .task(id: id) {
            guard drawing == nil else { return }
            do { drawing = try library.drawing(id).map { try PKDrawing(data: $0) } ?? PKDrawing() }
            catch { failure = true }
        }
    }
}

private struct NotionSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notionParent") private var parent = ""
    @State private var address = ""
    @State private var token = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ссылка или ID страницы", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Токен интеграции", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Добавьте внутреннюю интеграцию в меню подключений выбранной страницы Notion. Экспорт создаёт дочернюю страницу с PDF всей тетради.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Link("Управление интеграциями Notion", destination: URL(string: "https://www.notion.so/my-integrations")!)
            }
            .navigationTitle("Notion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let id = Notion.pageID(address) else { return }
                        do {
                            try Notion.saveToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                            parent = id
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(Notion.pageID(address) == nil || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                address = parent
                do { token = try Notion.token() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
private final class LectureAudio: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var files: [URL] = []
    @Published private(set) var playing: URL?
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var monitor: Task<Void, Never>?

    func reload(library: Library, book: UUID) {
        do { files = try library.recordings(book) }
        catch { self.error = error.localizedDescription }
    }

    func start(library: Library, book: UUID) async {
        error = nil
        guard !recording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Разреши доступ к микрофону для «Полей» в настройках iPad."
            return
        }
        player?.stop()
        playing = nil
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let date = Date.now.ISO8601Format().replacingOccurrences(of: ":", with: "-")
            let name = date + "_" + UUID().uuidString + ".m4a"
            let url = try library.recordingFolder(book).appendingPathComponent(name)
            let device = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            guard device.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = device
            recording = true
            monitor?.cancel()
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, !Task.isCancelled else { return }
                    if self.recorder?.isRecording != true {
                        self.stop()
                        self.reload(library: library, book: book)
                        return
                    }
                }
            }
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            self.error = error.localizedDescription
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        recorder?.stop()
        player?.stop()
        if recording || playing != nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        recording = false
        playing = nil
    }

    func play(_ file: URL) {
        error = nil
        guard !recording else { return }
        if playing == file { stop(); return }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            let playback = try AVAudioPlayer(contentsOf: file)
            guard playback.play() else { throw CocoaError(.fileReadUnknown) }
            player = playback
            playing = file
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, !Task.isCancelled else { return }
                    if self.player?.isPlaying != true { self.stop(); return }
                }
            }
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            self.error = error.localizedDescription
        }
    }
}

private struct AudioSheet: View {
    @ObservedObject var audio: LectureAudio
    let library: Library
    let book: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var starting = false
    @State private var recordingToDelete: URL?

    var body: some View {
        NavigationStack {
            List {
                Button(audio.recording ? "Остановить запись" : "Записать лекцию",
                       systemImage: audio.recording ? "stop.circle" : "record.circle") {
                    if audio.recording {
                        audio.stop()
                        audio.reload(library: library, book: book)
                    } else {
                        starting = true
                        Task {
                            await audio.start(library: library, book: book)
                            starting = false
                        }
                    }
                }
                .disabled(starting)
                ForEach(audio.files, id: \.self) { file in
                    Button(label(file), systemImage: audio.playing == file ? "stop.fill" : "play.fill") { audio.play(file) }
                        .disabled(audio.recording)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) { recordingToDelete = file }
                                .disabled(audio.recording || starting)
                        }
                }
                if let error = audio.error { Text(error).foregroundStyle(.red) }
            }
            .alert("Удалить аудиозапись?", isPresented: Binding(
                get: { recordingToDelete != nil }, set: { if !$0 { recordingToDelete = nil } }
            ), presenting: recordingToDelete) { file in
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    if audio.playing == file { audio.play(file) }
                    do {
                        try FileManager.default.removeItem(at: file)
                        audio.reload(library: library, book: book)
                    } catch { audio.error = error.localizedDescription }
                }
            }
            .navigationTitle("Аудиозаписи")
            .toolbar { Button("Готово") { dismiss() } }
            .onAppear { if !audio.recording { audio.reload(library: library, book: book) } }
        }
    }

    private func label(_ file: URL) -> String {
        let value = String(file.deletingPathExtension().lastPathComponent.prefix(20))
        guard let separator = value.firstIndex(of: "T"),
              let date = ISO8601DateFormatter().date(from: String(value[..<separator]) + "T" +
                  value[value.index(after: separator)...].replacingOccurrences(of: "-", with: ":")) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
