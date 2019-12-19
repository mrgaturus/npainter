import macros

# Signal Builder
var lastID {.compileTime.} : uint8 = 0
macro signal*(name: untyped, messages: untyped) =
  # Expected Parameters
  name.expectKind(nnkIdent)
  messages.expectKind(nnkStmtList)
  # Check signal limit count
  if lastID > 63'u8: error("exceded signal count")
  # Create a new Tree
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
  # Create Msg Enum if not discarded
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
