define (require, exports, module) ->

  require 'vendor/link!css/filebrowser.css'

  {node} = require 'lib/utils'
  {addKeyboardListener} = require 'lib/keyboard'
  
  ITEM_HEIGHT = 70
  
  FileItem = Backbone.Model.extend
    defaults: ->
      type: 'file'
      file: null
      items: null

  FileItemList = Backbone.Collection.extend
    model: FileItem
    
    comparator: (p) ->
      p.get('type')

  FileItemView = Backbone.View.extend
    className: 'file-item'

    events:
      'dblclick' : 'openFile'
      'click .name': 'openFile'
      'click' : 'onClick'

    initialize: ->
      @model.on 'destroy', @remove, @
      @model.on 'change', @render, @
      
      if @model.get('type') == 'file'
        @$el.addClass 'is-file'
        @$el.append [
          node 'div', class: 'name', (@model.get('file').get('url'))
        ]
      else
        @$el.addClass 'is-dir'
        @$el.append [
          node 'div', class: 'name', (@model.get('path'))
          @itemsEl = node 'div'
        ]
        
        items = @model.get('items')
        items.on 'add', @onItemAdd, @
        items.on 'reset', @onItemAddAll, @
      
      app.console.on 'change:client', @render, @

    onItemAdd: (item) ->
      view = (new FileItemView model: item).render()
      index = @model.get('items').indexOf(view.model);
      previous = @model.get('items').at(index - 1);
      previousView  = previous && previous.view;
      if index == 0 || !previous || !previousView
        $(@itemsEl).prepend(view.el);
      else
        $(previousView.el).after(view.el);
      
    onItemAddAll: (items) ->
      $(@itemsEl).empty()
      @model.get('items').each @onItemAdd, @

    openFile: ->
      app.console.openFile @model.get 'url'

    onClick: ->
      @select()

    destroy: ->
      @model.off 'destroy', @remove, @
      @model.off 'change', @render, @
      app.console.off 'change:client', @render, @

    select: (bool = true) ->
      @$el.toggleClass 'is-selected', bool
      @trigger 'select', @model if bool
      # Order is important to get the browser clear old ones.
      @selected = bool

    render: ->
      ###
      json = @model.toJSON()
      clientId = app.console?.client?.id
      parsedName = json.name.match /^(.+)(\.[^\.]+)$/
      _.extend json,
        isActive: clientId && (json.clients.indexOf clientId) != -1
        isOpen: !!json.edit
        name: parsedName[1]
        extension: parsedName[2]
        isHelper: 0 == json.url.indexOf '#local'
      @$el.html @template json
      ###
      @

  FileBrowser = Backbone.View.extend

    MIN_WIDTH: 150

    initialize: ->
      _.bindAll @, 'onResize', 'onSelect', 'onKeyDown'

      @subviews = []

      @collection.on 'add', @onAddFile, @
      @collection.on 'reset', @onAddAllFiles, @
      $(window).on 'resize', @onResize

      addKeyboardListener 'filebrowser', @el
      @el.listenKey 'file-prev', mac: 'right', exec: => @moveSelection 1
      @el.listenKey 'file-next', mac: 'left', exec: => @moveSelection -1
      @el.listenKey 'file-prev-row', mac: 'up', exec: => @moveSelection -@cols
      @el.listenKey 'file-next-row', mac: 'down', exec: => @moveSelection @cols
      @el.listenKey 'file-first', mac: 'home', exec: => @collection.first().view.select()
      @el.listenKey 'file-last', mac: 'end', exec: => @collection.last().view.select()
      @el.listenKey 'select-file', mac: 'return', exec: => @selectedFile()?.view?.openFile()
      
      @root = new FileItem type: 'dir', path: '', items: new FileItemList
      rootView = new FileItemView model: @root
      @$el.append rootView.render().el
      
      @$el.on 'keydown', @onKeyDown
      @search = ''

    destroy: ->
      @collection.each (file) -> file.view.destroy()
      @collection.off 'add', @addOne, @
      @collection.off 'reset', @addAll, @
      $(window).off 'resize', @onResize

    # As-you-type file search(highlight).
    onKeyDown: (e) ->
      char = String.fromCharCode e.keyCode
      return @search = '' unless char.length
      curTime = new Date()
      @search = '' if curTime - @lastCharTime > 700
          
      @search += char.toLowerCase()
      @lastCharTime = curTime
      search = @search
      file = @collection.find (file) ->
        -1 != file.get('name').toLowerCase().indexOf search
      file?.view?.select()

    moveSelection: (delta) ->
      selectedFile = @selectedFile()
      index = @collection.indexOf selectedFile
      index += delta
      index = 0 if index < 0
      index = @collection.size() - 1 if index >= @collection.size()
      @collection.at(index).view.select()
      event.preventDefault()

    onResize: ->
      # TODO: Bad, bad solution. Check out some CSS grid layout.
      #width = @el.offsetWidth
      #@cols = ~~ (width / @MIN_WIDTH)
      #@$('.file-item').css width: "#{(100/@cols).toFixed(3)}%"

    getParent: (item, path) ->
      return item if !path.length || path.length == 1 && path[0] == item.get('path')
      items = item.get('items')
      
      found = false
      items.each (subitem) =>
        console.log('compare', subitem.get('type'), subitem.get('path'), path[0]);
        if subitem.get('type') == 'dir' && subitem.get('path') == path[0]
          found = @getParent subitem, path[1..]
      return found if found
      
      newitem = new FileItem path: path[0], type: 'dir', items: new FileItemList
      items.add newitem
      
      return @getParent newitem, path[1..]

    onAddFile: (file) ->
      path = file.get('url').replace /[^\/]*$/, ''
      parent = @getParent @root, path.split('/')
      
      fileitem = new FileItem type: 'file', file: file
      parent.get('items').add fileitem
      tm('addfile')
      
      ###
      view = new FileView model: file
      view.on 'select', @onSelect
      file.view = view
      $(view.render().el).css width: @colWidth if @colWidth
      @$el.append view.render().el
      ###

    onAddAllFiles: ->
      @collection.each @onAddFile, @
      @onResize()
      
    selectedFile: ->
      @collection.find (file) -> file.view.selected

    onSelect: (file) ->
      selectedFile = @selectedFile()
      return if !selectedFile || selectedFile == file
      selectedFile.view.select false
      offset = file.view.el.offsetTop - 5
      scroll = @el.scrollTop
      if offset < scroll
        @el.scrollTop = offset
      if offset - @el.offsetHeight + ITEM_HEIGHT > @el.scrollTop
        @el.scrollTop = offset - @el.offsetHeight + ITEM_HEIGHT


  module.exports = FileBrowser