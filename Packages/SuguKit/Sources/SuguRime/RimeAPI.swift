import CRime
import CRimeShim
import Foundation

/// The librime C function table, loaded once with plugin modules linked in.
struct RimeAPI: @unchecked Sendable {
    let table: UnsafeMutablePointer<RimeApi>

    static let shared: RimeAPI = {
        sugu_rime_link_plugins()
        guard let api = rime_get_api() else { fatalError("librime is not linked") }
        return RimeAPI(table: api)
    }()

    var api: RimeApi { table.pointee }

    /// librime's `RIME_STRUCT_INIT`: `data_size` counts the bytes after itself.
    static func dataSize<T>(of _: T.Type) -> Int32 {
        Int32(MemoryLayout<T>.stride - MemoryLayout<Int32>.stride)
    }
}

/// X11 key symbols and masks librime expects in `process_key`.
enum RimeKey {
    static let backspace: Int32 = 0xFF08
    static let delete: Int32 = 0xFFFF
    static let home: Int32 = 0xFF50
    static let left: Int32 = 0xFF51
    static let right: Int32 = 0xFF53
    static let end: Int32 = 0xFF57
}

/// Keeps C strings alive for as long as librime may read them.
final class CStringPool {
    private var storage: [UnsafeMutablePointer<CChar>] = []

    func make(_ string: String) -> UnsafePointer<CChar> {
        let pointer = strdup(string)!
        storage.append(pointer)
        return UnsafePointer(pointer)
    }

    deinit { storage.forEach { free($0) } }
}
