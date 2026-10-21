import AppKit
import Testing

@MainActor
@Suite struct ControlHandlerTests {
    @Test func aControlsActionReachesItsHandler() {
        let control = NSSegmentedControl(labels: ["Vertical", "Horizontal"], trackingMode: .selectOne, target: nil, action: nil)
        var selected: Int?
        ControlHandler.attach({ selected = ($0 as? NSSegmentedControl)?.selectedSegment }, to: control)
        control.selectedSegment = 1
        #expect(control.sendAction(control.action, to: control.target))
        #expect(selected == 1)
    }
}
