PareditJS = require 'paredit.js'
PareditJS.walk = module.require("paredit.js/lib/navigator").walk;
{CompositeDisposable} = require 'atom'

module.exports = Paredit =
  subscriptions: null


  activate: (state) ->

    atom.workspace.observeTextEditors (editor) =>
      # if the editor is clojure etc.
      # register for changes and update the ast
      lang = editor.getRootScopeDescriptor().getScopesArray()[0]
      if lang == "source.clojure"
        editor.needsSync = true
        @syncAST(editor)
        # TODO: when an editor becomes lisp or not lisp?

        editor.onDidChange () =>
          editor.needsSync = true

        editor.onDidStopChanging () =>
          @syncAST(editor)
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:indent': => @indent()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:newLineAndIndent': => @newLineAndIndent()

    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:forwardSexp': => @forwardSexp()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:backwardSexp': => @backwardSexp()
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'paredit:forwardAndSelectSexp': => @forwardAndSelectSexp()
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'paredit:backwardAndSelectSexp': => @backwardAndSelectSexp()

    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:openParens': => @openParens()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:openBracket': => @openBracket()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:openCurly': => @openCurly()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:openQuote': => @closeParens()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:closeCurly': => @closeCurly()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:closeBracket': => @closeBracket()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:closeParens': => @closeParens()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:killSexpFwd': => @killSexpFwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:killSexpBwd': => @killSexpBwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:deleteFwd': => @deleteFwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:deleteBwd': => @deleteBwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:slurpSexpFwd': => @slurpSexpFwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:slurpSexpBwd': => @slurpSexpBwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:barfSexpFwd': => @barfSexpFwd()
    @subscriptions.add atom.commands.add 'atom-text-editor', 'paredit:barfSexpBwd': => @barfSexpBwd()


  deactivate: ->
    @subscriptions.dispose()

  serialize: ->

  prepareForSourceTransform: (editor) ->
    @syncAST(editor)
    currPos = editor.getCursorBufferPosition()
    buf = editor.getBuffer()
    source = editor.getText()
    sel = editor.getSelectedBufferRange()
    posIdx = buf.characterIndexForPosition(currPos)
    parentSexps = editor.ast && PareditJS.walk.containingSexpsAt(editor.ast, posIdx, PareditJS.walk.hasChildren)
    res =
      pos: posIdx
      ast: editor.ast
      selStart: buf.characterIndexForPosition(sel.start)
      selEnd: buf.characterIndexForPosition(sel.end)
      source: source
      parentSexps: parentSexps

  syncAST: (editor) ->
    if editor.needsSync
      editor.ast = PareditJS.parse(editor.getText())
      @highlightErrors(editor)
      editor.needsSync = false

  applyChanges: (editor, c) ->
    return if not c

    buf = editor.getBuffer()

    for change in c.changes
      if change[0] is "remove"
        p1 = buf.positionForCharacterIndex(change[1])
        p2 = buf.positionForCharacterIndex(change[1]+change[2])
        buf.delete([p1,p2])
      else if change[0] is "insert"
        p1 = buf.positionForCharacterIndex(change[1])
        buf.insert(p1,change[2])

  updateCursor: (editor, idx) ->
    buf = editor.getBuffer()

    if idx
      editor.setCursorBufferPosition(buf.positionForCharacterIndex(idx))

  highlightErrors: (editor) ->

    oldMarkers = editor.findMarkers({pareditError: true})
    for marker in oldMarkers
      marker.destroy()

    if editor.ast.errors && editor.ast.errors.length
      for err in editor.ast.errors
        buf = editor.getBuffer()
        p1 = buf.positionForCharacterIndex(err.start)
        p2 = buf.positionForCharacterIndex(err.end)
        marker = editor.markBufferRange(
          [p1, p2], {invalidate: 'touch', pareditError: true})
        editor.decorateMarker(marker,
          {type: 'highlight', class: 'highlight-paredit-error'})

# Indentation

  doIndent: (editor) ->
    data = @prepareForSourceTransform(editor)

    if not data.ast
      return

    changes = PareditJS.editor.indentRange(data.ast, data.source, data.selStart, data.selEnd)
    @applyChanges(editor, changes)

  indent: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @doIndent(editor)
    editor.groupChangesSinceCheckpoint(check)

  newLineAndIndent: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    editor.insertText("\n")
    @doIndent(editor)
    editor.groupChangesSinceCheckpoint(check)


  forwardSexp: ->
    editor = atom.workspace.getActiveTextEditor()
    @forward(editor,false)

  forwardAndSelectSexp: ->
    editor = atom.workspace.getActiveTextEditor()
    @forward(editor,true)

  forward: (editor, select) ->
      data = @prepareForSourceTransform(editor)
      buf = editor.getBuffer()
      idx = data.pos

      return if (!data.ast || !data.ast.type == 'toplevel')

      loop
        next = PareditJS.walk.nextSexp(data.ast, idx)

        if next && next.end != data.pos && next.type != 'comment'
          pos = buf.positionForCharacterIndex(next.end)
          if select
            editor.selectToBufferPosition(pos)
          else
            editor.setCursorBufferPosition(pos)
          break

        idx = idx + 1

        break if idx > editor.getBuffer().getMaxCharacterIndex()

        prev = PareditJS.walk.prevSexp(data.ast, idx)

        if prev && prev.end == idx && prev.type != 'comment'
          pos = buf.positionForCharacterIndex(idx)
          if select
            editor.selectToBufferPosition(pos)
          else
            editor.setCursorBufferPosition(pos)
          break

  backwardSexp: ->
    editor = atom.workspace.getActiveTextEditor()
    @back(editor,false)

  backwardAndSelectSexp: ->
    editor = atom.workspace.getActiveTextEditor()
    @back(editor,true)

  back: (editor, select)->

    data = @prepareForSourceTransform(editor)
    buf = editor.getBuffer()
    idx = data.pos

    return if (!data.ast || !data.ast.type == 'toplevel')

    loop
      prev = PareditJS.walk.prevSexp(data.ast, idx)

      if prev && prev.start != data.pos && prev.type != 'comment'
        pos = buf.positionForCharacterIndex(prev.start)
        if select
          editor.selectToBufferPosition(pos)
        else
          editor.setCursorBufferPosition(pos)
        break

      idx = idx - 1

      break if idx == 0

      next = PareditJS.walk.nextSexp(data.ast, idx)

      if next && next.start == idx && next.type != 'comment'
        pos = buf.positionForCharacterIndex(idx)
        if select
          editor.selectToBufferPosition(pos)
        else
          editor.setCursorBufferPosition(pos)
        break

# Parens

  open: (args) ->
    editor = atom.workspace.getActiveTextEditor()
    data = @prepareForSourceTransform(editor)

    if not data.ast
      editor.insertText(args.open)
      return

    args.freeEdits = PareditJS.freeEdits

    if data.selStart is not data.selEnd
      args.endIdx = data.selEnd
    idx =
      if args.endIdx
        data.selStart
      else
        data.pos

    changes = PareditJS.editor.openList(data.ast, data.source, idx, args)

    if changes
      @applyChanges(editor, changes)
      @updateCursor(editor, changes.newIndex)

  openParens: ->
    args =
      open: '('
      close: ')'
    @open(args)

  openBracket: ->
    args =
      open: '['
      close: ']'
    @open(args)

  openCurly: ->
    args =
      open: '{'
      close: '}'
    @open(args)

  openQuote: ->
    args =
      open: '"'
      close: '"'
    @open(args)

  closeList: (editor) ->
      data = @prepareForSourceTransform(editor)
      buf = editor.getBuffer()

      return false if (!data.ast || !data.ast.type == 'toplevel')
      moveToIdx = PareditJS.navigator.closeList(data.ast, data.pos)
      return false if (moveToIdx == undefined)

      pos = buf.positionForCharacterIndex(moveToIdx)
      editor.setCursorBufferPosition(pos)
      return true

  close: (args) ->
    editor = atom.workspace.getActiveTextEditor()
    data = @prepareForSourceTransform(editor)

    args.freeEdits = PareditJS.freeEdits

    if args.freeEdits || !data.ast || (data.ast.errors && data.ast.errors.length) || !@closeList(editor)
      editor.insertText(args.close)

  closeCurly: ->
    args =
      open: '{'
      close: '}'
    @close(args)

  closeBracket: ->
    args =
      open: '['
      close: ']'
    @close(args)

  closeParens: ->
    args =
      open: '('
      close: ')'
    @close(args)

  # deleting

  killSexp: (editor, args) ->
    args = args || {}
    data = @prepareForSourceTransform(editor)
    return if not data.ast
    changes = PareditJS.editor.killSexp(data.ast, data.source, data.pos, args);
    if changes
      @applyChanges(editor, changes)
      @updateCursor(editor, changes.newIndex)

  killSexpFwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @killSexp(editor, {backward: false})
    editor.groupChangesSinceCheckpoint(check)

  killSexpBwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @killSexp(editor, {backward: true})
    editor.groupChangesSinceCheckpoint(check)

  delete: (editor, args) ->
    args = args || {}

    if PareditJS.freeEdits
      args.freeEdits = true

    data = @prepareForSourceTransform(editor)
    return if not data.ast

    if data.selStart != data.selEnd
      args.endIdx = data.selEnd
    pos = if args.endIdx then data.selStart else data.pos
    changes = PareditJS.editor.delete(data.ast, data.source, pos, args)
    if changes
      @applyChanges(editor, changes)
      # hack to make it behave like emacs paredit


      if data.pos == changes.newIndex and args.backward
        changes.newIndex = Math.max(0, changes.newIndex - 1)
      # remove forward cursor movement for now
      # else if data.pos == changes.newIndex and !args.backward
        # changes.newIndex = changes.newIndex + 1
        # @updateCursor(editor, changes.newIndex)

  deleteBwd: ->
    editor = atom.workspace.getActiveTextEditor()
    if editor.getSelectedText().length == 0
      check = editor.createCheckpoint()
      @delete(editor, {backward: true})
      editor.groupChangesSinceCheckpoint(check)
    else
      editor.delete()

  deleteFwd: ->
    editor = atom.workspace.getActiveTextEditor()
    if editor.getSelectedText().length == 0
      check = editor.createCheckpoint()
      @delete(editor, {backward: false})
      editor.groupChangesSinceCheckpoint(check)
    else
      editor.delete()

  # slurp/barf

  slurpSexp: (editor, args) ->
    args = args || {}
    data = @prepareForSourceTransform(editor)
    return if not data.ast

    changes = PareditJS.editor.slurpSexp(data.ast, data.source, data.pos, args)
    if changes
      @applyChanges(editor, changes)
      @updateCursor(editor, changes.newIndex)

  slurpSexpFwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @slurpSexp(editor, {backward: false})
    editor.groupChangesSinceCheckpoint(check)

  slurpSexpBwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @slurpSexp(editor, {backward: true})
    editor.groupChangesSinceCheckpoint(check)

  barfSexp: (editor, args) ->
    args = args || {}
    data = @prepareForSourceTransform(editor)
    return if not data.ast

    changes = PareditJS.editor.barfSexp(data.ast, data.source, data.pos, args)
    if changes
      @applyChanges(editor, changes)
      @updateCursor(editor, changes.newIndex)

  barfSexpFwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @barfSexp(editor, {backward: false})
    editor.groupChangesSinceCheckpoint(check)

  barfSexpBwd: ->
    editor = atom.workspace.getActiveTextEditor()
    check = editor.createCheckpoint()
    @barfSexp(editor, {backward: true})
    editor.groupChangesSinceCheckpoint(check)

  # TODO:
  # indent on paste
  # 'Ctrl-Alt-h':                                   'markDefun',
  # 'Shift-Command-Space|Ctrl-Shift-Space':         'expandRegion',
  # 'Ctrl-Command-space|Ctrl-Alt-Space':            'contractRegion',
  # 'Ctrl-`':                                       'gotoNextError',
  #
  # "Ctrl-Alt-t":                                   "paredit-transpose",
  # "Alt-Shift-s":                                  "paredit-splitSexp",
  # "Alt-s":                                        "paredit-spliceSexp",
  # "Alt-Shift-9":                                  {name: "paredit-wrapAround", args: {open: '(', close: ')'}},
  # "Alt-[":                                        {name: "paredit-wrapAround", args: {open: '[', close: ']'}},
  # "Alt-Shift-{|Alt-Shift-[":                      {name: "paredit-wrapAround", args: {open: '{', close: '}'}},
  # "Alt-Shift-0":                                  {name: "paredit-closeAndNewline", args: {close: ')'}},
  # "Alt-]":                                        {name: "paredit-closeAndNewline", args: {close: ']'}},
  # "Alt-Up|Alt-Shift-Up":                          {name: "paredit-spliceSexpKill", args: {backward: true}},
  # "Alt-Down||Alt-Shift-Down":                     {name: "paredit-spliceSexpKill", args: {backward: false}},
  # "Ctrl-x `":                                     "gotoNextError",
  # "\"":                                           {name: "paredit-openList", args: {open: "\"", close:
