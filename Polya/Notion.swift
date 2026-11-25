import Foundation
import Security

enum NotionError: LocalizedError {
    case settings, tooLarge, keychain(OSStatus), response, http(Int, String)

    var errorDescription: String? {
        switch self {
        case .settings: "Укажите токен интеграции и ссылку или ID родительской страницы."
        case .tooLarge: "PDF больше 20 МБ. Notion принимает до 20 МБ за одну загрузку."
        case .keychain(let status): "Связка ключей недоступна (код \(status))."
        case .response: "Notion вернул неожиданный ответ."
        case .http(let status, let message): "Notion (\(status)): \(message)"
        }
    }
}

enum Notion {
    private static let key: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "study.polya.notion",
        kSecAttrAccount as String: "integration"
    ]

    static func token() throws -> String {
        var query = key
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else { throw NotionError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    static func saveToken(_ token: String) throws {
        let value = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(key as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            var item = key.merging(value) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NotionError.keychain(status) }
    }

    static func pageID(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: value) { return id.uuidString.lowercased() }
        let path = URL(string: value)?.lastPathComponent ?? value
        guard let match = path.range(of: "[0-9a-fA-F]{32}$", options: .regularExpression) else { return nil }
        return String(path[match]).lowercased()
    }

    static func export(_ pdf: Data, title: String, parent: String, token: String) async throws -> URL {
        guard pdf.count <= 20_000_000 else { throw NotionError.tooLarge }
        guard !token.isEmpty, let parent = pageID(parent) else { throw NotionError.settings }

        let file = try await post("file_uploads", token: token, json: [
            "mode": "single_part", "filename": "Polya.pdf", "content_type": "application/pdf"
        ])
        guard let id = file["id"] as? String, UUID(uuidString: id) != nil else { throw NotionError.response }

        let boundary = UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"Polya.pdf\"\r\nContent-Type: application/pdf\r\n\r\n".utf8)
        body.append(pdf)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let uploaded = try await post("file_uploads/\(id)/send", token: token,
                                      contentType: "multipart/form-data; boundary=\(boundary)", body: body)
        guard uploaded["status"] as? String == "uploaded" else { throw NotionError.response }

        let page = try await post("pages", token: token, json: [
            "parent": ["type": "page_id", "page_id": parent],
            "properties": ["title": ["type": "title", "title": [
                ["type": "text", "text": ["content": String(title.prefix(200))]]
            ]]],
            "children": [
                ["object": "block", "type": "pdf", "pdf": [
                    "type": "file_upload", "file_upload": ["id": id]
                ]]
            ]
        ])
        guard let address = page["url"] as? String, let url = URL(string: address), url.scheme == "https" else {
            throw NotionError.response
        }
        return url
    }

    private static func post(_ path: String, token: String, json: [String: Any]) async throws -> [String: Any] {
        try await post(path, token: token, contentType: "application/json",
                       body: JSONSerialization.data(withJSONObject: json))
    }

    private static func post(_ path: String, token: String, contentType: String, body: Data) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/" + path)!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-11", forHTTPHeaderField: "Notion-Version")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw NotionError.response }
        let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            throw NotionError.http(http.statusCode, result?["message"] as? String ?? "Проверьте доступ к странице и настройки интеграции.")
        }
        guard let result else { throw NotionError.response }
        return result
    }
}
