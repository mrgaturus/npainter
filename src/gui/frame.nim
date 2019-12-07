import context, container

type
  GUIFrame = object
    tex: CTXFrame
    gui: GUIContainer

# -------------------
# GUIFRAME CREATION PROCS
# -------------------

proc newGUIFrame(): GUIFrame =
  discard