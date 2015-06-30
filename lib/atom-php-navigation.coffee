AtomPhpNavigationView = require './atom-php-navigation-view'
{CompositeDisposable} = require 'atom'
fs = require 'fs'
scandir = require('scandir').create()
_markers = {};
_tree = {};


module.exports = AtomPhpNavigation =
  atomPhpNavigationView: null
  modalPanel: null
  subscriptions: null
  enabled: false
  indexingRunned: false

  getTree: ->
    return _tree;

  printTree: ->
    console.log @getTree();

  activate: (state) ->
    @atomPhpNavigationView = new AtomPhpNavigationView(state.atomPhpNavigationViewState)
    @modalPanel = atom.workspace.addModalPanel(item: @atomPhpNavigationView.getElement(), visible: false)

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'atom-php-navigation:toggle': => @toggle()


    @phpViews = []
    @enable()

  deactivate: ->
    @modalPanel.destroy()
    @subscriptions.dispose()
    @atomPhpNavigationView.destroy()

  serialize: ->
    atomPhpNavigationViewState: @atomPhpNavigationView.serialize()

  toggle: ->
    @indexing()

    if @enabled
      @disable()
    else
      @enable()

  enable: ->
    @enabled = true
    console.log 'On'

    @editorViewSubscription = atom.workspace.observeTextEditors (editor) =>
      @injectPhpViewIntoEditorView(editor)

  disable: ->
    @enabled = false
    console.log 'Off'

  injectPhpViewIntoEditorView: (editor) ->
    # Find classes and parent classes in opened files
    editor.scan /^(abstract class|interface|class) ([\w\d_\\]+) (extends|implements) ([\w\d_\\]+)/i, (res) ->
      if res.match.length < 5
        return false

      namespace = res.match[4].split "\\"
      className = namespace[namespace.length - 1]
      exp = new RegExp "^(abstract class|interface|class) (" + className + ")[^\\w\\d]+"
      row = res.computedRange.start.row
      start = ( res.match[0].indexOf ' ' + res.match[4] ) + 1
      end = start + res.match[4].length
      end = if end > res.computedRange.end.column then res.computedRange.end.column else end
      marker = editor.markBufferRange([[row, start], [row, end]])
      console.log 'marker', marker

      options =
        type: 'line'
        class: 'parent-class'

      editor.decorateMarker marker, options
      editor.onDidChangeCursorPosition (event) ->
        newCol = event.newBufferPosition.column
        newRow =  event.newBufferPosition.row

        if newRow == row and newCol >= start and newCol <= end
          if typeof _tree[className] == 'object'
            atom.open {pathsToOpen: _tree[className].path}
          else
            atom.workspace.scan exp, (res) ->
              if res.filePath
                atom.open {pathsToOpen: res.filePath}
                _tree[className] =
                  path: res.filePath
                  className: className
                  namespace: namespace.slice(1, namespace.length).join '\\'

  indexing: ->
    if !@indexingRunned
      @indexingRunned = true
      @modalPanel.show()
    else
      return false

    console.log 'Indexing!'

    path = atom.project.getPaths()[0]
    scandir.on 'file', (filePath, stats) ->
      fs.readFile filePath, encoding: 'utf-8', (err, data) ->
        namespace = data.match /namespace (.*?);/i
        className = data.match /\n+(interface|abstract class|class) (.*?)( |\n)/
        className = if className then className[2] else null
        fileName = filePath.split('/')
        fileName = fileName[fileName.length - 1]

        _tree[if className then className else fileName] =
          namespace: if namespace then namespace[1] else ''
          className: className
          path: filePath

      return

    scandir.on 'error', (err) ->
      console.error err
      return

    self = @
    scandir.on 'end', ->
      self.indexingComplete()
      return

    scandir.scan
      dir: path
      recursive: true
      filter: /\.php/


  indexingComplete: ->
    @indexingRunned = false
    if @modalPanel.isVisible()
      @modalPanel.hide()

    @printTree()
