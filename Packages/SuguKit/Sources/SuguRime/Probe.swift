import CRime
import CRimeShim

public func rimeVersion() -> String {
    sugu_rime_link_plugins()
    guard let api = rime_get_api(), let version = api.pointee.get_version?() else { return "" }
    return String(cString: version)
}
