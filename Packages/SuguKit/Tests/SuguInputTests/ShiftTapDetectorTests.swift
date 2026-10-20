import Testing
import SuguCore
import SuguInput

struct ShiftTapDetectorTests {
    @Test func aQuickShiftOnItsOwnIsATap() {
        var detector = ShiftTapDetector()
        let tap1 = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [.shift], timestamp: 1)
        #expect(!tap1)
        let tap2 = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [], timestamp: 1.2)
        #expect(tap2)
        // Caps Lock being on does not matter.
        let tap3 = detector.flagsChanged(keyCode: VirtualKey.rightShift, modifiers: [.shift, .capsLock], timestamp: 2)
        #expect(!tap3)
        let tap4 = detector.flagsChanged(keyCode: VirtualKey.rightShift, modifiers: [.capsLock], timestamp: 2.1)
        #expect(tap4)
    }

    @Test func holdsAndChordsAreNotTaps() {
        var detector = ShiftTapDetector()
        _ = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [.shift], timestamp: 1)
        let tap5 = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [], timestamp: 1 + ShiftTapDetector.maximumDuration + 0.1)
        #expect(!tap5)

        _ = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [.shift], timestamp: 3)
        detector.interrupt()
        let tap6 = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [], timestamp: 3.1)
        #expect(!tap6)

        _ = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [.shift], timestamp: 4)
        let tap7 = detector.flagsChanged(keyCode: VirtualKey.command, modifiers: [.shift, .command], timestamp: 4.05)
        #expect(!tap7)
        let tap8 = detector.flagsChanged(keyCode: VirtualKey.shift, modifiers: [], timestamp: 4.1)
        #expect(!tap8)
    }
}
