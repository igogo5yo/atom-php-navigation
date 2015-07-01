module.exports =
class AtomPhpNavigationView
  constructor: (serializedState) ->
    # Create root element
    @element = document.createElement('div')
    @element.classList.add('atom-php-navigation')

    # Create message element
    message = document.createElement('div')
    message.textContent = "Indexation: please wait!"
    message.classList.add('message')

    loading = document.createElement('span')
    loading.classList.add('loading')
    message.appendChild(loading)

    @element.appendChild(message)

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @element.remove()

  getElement: ->
    @element
