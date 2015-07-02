AtomPhpNavigationView = require './atom-php-navigation-view'
{CompositeDisposable, Range} = require 'atom'
fs = require 'fs'
trim = require 'trim'
scandir = require('scandir').create()
_markers = {};
_tree = {};

module.exports = AtomPhpNavigation =
  atomPhpNavigationView: null
  modalPanel: null
  subscriptions: null
  enabled: false
  indexingRunned: false
  extendsRegExp: /^(class|interface|trait|abstract class)\s([\S]+?)\s(\s?extends ([\w\d\_\\]+))?(\s?implements ([\w\d\_\\,\s]+))?/g
  useRegExp: /use\s([\w\d_\\]+);/g
  classRegExp: /\n+(interface|abstract class|class) (.*?)( |\n)/
  namespaceRegExp: /namespace (.*?);/
  classCallRegExp: /([\s\t]+|=)(new ([\w\d\\_]+)|([\w\d\\_]+)::)/g

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
      @scanExtends(editor)
      @scanUses(editor)

  disable: ->
    @enabled = false
    console.log 'Off'

  createMarker: (editor, res, match) ->
    match = trim match
    namespace = match.split "\\"
    className = namespace[namespace.length - 1]
    row = res.computedRange.start.row
    start = ( res.match[0].indexOf ' ' + match ) + 1
    end = start + match.length
    range = new Range([row, start], [row, end])
    marker = editor.markBufferRange(range)
    markerProperties =
      className: className
      namespace: namespace.slice(1, namespace.length).join '\\'

    marker.setProperties markerProperties

    options =
      type: 'line'
      class: 'clickable-class'

    editor.decorateMarker marker, options
    return marker

  scanUses: (editor) ->
    self = @
    # Find used classes and traits in opened files
    editor.scan @useRegExp, (res) ->
      if res.match.length < 2
        return false

      marker = self.createMarker(editor, res, res.match[1])
      editor.onDidChangeCursorPosition (event) ->
        if marker.getBufferRange().containsPoint(event.newBufferPosition)
          props = marker.getProperties()
          className = props.className
          self.openClassFile className, res.filePath, props.namespace

  scanExtends: (editor) ->
    self = @
    # Find classes and parent classes in opened files
    editor.scan @extendsRegExp, (res) ->
      if res.match.length < 5
        return false

      markers = []
      if res.match[4] != undefined
        markers.push(self.createMarker(editor, res, res.match[4]))

      if res.match[6] != undefined
        res.match[6].split(',').map((str) ->
          markers.push(self.createMarker(editor, res, str))
        )

      editor.onDidChangeCursorPosition (event) ->
        markers.map((marker) ->
          if marker.getBufferRange().containsPoint(event.newBufferPosition)
            props = marker.getProperties()
            className = props.className
            self.openClassFile className, res.filePath, props.namespace
        )

  openClassFile: (className, path, namespace) ->
    if typeof _tree[className] == 'object'
      atom.open {pathsToOpen: _tree[className].path}
    else
      exp = new RegExp "^(class|interface|trait|abstract class) (" + className + ")[^\\w\\d]+"
      atom.workspace.scan exp, (res) ->
        if res.filePath
          atom.open {pathsToOpen: res.filePath}
          _tree[className] =
            path: path
            className: className
            namespace: namespace

  indexing: ->
    if !@indexingRunned
      @indexingRunned = true
      @modalPanel.show()
    else
      return false

    self = @

    path = atom.project.getPaths()[0]
    scandir.on 'file', (filePath, stats) ->
      fs.readFile filePath, encoding: 'utf-8', (err, data) ->
        namespace = data.match self.namespaceRegExp
        className = data.match self.classRegExp
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

    #@printTree()
