# EverPlay in-game menu: a small draggable button that opens quick actions (quick save/load,
# rollback, skip, auto, hide interface, ...) and a variable editor for cheating.
#
# EverPlay's iOS runtimes compile this file into renpy/common, so it runs in every game's
# store. Games may define variables named like builtins (seen: "sorted"), so the code below
# only uses builtins through _everplay_b and keeps every name it defines under _everplay.

init -1500 python:

    # Python 2 first: there, "builtins" is the future package's wrapper with its own int type.
    try:
        import __builtin__ as _everplay_b
    except ImportError:
        import builtins as _everplay_b

    try:
        _everplay_text_types = (_everplay_b.str, _everplay_b.unicode)
    except AttributeError:
        _everplay_text_types = (_everplay_b.str,)
    try:
        _everplay_number_types = (_everplay_b.int, _everplay_b.long, _everplay_b.float)
    except AttributeError:
        _everplay_number_types = (_everplay_b.int, _everplay_b.float)

    _everplay_limit = 150

    def _everplay_enabled():
        import os
        return os.environ.get("EVERPLAY_MENU", "1") != "0"

    def _everplay_scale(value):
        return _everplay_b.int(value * config.screen_height / 720.0)

    def _everplay_kind(value):
        if _everplay_b.isinstance(value, _everplay_b.bool):
            return "bool"
        if _everplay_b.isinstance(value, _everplay_number_types):
            return "number"
        if _everplay_b.isinstance(value, _everplay_text_types):
            return "text"
        return None

    def _everplay_quote(text):
        # Shown as plain text: no Ren'Py substitutions or text tags from game data.
        return text.replace("[", "[[").replace("{", "{{")

    def _everplay_show(value):
        kind = _everplay_kind(value)
        if kind == "text":
            text = value if _everplay_b.len(value) <= 60 else value[:57] + u"..."
            return u'"%s"' % text
        if kind == "number" and _everplay_b.isinstance(value, _everplay_b.float):
            return u"%g" % value
        return u"%s" % (value,)

    def _everplay_get(container, key, item):
        if item:
            return container[key]
        return _everplay_b.getattr(container, key)

    def _everplay_set(container, key, item, value):
        if item:
            container[key] = value
        else:
            _everplay_b.setattr(container, key, value)
        renpy.restart_interaction()

    def _everplay_add(container, key, item, delta):
        _everplay_set(container, key, item, _everplay_get(container, key, item) + delta)

    def _everplay_toggle(container, key, item):
        _everplay_set(container, key, item, not _everplay_get(container, key, item))

    def _everplay_apply(container, key, item, text):
        old = _everplay_get(container, key, item)
        kind = _everplay_kind(old)
        text = text.strip() if kind != "text" else text
        try:
            if kind == "bool":
                new = text.lower() in ("1", "true", "yes", "on", "an", "ja")
            elif _everplay_b.isinstance(old, _everplay_b.float):
                new = _everplay_b.float(text.replace(",", "."))
            elif kind == "number":
                new = _everplay_b.int(_everplay_b.float(text.replace(",", ".")))
            else:
                new = text
        except ValueError:
            renpy.notify("Enter a number")
            return
        _everplay_set(container, key, item, new)

    def _everplay_simple_items(name, value):
        """Entries (label, container, key, item) for a store variable and one level inside it."""
        kind = _everplay_kind(value)
        if kind is not None:
            return [(name, store, name, False)]
        found = []
        if _everplay_b.isinstance(value, _everplay_b.dict):
            keys = [k for k in value.keys() if _everplay_b.isinstance(k, _everplay_text_types)]
            for key in _everplay_b.sorted(keys)[:200]:
                if _everplay_kind(value[key]) is not None:
                    found.append((u'%s["%s"]' % (name, key), value, key, True))
            return found
        module = _everplay_b.getattr(_everplay_b.type(value), "__module__", "") or ""
        if module.startswith("store") and _everplay_b.hasattr(value, "__dict__") and not _everplay_b.isinstance(value, _everplay_b.type):
            try:
                fields = _everplay_b.vars(value)
            except TypeError:
                return found
            for attribute in _everplay_b.sorted(fields):
                if attribute.startswith("_"):
                    continue
                if _everplay_kind(fields[attribute]) is not None:
                    found.append((u"%s.%s" % (name, attribute), value, attribute, False))
        return found

    def _everplay_entries(query, everything):
        namespace = store.__dict__
        names = None
        if not everything:
            try:
                import renpy.python as _everplay_python
                names = _everplay_python.store_dicts["store"].ever_been_changed
            except Exception:
                names = None
        candidates = namespace.keys() if names is None else [n for n in names if n in namespace]
        query = (query or u"").strip().lower()
        by_value = query.startswith("=")
        if by_value:
            query = query[1:].strip()
        entries = []
        for name in _everplay_b.sorted(candidates):
            if name.startswith("_") or name in ("config", "persistent", "style", "gui", "build", "preferences"):
                continue
            value = namespace[name]
            if _everplay_b.callable(value) and not _everplay_b.hasattr(value, "__dict__"):
                continue
            for entry in _everplay_simple_items(name, value):
                if query:
                    if by_value:
                        shown = (u"%s" % (_everplay_get(entry[1], entry[2], entry[3]),)).lower()
                        if shown != query:
                            continue
                    elif query not in entry[0].lower():
                        continue
                entries.append(entry)
        return entries

    def _everplay_unlock():
        labels = images = 0
        seen = persistent._seen_ever
        for label in renpy.get_all_labels():
            if not label.startswith("_"):
                seen[label] = True
                labels += 1
        shown = persistent._seen_images
        for name in renpy.list_images():
            shown[_everplay_b.tuple(name.split())] = True
            images += 1
        renpy.save_persistent()
        renpy.notify("Unlocked %d scenes and %d images" % (labels, images))

    def _everplay_console():
        config.console = True
        _console.enter()

    def _everplay_button_pos():
        size = _everplay_scale(64)
        position = persistent._everplay_button
        if not position:
            return (_everplay_scale(14), _everplay_scale(14))
        x = _everplay_b.max(0, _everplay_b.min(_everplay_b.int(position[0]), config.screen_width - size))
        y = _everplay_b.max(0, _everplay_b.min(_everplay_b.int(position[1]), config.screen_height - size))
        return (x, y)

    def _everplay_dragged(drags, drop):
        persistent._everplay_button = (drags[0].x, drags[0].y)
        return None

    def _everplay_button_home():
        persistent._everplay_button = None
        renpy.restart_interaction()

    def _everplay_menu_actions():
        return [
            ("Quick save", QuickSave()),
            ("Quick load", QuickLoad()),
            ("Rollback", Rollback()),
            ("Skip", Skip()),
            ("Skip unseen", Preference("skip", "toggle")),
            ("Auto", Preference("auto-forward", "toggle")),
            ("Hide UI", [Hide("_everplay_menu"), HideInterface()]),
            ("Instant text", Preference("text speed", 0)),
            ("Save", [Hide("_everplay_menu"), ShowMenu("save")]),
            ("Load", [Hide("_everplay_menu"), ShowMenu("load")]),
            ("Settings", [Hide("_everplay_menu"), ShowMenu("preferences")]),
            ("Variables", Show("_everplay_cheats")),
            ("Console", [Hide("_everplay_menu"), Function(_everplay_console)]),
            ("Unlock gallery", Confirm("Mark every scene and image as seen? Galleries and replays that check this unlock.",
                                       Function(_everplay_unlock))),
            (("Original text", ToggleField(persistent, "_everplay_show_original", True, None)) if _everplay_translation_on()
             else ("Button home", Function(_everplay_button_home))),
            ("Main menu", [Hide("_everplay_menu"), MainMenu()]),
        ]

    # Machine translation (EVERPLAY_TRANSLATE=1): dialogue and choices go through EverPlay's
    # EverPlayTranslator (Swift, reached with pyobjus), which caches every line per game.
    _everplay_translation = {"checked": False, "native": None, "backend": None, "previous": None}

    def _everplay_translation_on():
        import os
        return os.environ.get("EVERPLAY_TRANSLATE") == "1"

    def _everplay_from_native(value):
        if value is None:
            return u""
        if _everplay_b.hasattr(value, "UTF8String"):
            value = value.UTF8String()
        if _everplay_b.isinstance(value, _everplay_b.bytes):
            value = value.decode("utf-8", "replace")
        return value

    def _everplay_to_native(text):
        if _everplay_b.str is _everplay_b.bytes and not _everplay_b.isinstance(text, _everplay_b.bytes):
            return text.encode("utf-8")  # Python 2: pyobjus takes UTF-8 byte strings
        return text

    def _everplay_bridge(kind, text):
        """POSTs to EverPlay's loopback endpoint (RuntimeBridge.swift); None when it is not there."""
        import os
        port = os.environ.get("EVERPLAY_BRIDGE_PORT")
        token = os.environ.get("EVERPLAY_BRIDGE_TOKEN")
        if not port or not token:
            return None
        try:
            import http.client as _everplay_http
        except ImportError:
            import httplib as _everplay_http
        connection = _everplay_http.HTTPConnection("127.0.0.1", _everplay_b.int(port), timeout=10)
        try:
            connection.request("POST", "/%s/%s" % (token, kind), text.encode("utf-8"),
                               {"Content-Type": "text/plain; charset=utf-8"})
            return connection.getresponse().read().decode("utf-8")
        finally:
            connection.close()

    def _everplay_backend(kind, text):
        # kind: "translate" (may wait briefly), "cached" (never waits) or "prefetch".
        if _everplay_translation["backend"] is not None:
            return _everplay_translation["backend"](kind, text)
        reply = _everplay_bridge(kind, text)
        if reply is not None:
            return reply
        if not _everplay_translation["checked"]:
            _everplay_translation["checked"] = True
            try:
                from pyobjus import autoclass, objc_str
                _everplay_translation["native"] = (autoclass("EverPlayTranslator"), objc_str)
            except Exception as error:
                print("EverPlay: translation unavailable (%r)" % (error,))
        native = _everplay_translation["native"]
        if native is None:
            return u""
        translator, objc_str = native
        value = objc_str(_everplay_to_native(text))
        if kind == "prefetch":
            translator.prefetch_(value)
            return u""
        if kind == "translate":
            return _everplay_from_native(translator.translate_(value))
        return _everplay_from_native(translator.cached_(value))

    def _everplay_upcoming(limit=12):
        """Dialogue and choices that follow the current statement, to translate ahead."""
        texts = []
        try:
            import renpy.game as _everplay_game
            node = _everplay_game.script.lookup(_everplay_game.context().current)
            steps = 0
            while node is not None and steps < 80 and _everplay_b.len(texts) < limit:
                node = _everplay_b.getattr(node, "next", None)
                steps += 1
                what = _everplay_b.getattr(node, "what", None)
                if _everplay_b.isinstance(what, _everplay_text_types):
                    texts.append(what)
                for item in _everplay_b.getattr(node, "items", None) or []:
                    if item and _everplay_b.isinstance(item[0], _everplay_text_types):
                        texts.append(item[0])
        except Exception:
            pass
        return texts

    def _everplay_translate_filter(text):
        previous = _everplay_translation["previous"]
        if previous is not None:
            text = previous(text)
        if persistent._everplay_show_original or not text or not _everplay_b.isinstance(text, _everplay_text_types):
            return text
        try:
            upcoming = _everplay_upcoming()
            if upcoming:
                _everplay_backend("prefetch", u"\x1e".join(upcoming))
            skipping = renpy.is_skipping() if _everplay_b.hasattr(renpy, "is_skipping") else config.skipping
            translated = _everplay_backend("cached" if skipping else "translate", text)
        except Exception as error:
            print("EverPlay: translation failed (%r)" % (error,))
            return text
        return translated or text

init 1999 python:
    # Always-shown screens stay visible on splash screens, the main menu and the save/load
    # screens, where Ren'Py hides overlay screens (suppress_overlay).
    if _everplay_enabled():
        _everplay_shown = _everplay_b.getattr(config, "always_shown_screens", None)
        if _everplay_shown is None:
            _everplay_shown = config.overlay_screens
        if "_everplay_overlay" not in _everplay_shown:
            _everplay_shown.append("_everplay_overlay")
    # Image cache (decoded images in memory; their textures use the same memory on iPhone).
    # Ren'Py keeps up to 400 MB on every platform; EverPlay passes a limit that fits the device.
    def _everplay_limit_image_cache():
        import os
        try:
            limit = _everplay_b.int(os.environ.get("EVERPLAY_IMAGE_CACHE_MB", "0"))
        except ValueError:
            return
        if limit <= 0:
            return
        if config.image_cache_size is not None:
            current = 2 * config.image_cache_size * config.screen_width * config.screen_height * 4 // (1024 * 1024)
        else:
            current = config.image_cache_size_mb or 0
        if current > limit:
            config.image_cache_size = None
            config.image_cache_size_mb = limit
            print("EverPlay: image cache limited to %d MB (game asked for %d MB)" % (limit, current))

    _everplay_limit_image_cache()
    if _everplay_translation_on() and config.say_menu_text_filter is not _everplay_translate_filter:
        _everplay_translation["previous"] = config.say_menu_text_filter
        config.say_menu_text_filter = _everplay_translate_filter

screen _everplay_overlay():
    zorder 1900
    if not renpy.get_screen("_everplay_menu") and not renpy.get_screen("_everplay_cheats") and not renpy.get_screen("_touch_keyboard"):
        $ s = _everplay_scale
        drag:
            drag_name "_everplay_button"
            draggable True
            drag_offscreen False
            pos _everplay_button_pos()
            dragged _everplay_dragged
            clicked Show("_everplay_menu")
            frame:
                background Solid("#14161ca8")
                xysize (s(64), s(64))
                padding (s(16), s(19))
                vbox:
                    spacing s(5)
                    add Solid("#ffffffd8") xysize (s(32), s(4))
                    add Solid("#ffffffd8") xysize (s(32), s(4))
                    add Solid("#ffffffd8") xysize (s(32), s(4))

screen _everplay_menu():
    modal True
    zorder 2000
    key "game_menu" action Hide("_everplay_menu")
    $ s = _everplay_scale
    $ gap = s(10)
    $ width = _everplay_b.int(config.screen_width * 0.9)
    $ cell = (width - 2 * s(22) - 3 * gap) // 4
    add Solid("#05060acc")
    frame:
        background Solid("#16181ff2")
        xalign 0.5
        yalign 0.5
        xsize width
        padding (s(22), s(18))
        vbox:
            spacing s(14)
            fixed:
                ysize s(44)
                text "EverPlay" size s(30) color "#ffffff" bold True yalign 0.5 font "DejaVuSans.ttf"
                textbutton "Close":
                    xalign 1.0
                    yalign 0.5
                    action Hide("_everplay_menu")
                    text_size s(24)
                    text_font "DejaVuSans.ttf"
                    text_color "#b8b4ff"
                    text_hover_color "#ffffff"
            grid 4 4:
                spacing gap
                for label, action in _everplay_menu_actions():
                    textbutton label:
                        action action
                        xysize (cell, s(68))
                        background Solid("#262a36")
                        hover_background Solid("#3a3f52")
                        selected_background Solid("#5a55c8")
                        selected_hover_background Solid("#6b66d6")
                        insensitive_background Solid("#1b1d24")
                        text_size s(23)
                        text_font "DejaVuSans.ttf"
                        text_color "#ffffff"
                        text_insensitive_color "#6b6f7b"
                        text_xalign 0.5
                        text_yalign 0.5
                        text_text_align 0.5

screen _everplay_cheats():
    modal True
    zorder 2050
    default query = ""
    default everything = False
    key "game_menu" action Hide("_everplay_cheats")
    $ s = _everplay_scale
    $ entries = _everplay_entries(query, everything)
    $ name_width = _everplay_b.int(config.screen_width * 0.24)
    $ value_width = _everplay_b.int(config.screen_width * 0.15)
    add Solid("#05060af2")
    frame:
        background Solid("#16181f")
        xalign 0.5
        yalign 0.5
        xsize _everplay_b.int(config.screen_width * 0.96)
        ysize _everplay_b.int(config.screen_height * 0.94)
        padding (s(18), s(14))
        vbox:
            spacing s(10)
            hbox:
                spacing s(12)
                text "Variables" size s(28) color "#ffffff" bold True yalign 0.5 font "DejaVuSans.ttf"
                frame:
                    background Solid("#262a36")
                    xsize s(380)
                    ysize s(50)
                    padding (s(12), s(8))
                    yalign 0.5
                    input value ScreenVariableInputValue("query") size s(23) color "#ffffff" yalign 0.5 font "DejaVuSans.ttf"
                textbutton ("All variables" if everything else "Changed by the game"):
                    action ToggleScreenVariable("everything")
                    background Solid("#262a36")
                    hover_background Solid("#3a3f52")
                    padding (s(14), s(10))
                    text_size s(20)
                    text_font "DejaVuSans.ttf"
                    text_color "#ffffff"
                    yalign 0.5
                textbutton "Close":
                    action Hide("_everplay_cheats")
                    padding (s(14), s(10))
                    text_size s(22)
                    text_font "DejaVuSans.ttf"
                    text_color "#b8b4ff"
                    text_hover_color "#ffffff"
                    yalign 0.5
            text "Tap the search field and type a name, or =value (for example =250) to find a variable by its value.":
                size s(17)
                font "DejaVuSans.ttf"
                color "#8f93a3"
            if _everplay_b.len(entries) > _everplay_limit:
                text ("Showing %d of %d. Search to narrow the list." % (_everplay_limit, _everplay_b.len(entries))):
                    size s(17)
                    font "DejaVuSans.ttf"
                    color "#d9b45a"
            # No scrollbars: they would take the game's own scrollbar style.
            viewport:
                ysize _everplay_b.int(config.screen_height * 0.94) - s(190)
                mousewheel True
                draggable True
                vbox:
                    spacing s(6)
                    for label, container, key, item in entries[:_everplay_limit]:
                        $ value = _everplay_get(container, key, item)
                        $ kind = _everplay_kind(value)
                        frame:
                            background Solid("#1f222c")
                            xfill True
                            padding (s(12), s(6))
                            hbox:
                                spacing s(8)
                                text _everplay_quote(label) size s(20) color "#d8d6ff" min_width name_width xmaximum name_width yalign 0.5 font "DejaVuSans.ttf"
                                text _everplay_quote(_everplay_show(value)) size s(20) color "#ffffff" min_width value_width xmaximum value_width yalign 0.5 font "DejaVuSans.ttf"
                                if kind == "bool":
                                    textbutton "Toggle":
                                        action Function(_everplay_toggle, container, key, item)
                                        background Solid("#2f3342")
                                        hover_background Solid("#454b60")
                                        padding (s(12), s(8))
                                        text_size s(19)
                                        text_font "DejaVuSans.ttf"
                                        text_color "#ffffff"
                                elif kind == "number":
                                    for delta in (-100, -10, -1, 1, 10, 100):
                                        textbutton ("%+d" % delta):
                                            action Function(_everplay_add, container, key, item, delta)
                                            background Solid("#2f3342")
                                            hover_background Solid("#454b60")
                                            padding (s(10), s(8))
                                            text_size s(19)
                                            text_font "DejaVuSans.ttf"
                                            text_color "#ffffff"
                                textbutton "Edit":
                                    action Show("_everplay_edit", label=label, container=container, key=key, item=item)
                                    background Solid("#3d3a8c")
                                    hover_background Solid("#5a55c8")
                                    padding (s(12), s(8))
                                    text_size s(19)
                                    text_font "DejaVuSans.ttf"
                                    text_color "#ffffff"
                    if not entries:
                        text "No matching variables." size s(20) color "#8f93a3" font "DejaVuSans.ttf"

screen _everplay_edit(label, container, key, item):
    modal True
    zorder 2100
    default buffer = u"%s" % (_everplay_get(container, key, item),)
    key "game_menu" action Hide("_everplay_edit")
    $ s = _everplay_scale
    add Solid("#000000b0")
    frame:
        background Solid("#1d2029")
        xalign 0.5
        yalign 0.3
        xsize _everplay_b.int(config.screen_width * 0.6)
        padding (s(22), s(18))
        vbox:
            spacing s(14)
            text _everplay_quote(label) size s(24) color "#d8d6ff" font "DejaVuSans.ttf"
            frame:
                background Solid("#262a36")
                xfill True
                padding (s(12), s(10))
                input value ScreenVariableInputValue("buffer") size s(26) color "#ffffff" font "DejaVuSans.ttf"
            hbox:
                spacing s(14)
                xalign 1.0
                textbutton "Cancel":
                    action Hide("_everplay_edit")
                    padding (s(16), s(10))
                    text_size s(22)
                    text_font "DejaVuSans.ttf"
                    text_color "#b8b4ff"
                textbutton "Set":
                    action [Function(_everplay_apply, container, key, item, buffer), Hide("_everplay_edit")]
                    background Solid("#5a55c8")
                    hover_background Solid("#6b66d6")
                    padding (s(22), s(10))
                    text_size s(22)
                    text_font "DejaVuSans.ttf"
                    text_color "#ffffff"

# EverPlay's on-screen keyboard. iOS's own keyboard does not reach the embedded game window, so
# EverPlay turns on Ren'Py's touch keyboard (RENPY_TOUCH_KEYBOARD) and replaces its screen with
# this docked QWERTZ layout. It reuses Ren'Py's own key actions from 00touchkeyboard.rpy.
init -1500 python:

    _everplay_font = "DejaVuSans.ttf"

    def _everplay_keyboard_at_top():
        try:
            import renpy.game as _everplay_game
            rect = _everplay_game.interface.text_rect
        except Exception:
            rect = None
        # Keep the text being typed visible: dock above it when it sits in the lower half.
        return bool(rect) and rect[1] + rect[3] > config.screen_height * 0.5

    # 8.1/8.2 have no config.interface_layer, and their config store raises instead of letting
    # getattr fall back.
    try:
        _everplay_kb_layer = config.interface_layer
    except Exception:
        _everplay_kb_layer = "screens"

    _everplay_rows = {
        "letters": ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"],
        "numbers": ["1234567890", "-/:;()€&@\"", ".,?!'#%*+="],
    }

init 1600:
    screen _touch_keyboard():
        layer _everplay_kb_layer
        zorder 3000  # above EverPlay's own windows (variable editor, edit dialog)
        default shift = False
        default mode = "letters"
        $ s = _everplay_scale
        $ width = config.screen_width
        $ gap = s(8)
        $ key = (width - s(24) - 10 * gap) // 11
        $ tall = s(62)
        $ rows = _everplay_rows[mode]
        frame:
            background Solid("#16161ceb")
            xfill True
            yalign (0.0 if _everplay_keyboard_at_top() else 1.0)
            padding (s(12), s(12))
            vbox:
                spacing gap
                xalign 0.5
                for index, row in enumerate(rows):
                    hbox:
                        spacing gap
                        xalign 0.5
                        if index == 2 and mode == "letters":
                            textbutton ("⇧" if not shift else "⬆"):
                                substitute False
                                action ToggleScreenVariable("shift")
                                xysize (key * 3 // 2, tall)
                                background Solid("#2b2b33")
                                selected_background Solid("#e8e8ee")
                                text_selected_color "#16161c"
                                text_font _everplay_font
                                text_size s(28)
                                text_color "#ffffff"
                                text_xalign 0.5
                                text_yalign 0.5
                        for character in row:
                            $ typed = character.upper() if shift else character
                            # substitute False: no [ ] interpolation and no string translation,
                            # which replaced single letters in a game with its own translations.
                            textbutton typed:
                                substitute False
                                action [_TouchKeyboardTextInput(typed), SetScreenVariable("shift", False)]
                                xysize (key, tall)
                                background Solid("#3e3e48")
                                hover_background Solid("#5a5a66")
                                text_font _everplay_font
                                text_size s(28)
                                text_color "#ffffff"
                                text_xalign 0.5
                                text_yalign 0.5
                        if index == 2:
                            textbutton "⌫":
                                substitute False
                                action _TouchKeyboardBackspace()
                                xysize (key * 3 // 2, tall)
                                background Solid("#2b2b33")
                                hover_background Solid("#45454f")
                                text_font _everplay_font
                                text_size s(28)
                                text_color "#ffffff"
                                text_xalign 0.5
                                text_yalign 0.5
                hbox:
                    spacing gap
                    xalign 0.5
                    textbutton ("123" if mode == "letters" else "ABC"):
                        substitute False
                        action SetScreenVariable("mode", "numbers" if mode == "letters" else "letters")
                        xysize (key * 2, tall)
                        background Solid("#2b2b33")
                        text_font _everplay_font
                        text_size s(24)
                        text_color "#ffffff"
                        text_xalign 0.5
                        text_yalign 0.5
                    textbutton "space":
                        substitute False
                        action _TouchKeyboardTextInput(" ")
                        xysize (key * 6 + gap * 5, tall)
                        background Solid("#3e3e48")
                        hover_background Solid("#5a5a66")
                        text_font _everplay_font
                        text_size s(24)
                        text_color "#ffffff"
                        text_xalign 0.5
                        text_yalign 0.5
                    textbutton "Enter":
                        substitute False
                        action _TouchKeyboardReturn()
                        xysize (key * 3 + gap * 2, tall)
                        background Solid("#5a55c8")
                        hover_background Solid("#6b66d6")
                        text_font _everplay_font
                        text_size s(24)
                        text_color "#ffffff"
                        text_xalign 0.5
                        text_yalign 0.5
