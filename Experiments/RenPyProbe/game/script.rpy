# Original EverPlay integration fixture. MIT, see the repository LICENSE.
define config.name = "EverPlay RenPy Probe"
define config.version = "0.1"
define config.screen_width = 800
define config.screen_height = 600
define config.save_directory = "EverPlayRenPyProbe-1"
define config.window = "hide"
define build.name = "EverPlayRenPyProbe"

default gold = 10
default route = "undecided"
default probe_ready = False

init python:
    build.archive("story", "all")
    build.classify("game/**.rpyc", "story")
    build.classify("game/**.rpy", None)

    def publish_probe_state():
        if renpy.emscripten:
            import json
            payload = json.dumps({"ready": True, "gold": gold, "route": route, "saved": renpy.can_load("probe-slot")})
            renpy.emscripten.run_script("window.everplayProbe = " + payload + ";")

screen probe():
    add Solid("#102537")
    text "EverPlay · Ren'Py engine probe" xpos 40 ypos 35 size 32
    text "Gold: [gold] · Route: [route]" xpos 40 ypos 105 size 26
    text "An original scene: choose a path through the garden." xpos 40 ypos 150 size 22
    textbutton "Collect +10" xpos 40 ypos 230 action [SetVariable("gold", gold + 10), Function(publish_probe_state)]
    textbutton "Garden route" xpos 40 ypos 300 action [SetVariable("route", "garden"), Function(publish_probe_state)]
    textbutton "Save slot" xpos 40 ypos 370 action Function(renpy.save, "probe-slot")
    textbutton "Load slot" xpos 40 ypos 440 action Function(renpy.load, "probe-slot")
    key "K_z" action [SetVariable("gold", gold + 10), Function(publish_probe_state)]
    key "K_x" action Function(renpy.save, "probe-slot")
    key "K_RETURN" action Function(renpy.load, "probe-slot")
    timer 0.2 action Function(publish_probe_state) repeat True

label main_menu:
    # Return to RenPy's normal game-start context; do not run gameplay in the menu context.
    return

label start:
    $ probe_ready = True
    # Screen edits must survive RenPy's normal rollback to the statement start.
    $ renpy.retain_after_load()
    call screen probe
    return
