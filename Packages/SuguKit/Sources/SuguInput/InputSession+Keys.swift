import SuguCore

extension InputSession {
    // MARK: Keys

    /// Handles one key press. Returns true when Sugu consumed it.
    public func handle(_ key: KeyInput) -> Bool {
        let handled = handleKey(key)
        if !handled {
            // The app has the key: it types the character, or moves the caret.
            lastTyped = key.isShortcut ? nil : key.printable
        }
        return handled
    }

    private func handleKey(_ key: KeyInput) -> Bool {
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
            // かな again, in Japanese with text selected, reconverts it, as
            // in Apple's Japanese input.
            if mode == .japanese, isEmpty { reconvertSelection() } else { setMode(.japanese) }
            return true
        case VirtualKey.eisu:
            setMode(.english); return true
        default:
            break
        }
        if key.modifiers.contains(.control), key.modifiers.contains(.shift), key.keyCode == VirtualKey.space {
            switchCJKMode()
            return true
        }
        if let binding = controlBinding(for: key) {
            switch binding {
            case .key(let code, let modifiers):
                return handleKey(KeyInput(keyCode: code, characters: "", modifiers: modifiers))
            case .caret(let forward):
                guard let engine = active else { return true }
                if engine.state.phase == .converting { engine.moveFocus(forward: forward) } else { engine.moveCaret(forward ? .right : .left) }
                refresh()
                return true
            }
        }
        if key.isShortcut {
            // Shortcuts belong to the app; finish the composition first.
            if !isEmpty { commitComposition() }
            return false
        }
        if key.keyCode == VirtualKey.escape, preferences.rule(for: client?.bundleIdentifier).escapeSwitchesToEnglish {
            if !isEmpty { abandonComposition() }
            setMode(.english)
            return false
        }
        if !isEmpty, let consumed = handleFunctionKey(key) { return consumed }
        // English composes only a selection being revised.
        if mode == .english, isEmpty { return false }
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
            begin(with: engine, input: input(for: key, character: character))
            return true
        }
    }

    private func typeFullWidthSpace(_ key: KeyInput) -> Bool {
        guard preferences.fullWidthSpace, !key.modifiers.contains(.shift) else { return false }
        commitText("　", reading: " ", learn: false)
        return true
    }

    private func typePunctuation(_ character: Character) {
        let previous = lastTyped ?? lastCharacterBeforeCaret()
        commitText(punctuator.output(for: character, after: previous), reading: String(character), learn: false)
    }

    /// Romaji input maps symbol keys to Japanese symbols; kana input types
    /// the kana of the physical key; pinyin passes keys through.
    func input(for key: KeyInput, character: Character) -> String {
        guard mode == .japanese else { return String(character) }
        if preferences.kanaInput {
            return KanaLayout.kana(forKeyCode: key.keyCode, shift: key.modifiers.contains(.shift), jis: key.isJISKeyboard) ?? String(character)
        }
        return preferences.japanesePunctuation.romajiInput(for: character)
    }

    // MARK: Live candidates (librime, expressions)

    /// Candidates follow every key and the first is chosen by default:
    /// Space commits it, digits pick another.
    private func handleLive(_ key: KeyInput, engine: any CompositionEngine) -> Bool {
        // An F9/F10 form stands until the composition is edited: Esc goes
        // back to the candidates, Return and Space commit the form, and
        // keys that change the composition drop it.
        if transformed != nil {
            switch key.keyCode {
            case VirtualKey.escape: transformed = nil; publish(); return true
            case VirtualKey.returnKey, VirtualKey.keypadEnter, VirtualKey.space: commitHighlighted(); return true
            case VirtualKey.delete, VirtualKey.forwardDelete, VirtualKey.home, VirtualKey.end, VirtualKey.left, VirtualKey.right,
                 VirtualKey.up, VirtualKey.down, VirtualKey.tab, VirtualKey.pageUp, VirtualKey.pageDown:
                transformed = nil
            default:
                if key.printable.map(engine.accepts) == true { transformed = nil }
            }
        }
        switch key.keyCode {
        case VirtualKey.escape: abandonComposition(); return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter: commit(engine.commitRaw()); return true
        case VirtualKey.space:
            // Space chooses a candidate; while the engine is still being set
            // up there is none yet, and the letters wait for it. Only if
            // setup failed does Space commit them as typed.
            if engine === loading, !engines.isFailing(mode) { return true }
            commitHighlighted()
            return true
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
        // Keys Sugu does not bind (F1–F5, Help) finish the composition and
        // go to the app.
        guard let character = key.printable else { commitHighlighted(); return false }
        // What the engine takes is input, even digits and operators in an
        // expression; only the rest selects or turns pages.
        if engine.accepts(character) {
            engine.insert(input(for: key, character: character))
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
            } else if key.keyCode == VirtualKey.tab {
                // With nothing to step into, Tab converts, as in Kotoeri.
                transformed = nil
                engine.convert()
                refresh()
            }
            return true
        case VirtualKey.pageUp: turnPage(by: -1); return true
        case VirtualKey.pageDown: turnPage(by: 1); return true
        case VirtualKey.home: if !converting { engine.moveCaret(.start); refresh() }; return true
        case VirtualKey.end: if !converting { engine.moveCaret(.end); refresh() }; return true
        default:
            break
        }
        guard let character = key.printable else { commitComposition(); return false }
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
                begin(with: fresh, input: input(for: key, character: character))
                return true
            }
            engine.insert(input(for: key, character: character))
            refresh()
            return true
        }
        commitComposition()
        return false
    }

    // MARK: Function keys (F6–F10)

    enum ControlBinding {
        /// Acts as this key would.
        case key(UInt16, KeyModifiers)
        /// Moves the caret, or the focused clause while converting.
        case caret(forward: Bool)
    }

    /// Control keys inside a composition, as in the text system's Emacs
    /// bindings and Apple's Japanese input method: ⌃H ⌃D delete, ⌃A ⌃E ⌃B
    /// ⌃F move, ⌃N ⌃P choose, ⌃G cancels, ⌃M commits, and ⌃J ⌃K ⌃; ⌃L ⌃:
    /// are F6–F10. ⌃[ is Escape with or without a composition, for vim.
    /// Read from the layout's characters, like the text system.
    func controlBinding(for key: KeyInput) -> ControlBinding? {
        guard key.modifiers.contains(.control), key.modifiers.isDisjoint(with: [.command, .option]),
              let character = key.charactersIgnoringModifiers.lowercased().first else { return nil }
        if character == "[" { return .key(VirtualKey.escape, []) }
        guard !isEmpty else { return nil }
        switch character {
        case "h": return .key(VirtualKey.delete, [])
        case "d": return .key(VirtualKey.forwardDelete, [])
        case "a": return .key(VirtualKey.home, [])
        case "e": return .key(VirtualKey.end, [])
        case "b": return .caret(forward: false)
        case "f": return .caret(forward: true)
        case "n": return .key(VirtualKey.tab, [])
        case "p": return .key(VirtualKey.tab, [.shift])
        case "g": return .key(VirtualKey.escape, [])
        case "m": return .key(VirtualKey.returnKey, [])
        case "j": return .key(VirtualKey.f6, [])
        case "k": return .key(VirtualKey.f7, [])
        case ";": return .key(VirtualKey.f8, [])
        case "l": return .key(VirtualKey.f9, [])
        case ":": return .key(VirtualKey.f10, [])
        default: return nil
        }
    }

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
