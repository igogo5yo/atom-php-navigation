path = require 'path'
{View} = require 'atom'
CSON = require 'season'
_ = require 'lodash'

InformationView = require './information-view'
Information = require './information'

module.exports =
class PhpView extends View
  @content: ->
    @div class: 'php-nav'

  initialize: (@editorView) ->
    @editorView.phpView = this
    @editorView.overlayer.append(this)

    @editor = @editorView.getEditor()

    @informationViews = []


    @editorView.command 'atom-php-navigation:move-to-next-information', => @moveToNextInformation()
    @editorView.command 'atom-php-navigation:move-to-previous-information', => @moveToPreviousInformation()

  beforeRemove: ->
    @editorView.off('atom-php-navigation:move-to-next-information atom-php-navigation:move-to-previous-information')
    @phpRunner.stopWatching()
    @editorView.phpView = undefined

  refresh: ->
    @phpRunner.refresh()

  onPhperActivation: ->
    # http://discuss.atom.io/t/decorating-the-left-gutter/1321/4
    @editorDisplayUpdateSubscription = @subscribe @editorView, 'editor:display-updated', =>
      if @pendingInformations?
        @addInformationViews(@pendingInformations)
        @pendingInformations = null

  onPhperDeactivation: ->
    @editorDisplayUpdateSubscription?.off()
    @removeInformationViews()

  onPhp: (error, informations) ->
    @removeInformationViews()

    if error?
      console.log(error.toString())
      console.log(error.stack)
    else if @editorView.active
      @addInformationViews(informations)
    else
      # InformationViews won't be placed properly when the editor (tab) is not active and the file is
      # reloaded by a modification by another process. So we make them pending for now and place
      # them when the editor become active.
      @pendingInformations = informations

  addInformationViews: (informations) ->
    for information in informations
      informationView = new InformationView(information, this)
      @informationViews.push(informationView)

  removeInformationViews: ->
    while view = @informationViews.shift()
      view.remove()

  getValidInformationViews: ->
    @informationViews.filter (informationView) ->
      informationView.isValid

  moveToNextInformation: ->
    @moveToNeighborInformation('next')

  moveToPreviousInformation: ->
    @moveToNeighborInformation('previous')

  moveToNeighborInformation: (direction) ->
    if @informationViews.length == 0
      atom.beep()
      return

    if direction == 'next'
      enumerationMethod = 'find'
      comparingMethod = 'isGreaterThan'
    else
      enumerationMethod = 'findLast'
      comparingMethod = 'isLessThan'

    currentCursorPosition = @editor.getCursor().getScreenPosition()

    # OPTIMIZE: Consider using binary search.
    neighborInformationView = _[enumerationMethod] @getValidInformationViews(), (informationView) ->
      informationPosition = informationView.screenStartPosition
      informationPosition[comparingMethod](currentCursorPosition)

    if neighborInformationView?
      @editor.setCursorScreenPosition(neighborInformationView.screenStartPosition)
    else
      atom.beep()
