import SuguCore

extension InputSession {
    // MARK: Keys

    /// Handles one key press. Returns true when Sugu consumed it.
    public func handle(_ key: KeyInput) -> Bool {
        if isSecureInput { return false }
        let isUndoKey = key.modifiers.contains(.control) && key.keyCode == VirtualKey.delete
        // Undo applies only to the commit just made; any other key ends it.
        let pendingUndo = undoable
        undoable = nil
        if isUndoKey, isEmpty {
            undoable = pendingUndo
            return undoLastCommit()
        }

        switch key.keyCode {
        case VirtualKey.kana where preferences.enabledModes.contains(.japanese):
            setMode(.japanese); return true
        case VirtualKey.eisu:
            setMode(.english); return true
        default:
            break
        }
        if key.modifiers.contains(.control), key.modifiers.contains(.shift), key.keyCode == VirtualKey.space {
            switchCJKMode()
            return true
        }
        if key.isShortcut {
            // Shortcuts belong to the app; finish the composition first.
            if !isEmpty { commitComposition() }
            return false
        }
        if key.keyCode == VirtualKey.escape, preferences.rule(for: client?.bundleIdentifier).escapeSwitchesToEnglish {
            if !isEmpty { cancelComposition() }
            setMode(.english)
            return false
        }
        if !isEmpty, let consumed = handleFunctionKey(key) { return consumed }
        if mode == .english { return false }
        if key.modifiers.contains(.option) {
            // Option types the layout's symbols; finish the composition first.
            if !isEmpty { commitComposition() }
            return false
        }
        guard let engine = active, !engine.state.isEmpty else { return start(key) }
        return engine.traits.hasConversionPhase ? handleStaged(key, engine: engine) : handleLive(key, engine: engine)
    }

    // MARK: Starting a composition

    func start(_ key: KeyInput) -> Bool {
        guard let character = key.printable, !key.modifiers.contains(.numericPad) else { return false }
        switch mode {
        case .english:
            return false
        case .chinese:
            if character == ComputedCandidates.chineseNumberPrefix {
                begin(with: expression, input: String(character))
                return true
            }
            if character.isASCIILowercaseLetter {
                begin(with: engines.engine(for: .chinese) ?? loading, input: String(character))
                return true
            }
            if ChinesePunctuator.handles(character) {
                typePunctuation(character)
                return true
            }
            return false
        case .japanese:
            if key.keyCode == VirtualKey.space { return typeFullWidthSpace(key) }
            guard let engine = engines.engine(for: .japanese), engine.accepts(character) else { return false }
            begin(with: engine, input: input(for: character))
            return true
        }
    }

    private func typeFullWidthSpace(_ key: KeyInput) -> Bool {
        guard preferences.fullWidthSpace, !key.modifiers.contains(.shift) else { return false }
        commitText("　", reading: " ", learn: false)
        return true
    }

    private func typePunctuation(_ character: Character) {
        let previous = lastCharacterBeforeCaret()
        commitText(punctuator.output(for: character, after: previous), reading: String(character), learn: false)
    }

    /// Romaji input maps symbol keys to Japanese symbols; kana input and
    /// pinyin pass keys through.
    func input(for character: Character) -> String {
        guard mode == .japanese, !preferences.kanaInput else { return String(character) }
        return preferences.japanesePunctuation.romajiInput(for: character)
    }

    // MARK: Live candidates (librime, expressions)

    /// Candidates follow every key and the first is chosen by default:
    /// Space commits it, digits pick another.
    private func handleLive(_ key: KeyInput, engine: any CompositionEngine) -> Bool {
        switch key.keyCode {
        case VirtualKey.escape: cancelComposition(); return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter: commit(engine.commitRaw()); return true
        case VirtualKey.space: commitHighlighted(); return true
        case VirtualKey.delete: engine.deleteBackward(); refresh(); return true
        case VirtualKey.forwardDelete: engine.deleteForward(); refresh(); return true
        case VirtualKey.home: engine.moveCaret(.start); refresh(); return true
        case VirtualKey.end: engine.moveCaret(.end); refresh(); return true
        case VirtualKey.pageUp: turnPage(by: -1); return true
        case VirtualKey.pageDown: turnPage(by: 1); return true
        case VirtualKey.tab: moveHighlight(by: key.modifiers.contains(.shift) ? -1 : 1); return true
        case VirtualKey.up: verticalLayout ? moveHighlight(by: -1) : turnPage(by: -1); return true
        case VirtualKey.down: verticalLayout ? moveHighlight(by: 1) : turnPage(by: 1); return true
        case VirtualKey.left:
            if verticalLayout { engine.moveCaret(.left); refresh() } else { moveHighlight(by: -1) }
            return true
        case VirtualKey.right:
            if verticalLayout { engine.moveCaret(.right); refresh() } else { moveHighlight(by: 1) }
            return true
        default:
            break
        }
        guard let character = key.printable else { return true }
        // What the engine takes is input, even digits and operators in an
        // expression; only the rest selects or turns pages.
        if engine.accepts(character) {
            engine.insert(input(for: character))
            refresh()
            return true
        }
        if key.modifiers.contains(.numericPad) {
            commitComposition()
            return false
        }
        if let digit = character.selectionDigit {
            selectOnPage(digit)
            return true
        }
        if character == "-" { turnPage(by: -1); return true }
        if character == "=" { turnPage(by: 1); return true }
        if mode == .chinese, ChinesePunctuator.handles(character) {
            commitHighlighted()
            typePunctuation(character)
            return true
        }
        // Anything else: finish the composition and let the key through.
        commitHighlighted()
        return false
    }

    // MARK: Staged conversion (AzooKey)

    /// Typing shows predictions; Space converts, then moves through the
    /// focused clause's candidates; arrows move and resize clauses.
    private func handleStaged(_ key: KeyInput, engine: any CompositionEngine) -> Bool {
        let converting = engine.state.phase == .converting

        switch key.keyCode {
        case VirtualKey.escape:
            if transformed != nil { transformed = nil; publish() } else if converting { engine.cancelConversion(); refresh() } else { cancelComposition() }
            return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            if transformed != nil || (list.highlight != nil && (!converting || highlightsOwnCandidate)) {
                commitHighlighted()
            } else {
                commit(engine.commitConverted())
            }
            return true
        case VirtualKey.space:
            transformed = nil
            if converting {
                showsConversionWindow = true
                moveHighlight(by: key.modifiers.contains(.shift) ? -1 : 1)
            } else {
                list.highlight = nil
                engine.convert()
                refresh()
            }
            return true
        case VirtualKey.delete:
            transformed = nil
            if converting { engine.cancelConversion() } else { engine.deleteBackward() }
            refresh()
            return true
        case VirtualKey.forwardDelete:
            transformed = nil
            engine.deleteForward(); refresh(); return true
        case VirtualKey.left, VirtualKey.right:
            let forward = key.keyCode == VirtualKey.right
            if converting {
                if key.modifiers.contains(.shift) { engine.resizeFocus(by: forward ? 1 : -1) } else { engine.moveFocus(forward: forward) }
            } else {
                engine.moveCaret(forward ? .right : .left)
            }
            refresh()
            return true
        case VirtualKey.up, VirtualKey.down, VirtualKey.tab:
            let backward = key.keyCode == VirtualKey.up || (key.keyCode == VirtualKey.tab && key.modifiers.contains(.shift))
            if converting {
                showsConversionWindow = true
                moveHighlight(by: backward ? -1 : 1)
            } else if !list.candidates.isEmpty {
                // Step into the predictions.
                if list.highlight == nil { list.setHighlight(backward ? list.candidates.count - 1 : 0); publish() } else { moveHighlight(by: backward ? -1 : 1) }
            }
            return true
        case VirtualKey.pageUp: turnPage(by: -1); return true
        case VirtualKey.pageDown: turnPage(by: 1); return true
        case VirtualKey.home: if !converting { engine.moveCaret(.start); refresh() }; return true
        case VirtualKey.end: if !converting { engine.moveCaret(.end); refresh() }; return true
        default:
            break
        }
        guard let character = key.printable else { return true }
        // Numpad keys type numbers; they never select.
        if key.modifiers.contains(.numericPad) {
            commitComposition()
            return false
        }
        let windowShown = converting ? showsConversionWindow : list.highlight != nil
        if windowShown, let digit = character.selectionDigit {
            selectOnPage(digit)
            return true
        }
        if engine.accepts(character) {
            if converting || transformed != nil || list.highlight != nil {
                // Typing on after a choice commits it and starts afresh.
                commitComposition()
                guard let fresh = engines.engine(for: mode) else { return true }
                begin(with: fresh, input: input(for: character))
                return true
            }
            engine.insert(input(for: character))
            refresh()
            return true
        }
        commitComposition()
        return false
    }

    // MARK: Function keys (F6–F10)

    private func handleFunctionKey(_ key: KeyInput) -> Bool? {
        guard let state = active?.state else { return nil }
        let kana = state.reading
        let typed = state.typedText
        let text: String?
        switch key.keyCode {
        case VirtualKey.f6: text = mode == .japanese ? WidthConversion.hiragana(kana) : nil
        case VirtualKey.f7: text = mode == .japanese ? WidthConversion.katakana(kana) : nil
        case VirtualKey.f8: text = mode == .japanese ? WidthConversion.halfWidthKatakana(kana) : nil
        case VirtualKey.f9: text = WidthConversion.fullWidth(typed)
        case VirtualKey.f10: text = typed
        default: return nil
        }
        guard let text else { return nil }
        transformed = text
        list.highlight = nil
        publish()
        return true
    }
}

fileprivate extension Character {
    /// 1–9 and 0 as candidate selection keys.
    var selectionDigit: Int? {
        guard isASCIIDigitCharacter else { return nil }
        return asciiDigitValue
    }
}
