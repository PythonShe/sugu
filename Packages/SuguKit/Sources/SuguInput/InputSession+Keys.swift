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
        // 英数 and かな keep the commit they may retype.
        let pendingRetype = retypable
        retypable = nil
        if isUndoKey, isEmpty {
            undoable = pendingUndo
            return undoLastCommit()
        }

        switch key.keyCode {
        case VirtualKey.kana where preferences.enabledModes.contains(.japanese):
            // かな again, in Japanese with text selected, reconverts it, as
            // in Apple's Japanese input.
            retypable = pendingRetype
            if mode == .japanese, isEmpty { reconvertSelection() } else { setMode(.japanese) }
            return true
        case VirtualKey.eisu:
            retypable = pendingRetype
            setMode(.english); return true
        default:
            break
        }
        if key.modifiers.contains(.control), key.modifiers.contains(.shift), key.keyCode == VirtualKey.space {
            switchCJKMode()
            return true
        }
        // ⌃⇧R reconverts the selection, as in Apple's Japanese input.
        if isEmpty, key.modifiers.isSuperset(of: [.control, .shift]), key.modifiers.isDisjoint(with: [.command, .option]),
           key.charactersIgnoringModifiers.lowercased() == "r", reconvertSelection() {
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
            case .resize(let delta):
                guard let engine = active, engine.state.phase == .converting else { return true }
                engine.resizeFocus(by: delta)
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
        // ⇧⌫ on a learned candidate forgets it; elsewhere it is ⌫.
        if key.keyCode == VirtualKey.delete, key.modifiers.contains(.shift), forgetHighlighted() { return true }
        switch composition(of: engine) {
        case .live: return handleLive(key, engine: engine)
        case .staged: return handleStaged(key, engine: engine)
        case .sentence: return handleSentence(key, engine: engine)
        }
    }

    // MARK: Starting a composition

    func start(_ key: KeyInput) -> Bool {
        guard let character = key.printable, !key.modifiers.contains(.numericPad) else { return false }
        switch mode {
        case .english:
            return false
        case .chinese:
            if typesZhuyin {
                guard let typed = zhuyinKey(for: character), Zhuyin.keyboard[typed] != nil else { break }
                begin(with: engines.engine(for: .chinese) ?? loading, input: String(typed))
                return true
            }
            if character == ComputedCandidates.chineseNumberPrefix {
                begin(with: expression, input: String(character))
                return true
            }
            if character.isASCIILowercaseLetter {
                begin(with: engines.engine(for: .chinese) ?? loading, input: String(character))
                return true
            }
        case .japanese:
            if key.keyCode == VirtualKey.space { return typeSpace(key) }
            guard let engine = engines.engine(for: .japanese), engine.accepts(character) else { return false }
            begin(with: engine, input: input(for: key, character: character))
            return true
        }
        if ChinesePunctuator.handles(punctuation(for: character)) {
            typePunctuation(punctuation(for: character))
            return true
        }
        return false
    }

    /// Zhuyin types , . on their own keys as symbols; with Shift they are
    /// the punctuation, as in the Taiwanese input methods.
    private func punctuation(for character: Character) -> Character {
        guard typesZhuyin else { return character }
        switch character {
        case "<": return ","
        case ">": return "."
        default: return character
        }
    }

    /// Space types the width set for Japanese and Shift-Space the other, as
    /// in Apple's and Google's Japanese input; a half-width one is the app's.
    private func typeSpace(_ key: KeyInput) -> Bool {
        guard preferences.fullWidthSpace != key.modifiers.contains(.shift) else { return false }
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
            // The ね and る keys' marks follow the punctuation style too.
            switch KanaLayout.kana(forKeyCode: key.keyCode, shift: key.modifiers.contains(.shift), jis: key.isJISKeyboard) {
            case "、": return preferences.japanesePunctuation.comma
            case "。": return preferences.japanesePunctuation.period
            case let kana?: return kana
            case nil: return String(character)
            }
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
                guard let character = key.printable else { break }
                if engine.accepts(character) {
                    transformed = nil
                } else {
                    // A digit or punctuation follows the form, not a candidate.
                    commitHighlighted()
                    return handleKey(key)
                }
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
        // [ and ] take the first or last character of the highlighted word
        // (以词定字), as Sogou and Microsoft Pinyin do; a numeral or date
        // made from the input is no word to take one from.
        if mode == .chinese, character == "[" || character == "]", let candidate = list.highlighted, candidate.source != .computed,
           case let word = candidate.text, word.count > 1, word.allSatisfy(\.isHan),
           let chosen = character == "[" ? word.first : word.last {
            commitWhole(String(chosen))
            return true
        }
        if mode == .chinese, ChinesePunctuator.handles(character) {
            commitHighlighted()
            typePunctuation(character)
            return true
        }
        // Anything else: finish the composition and let the key through.
        commitHighlighted()
        return false
    }

    // MARK: Sentence (Zhuyin)

    /// How the composition in `engine` takes keys; letters typed while
    /// librime is set up wait as Zhuyin keys when Zhuyin is in use.
    func composition(of engine: any CompositionEngine) -> EngineTraits.Composition {
        engine === loading && typesZhuyin ? .sentence : engine.traits.composition
    }

    var typesZhuyin: Bool { mode == .chinese && preferences.chineseKeyboard == .zhuyin }

    /// The standard layout's key for a key of the Zhuyin layout in use,
    /// which the engines read; nil for a key with no symbol or tone.
    func zhuyinKey(for character: Character) -> Character? {
        Zhuyin.standardKeys(for: preferences.zhuyinLayout)[character]
    }

    /// The sentence stays converted as syllables are typed. Space ends a
    /// syllable with the first tone, and between syllables opens the
    /// candidate window on the words at the caret, as ↓ does; there digits
    /// choose and Return takes the highlighted word.
    private func handleSentence(_ key: KeyInput, engine: any CompositionEngine) -> Bool {
        if engine.state.phase == .converting {
            switch key.keyCode {
            case VirtualKey.escape, VirtualKey.delete: engine.cancelConversion(); refresh(); return true
            case VirtualKey.returnKey, VirtualKey.keypadEnter: commitHighlighted(); return true
            case VirtualKey.space: turnPage(by: key.modifiers.contains(.shift) ? -1 : 1); return true
            case VirtualKey.pageUp: turnPage(by: -1); return true
            case VirtualKey.pageDown: turnPage(by: 1); return true
            case VirtualKey.tab: moveHighlight(by: key.modifiers.contains(.shift) ? -1 : 1); return true
            case VirtualKey.up: verticalLayout ? moveHighlight(by: -1) : turnPage(by: -1); return true
            case VirtualKey.down: verticalLayout ? moveHighlight(by: 1) : turnPage(by: 1); return true
            case VirtualKey.left, VirtualKey.right:
                let forward = key.keyCode == VirtualKey.right
                if verticalLayout {
                    engine.cancelConversion()
                    engine.moveCaret(forward ? .right : .left)
                    refresh()
                } else {
                    moveHighlight(by: forward ? 1 : -1)
                }
                return true
            default:
                break
            }
            if let character = key.printable, !key.modifiers.contains(.numericPad), let digit = character.selectionDigit {
                selectOnPage(digit)
                return true
            }
            // Anything else goes on with the sentence.
            engine.cancelConversion()
        }
        switch key.keyCode {
        case VirtualKey.escape:
            // Esc takes the half-typed syllable, then the sentence.
            if engine.clearPending() { refresh() } else { abandonComposition() }
            return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter: commit(engine.commitConverted() ?? engine.commitRaw()); return true
        case VirtualKey.space:
            if engine.accepts(" ") { engine.insert(" ") } else { engine.convert() }
            refresh()
            return true
        case VirtualKey.down: engine.convert(); refresh(); return true
        case VirtualKey.delete: engine.deleteBackward(); refresh(); return true
        case VirtualKey.forwardDelete: engine.deleteForward(); refresh(); return true
        case VirtualKey.home: engine.moveCaret(.start); refresh(); return true
        case VirtualKey.end: engine.moveCaret(.end); refresh(); return true
        case VirtualKey.left: engine.moveCaret(.left); refresh(); return true
        case VirtualKey.right: engine.moveCaret(.right); refresh(); return true
        case VirtualKey.up, VirtualKey.tab, VirtualKey.pageUp, VirtualKey.pageDown: return true
        default:
            break
        }
        guard let character = key.printable, !key.modifiers.contains(.numericPad) else {
            commitComposition()
            return false
        }
        if let typed = zhuyinKey(for: character) {
            // A tone with no syllable to take it does nothing.
            if engine.accepts(typed) {
                engine.insert(String(typed))
                refresh()
            }
            return true
        }
        // Punctuation, and letters typed with Shift, join the sentence, as
        // in the Taiwanese input methods; anything else goes to the app.
        let mark = punctuation(for: character)
        let letter = key.modifiers.contains(.shift) && character.isASCIILetter
        guard ChinesePunctuator.handles(mark) || letter else {
            commitComposition()
            return false
        }
        let state = engine.state
        let previous = state.markedText.prefix(state.caret).last ?? lastTyped ?? lastCharacterBeforeCaret()
        let text = letter ? String(character) : punctuator.output(for: mark, after: previous)
        if engine.insertLiteral(text) {
            refresh()
            return true
        }
        commitComposition()
        guard !letter else { return false }
        commitText(text, reading: String(mark), learn: false)
        return true
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
        if !converting, transformed == nil, list.highlight == nil, let symbol = zSymbol(after: engine.state, for: character) {
            engine.deleteBackward()
            engine.insert(symbol)
            refresh()
            return true
        }
        if engine.accepts(character) {
            if converting || transformed != nil || list.highlight != nil {
                // Typing on after a choice commits it and starts afresh; a
                // mark that ends a phrase goes with it, as in Google's and
                // ATOK's Japanese input, rather than waiting on its own.
                let typed = input(for: key, character: character)
                commitComposition()
                let punctuation = preferences.japanesePunctuation
                if [punctuation.comma, punctuation.period, "！", "？"].contains(typed) {
                    commitText(typed, reading: typed, learn: false)
                    return true
                }
                guard let fresh = engines.engine(for: mode) else { return true }
                begin(with: fresh, input: typed)
                return true
            }
            engine.insert(input(for: key, character: character))
            refresh()
            return true
        }
        commitComposition()
        return false
    }

    /// The symbol a key types after a z not yet kana, in romaji.
    private func zSymbol(after state: CompositionState, for character: Character) -> String? {
        guard mode == .japanese, !preferences.kanaInput, let symbol = JapanesePunctuationStyle.zSymbols[character],
              state.markedText.prefix(state.caret).last == "z" else { return nil }
        return symbol
    }

    // MARK: Function keys (F6–F10)

    enum ControlBinding {
        /// Acts as this key would.
        case key(UInt16, KeyModifiers)
        /// Moves the caret, or the focused clause while converting.
        case caret(forward: Bool)
        /// Shrinks or grows the focused clause while converting.
        case resize(Int)
    }

    /// Control keys inside a composition, as in the text system's Emacs
    /// bindings and Apple's Japanese input method: ⌃H ⌃D delete, ⌃A ⌃E ⌃B
    /// ⌃F move, ⌃N ⌃P choose, ⌃G cancels, ⌃M commits, ⌃I ⌃O shrink and grow
    /// the clause, and ⌃J ⌃K ⌃; ⌃L ⌃: are F6–F10. ⌃[ is Escape with or
    /// without a composition, for vim.
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
        case "i": return .resize(-1)
        case "o": return .resize(1)
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
        case VirtualKey.f9: text = latinForm(of: typed, after: transformed, width: WidthConversion.fullWidth)
        case VirtualKey.f10: text = latinForm(of: typed, after: transformed) { $0 }
        default: return nil
        }
        // F6–F8 (and ⌃J ⌃K ⌃;) have no form in Chinese, nor F9 and F10
        // in Zhuyin, whose keys are not its text; they do nothing.
        guard let text, active.map(composition(of:)) != .sentence else { return true }
        transformed = text
        list.highlight = nil
        publish()
        return true
    }
}

extension InputSession {
    /// The letters as typed, then, as the same key comes again, in capitals,
    /// capitalized and in lower case, as Apple's, Google's and Microsoft's
    /// input methods cycle F9 and F10.
    fileprivate func latinForm(of typed: String, after shown: String?, width: (String) -> String) -> String {
        var forms: [String] = []
        for form in [typed.lowercased(), typed.uppercased(), typed.prefix(1).uppercased() + typed.dropFirst().lowercased()] where !forms.contains(form) {
            forms.append(form)
        }
        guard let shown, let index = forms.firstIndex(where: { width($0) == shown }) ?? (shown == width(typed) ? 0 : nil) else { return width(typed) }
        return width(forms[(index + 1) % forms.count])
    }
}

fileprivate extension Character {
    /// 1–9 and 0 as candidate selection keys.
    var selectionDigit: Int? {
        guard isASCIIDigitCharacter else { return nil }
        return asciiDigitValue
    }
}
