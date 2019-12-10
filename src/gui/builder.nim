import macros

# Signal Builder
var lastID {.compileTime.} : uint16 = 1
macro signal*(name: untyped, messages: untyped): untyped =
  name.expectKind(nnkIdent)
  result = nnkStmtList.newTree()
  # Create ID Const Node
  result.add(
    newNimNode(nnkConstSection).add(
      newNimNode(nnkConstDef).add(
        newNimNode(nnkPostfix).add(
          newIdentNode("*"), 
          newIdentNode(name.strVal & "ID")
        ), 
        newEmptyNode(), 
        newLit(lastID)
      )
    )
  )
  inc(lastID)

  if messages[0].kind != nnkDiscardStmt:
    # Create Enum Node
    var msgNode = newNimNode(nnkEnumTy)
    msgNode.add(newEmptyNode())
    for m in messages:
      m.expectKind(nnkIdent)
      msgNode.add(
        newIdentNode("msg" & m.strVal)
      )
    # Create Type Enum Node
    result.add(
      newNimNode(nnkTypeSection).add(
        newNimNode(nnkTypeDef).add(
          newNimNode(nnkPostfix).add(
            newIdentNode("*"),
            newIdentNode(name.strVal & "Msg")
          ),
          newEmptyNode(),
          msgNode
        )
      )
    )

# Widget Builder
# TODO: Plan how is the sintaxis