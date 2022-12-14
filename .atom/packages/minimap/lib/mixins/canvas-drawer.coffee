Mixin = require 'mixto'

module.exports =
class CanvasDrawer extends Mixin
  initializeCanvas: ->
    @canvas = document.createElement('canvas')
    @context = @canvas.getContext('2d')
    @canvas.webkitImageSmoothingEnabled = false
    @pendingChanges ?= []

    @offscreenCanvas = document.createElement('canvas')
    @offscreenContext = @offscreenCanvas.getContext('2d')

  updateCanvas: ->
    firstRow = @minimap.getFirstVisibleScreenRow()
    lastRow = @minimap.getLastVisibleScreenRow()
    intactRanges = @computeIntactRanges(firstRow, lastRow)

    @context.clearRect(0,0,@canvas.width, @canvas.height)

    if intactRanges.length is 0
      @drawLines(@context, firstRow, lastRow, 0)
    else
      for intact in intactRanges
        @copyBitmapPart(@context, @offscreenCanvas, intact.domStart, intact.start-firstRow, intact.end-intact.start)
      @fillGapsBetweenIntactRanges(@context, intactRanges, firstRow, lastRow)

    # copy displayed canvas to offscreen canvas
    @offscreenCanvas.width = @canvas.width
    @offscreenCanvas.height = @canvas.height
    @offscreenContext.drawImage(@canvas, 0, 0)
    @offscreenFirstRow = firstRow
    @offscreenLastRow = lastRow

  #     ######   #######  ##        #######  ########   ######
  #    ##    ## ##     ## ##       ##     ## ##     ## ##    ##
  #    ##       ##     ## ##       ##     ## ##     ## ##
  #    ##       ##     ## ##       ##     ## ########   ######
  #    ##       ##     ## ##       ##     ## ##   ##         ##
  #    ##    ## ##     ## ##       ##     ## ##    ##  ##    ##
  #     ######   #######  ########  #######  ##     ##  ######

  getTextOpacity: -> @textOpacity

  # Returns the default text color for an editor content.
  #
  # The color value is directly read from the `TextEditorView` computed
  # styles.
  #
  # Returns a {String}.
  getDefaultColor: ->
    color = @retrieveStyleFromDom(['.editor'], 'color', false, false)
    @transparentize(color, @getTextOpacity())

  # Returns the text color for the passed-in `token` object.
  #
  # The color value is read from the DOM by creating a node structure
  # that match the token `scope` property.
  #
  # token - A token {Object}.
  #
  # Returns a {String}.
  getTokenColor: (token) ->
    #Retrieve color from cache if available
    flatScopes = (token.scopeDescriptor or token.scopes).join()
    @retrieveTokenColorFromDom(token)

  # Returns the background color for the passed-in `decoration` object.
  #
  # The color value is read from the DOM by creating a node structure
  # that match the decoration `scope` property unless the decoration
  # provides its own `color` property.
  #
  # decoration - A `Decoration` object.
  #
  # Returns a {String}.
  getDecorationColor: (decoration) ->
    properties = decoration.getProperties()
    return properties.color if properties.color?
    @retrieveDecorationColorFromDom(decoration)

  # Internal: Returns the text color for the passed-in token.
  #
  # token - A token {Object}.
  #
  # Returns a {String}.
  retrieveTokenColorFromDom: (token) ->
    # This is quite an expensive operation so results are cached in getTokenColor.
    scopes = (token.scopeDescriptor or token.scopes)
    color = @retrieveStyleFromDom(scopes, 'color')
    @transparentize(color, @getTextOpacity())

  # Internal: Returns the background color for the passed-in decoration.
  #
  # decoration - A `Decoration` object.
  #
  # Returns a {String}.
  retrieveDecorationColorFromDom: (decoration) ->
    @retrieveStyleFromDom(decoration.getProperties().scope.split(/\s+/), 'background-color', false)

  # Internal: Converts a `rgb(...)` color into a `rgba(...)` color
  # with the specified opacity.
  #
  # color - The {String} of the color to modify.
  # opacity - The opacity {Number} to apply to the color.
  #
  # Returns a {String}.
  transparentize: (color, opacity=1) ->
    color.replace('rgb(', 'rgba(').replace(')', ", #{opacity})")

  #    ########  ########     ###    ##      ##
  #    ##     ## ##     ##   ## ##   ##  ##  ##
  #    ##     ## ##     ##  ##   ##  ##  ##  ##
  #    ##     ## ########  ##     ## ##  ##  ##
  #    ##     ## ##   ##   ######### ##  ##  ##
  #    ##     ## ##    ##  ##     ## ##  ##  ##
  #    ########  ##     ## ##     ##  ###  ###

  # Internal: Draws lines on the passed-in `context`.
  #
  # The lines range to draw is specified by the `firstRow` and `lastRow`
  # parameters.
  #
  # context - The canvas context {Object} into which drawing the lines.
  # firstRow - The starting row {Number} of the lines range to draw.
  # endRow - The ending row {Number} of the lines range to draw.
  # offsetRow - The offset {Number} to apply to rows index.
  drawLines: (context, firstRow, lastRow, offsetRow) ->
    return if firstRow > lastRow

    lines = @getTextEditor().tokenizedLinesForScreenRows(firstRow, lastRow)
    lineHeight = @minimap.getLineHeight() * devicePixelRatio
    charHeight = @minimap.getCharHeight() * devicePixelRatio
    charWidth = @minimap.getCharWidth() * devicePixelRatio
    canvasWidth = @canvas.width
    displayCodeHighlights = @displayCodeHighlights
    decorations = @minimap.decorationsForScreenRowRange(firstRow, lastRow)

    line = lines[0]

    # Whitespaces can be substituted by other characters so we need
    # to replace them when that's the case.
    if line? and line.invisibles?
      re = ///
      #{line.invisibles.cr}|
      #{line.invisibles.eol}|
      #{line.invisibles.space}|
      #{line.invisibles.tab}
      ///g

    for line, row in lines
      x = 0
      y = offsetRow + row
      screenRow = firstRow + row
      y0 = y*lineHeight

      # Line decorations are first drawn on the canvas.
      lineDecorations = @minimap.decorationsByTypesForRow(screenRow, 'line', decorations)
      @drawLineDecorations(context, lineDecorations, y0, canvasWidth, lineHeight) if lineDecorations.length

      # Then comes the highlight decoration with `highlight-under` type.
      highlightDecorations = @minimap.decorationsByTypesForRow(firstRow + row, 'highlight-under', decorations)
      for decoration in highlightDecorations
        @drawHighlightDecoration(context, decoration, y, screenRow, lineHeight, charWidth, canvasWidth)

      # Then the line tokens are drawn
      for token in line.tokens
        w = token.screenDelta
        unless token.isOnlyWhitespace()
          color = if displayCodeHighlights
            @getTokenColor(token)
          else
            @getDefaultColor()

          value = token.value
          value = value.replace(re, ' ') if re?

          x = @drawToken(context, value, color, x, y0, charWidth, charHeight)
        else
          x += w * charWidth

        break if x > canvasWidth

      # Finally the highlight over decorations are drawn.
      highlightDecorations = @minimap.decorationsByTypesForRow(firstRow + row, 'highlight', 'highlight-over', decorations)
      for decoration in highlightDecorations
        @drawHighlightDecoration(context, decoration, y, screenRow, lineHeight, charWidth, canvasWidth)

    context.fill()

  # Internal: Draws a single token on the given context.
  #
  # context - The canvas context object onto which draw the token.
  # text - The {String} text of the token.
  # color - The {String} color of the token.
  # x - The {Number} position on the x axis at which render the token.
  # y - The {Number} position on the y axis at which render the token.
  # charWidth - The char width {Number}.
  # charHeight - The char height {Number}.
  #
  # Returns a {Number} that correspond to the new x position after the render.
  drawToken: (context, text, color, x, y, charWidth, charHeight) ->
    context.fillStyle = color
    chars = 0
    for char in text
      if /\s/.test char
        if chars > 0
          context.fillRect(x-(chars * charWidth), y, chars*charWidth, charHeight)
        chars = 0
      else
        chars++

      x += charWidth

    context.fillRect(x-(chars * charWidth), y, chars*charWidth, charHeight) if chars > 0

    x

  drawLineDecorations: (context, decorations, y, canvasWidth, lineHeight) ->
    for decoration in decorations
      context.fillStyle = @getDecorationColor(decoration)
      context.fillRect(0,y,canvasWidth,lineHeight)


  # Internal: Draws a highlight decoration on the passed-in context.
  #
  # It renders only the part of the highlight corresponding to the specified
  # row.
  #
  # context - The canvas context object.
  # decoration - The `Decoration` object to render.
  # y - The {Number} position on the y axis at which render the decoration.
  # screenRow - The row {Number} corresponding to the rendered row.
  # lineHeight - The {Number} for the line height.
  # charWidth - The {Number} for the character width.
  # canvasWidth - The {Number} of the canvas width.
  drawHighlightDecoration: (context, decoration, y, screenRow, lineHeight, charWidth, canvasWidth) ->
    context.fillStyle = @getDecorationColor(decoration)
    range = decoration.getMarker().getScreenRange()
    rowSpan = range.end.row - range.start.row

    if rowSpan is 0
      colSpan = range.end.column - range.start.column
      context.fillRect(range.start.column*charWidth,y*lineHeight,colSpan*charWidth,lineHeight)
    else
      if screenRow is range.start.row
        x = range.start.column * charWidth
        context.fillRect(x,y*lineHeight,canvasWidth-x,lineHeight)
      else if screenRow is range.end.row
        context.fillRect(0,y*lineHeight,range.end.column * charWidth,lineHeight)
      else
        context.fillRect(0,y*lineHeight,canvasWidth,lineHeight)

  # Internal: Copy a part of the offscreen bitmap into the onscreen one to
  # reduce the amount of rendered lines during scroll.
  #
  # context - The canvas context object.
  # bitmapCanvas - The source bitmap.
  # srcRow - The row {Number} on the source bitmap.
  # destRow - The row {Number} on the destination bitmap.
  # rowCount - The {Number} of rows to copy.
  copyBitmapPart: (context, bitmapCanvas, srcRow, destRow, rowCount) ->
    lineHeight = @minimap.getLineHeight() * devicePixelRatio
    context.drawImage(bitmapCanvas,
        0, srcRow * lineHeight,
        bitmapCanvas.width, rowCount * lineHeight,
        0, destRow * lineHeight,
        bitmapCanvas.width, rowCount * lineHeight)

  #    ########     ###    ##    ##  ######   ########  ######
  #    ##     ##   ## ##   ###   ## ##    ##  ##       ##    ##
  #    ##     ##  ##   ##  ####  ## ##        ##       ##
  #    ########  ##     ## ## ## ## ##   #### ######    ######
  #    ##   ##   ######### ##  #### ##    ##  ##             ##
  #    ##    ##  ##     ## ##   ### ##    ##  ##       ##    ##
  #    ##     ## ##     ## ##    ##  ######   ########  ######

  ### Internal ###

  # Renders the lines between the intact ranges when an update has pending
  # changes.
  #
  # context - The canvas context object.
  # intactRanges - The {Array} of intact ranges.
  # firstRow - The first visible row index {Number}.
  # lastRow - The last visible row index {Number}.
  fillGapsBetweenIntactRanges: (context, intactRanges, firstRow, lastRow) ->
    currentRow = firstRow
    # intactRanges is sorted, we can safely fill between ranges
    for intact in intactRanges
      @drawLines(context, currentRow, intact.start-1, currentRow-firstRow)
      currentRow = intact.end
    if currentRow <= lastRow
      @drawLines(context, currentRow, lastRow, currentRow-firstRow)

  # Computes the ranges that are not affected by the current pending changes.
  #
  # firstRow - The first visible row index {Number}.
  # lastRow - The last visible row index {Number}.
  #
  # Returns an??{Array} of ranges.
  computeIntactRanges: (firstRow, lastRow) ->
    return [] if !@offscreenFirstRow? and !@offscreenLastRow?

    intactRanges = [{start: @offscreenFirstRow, end: @offscreenLastRow, domStart: 0}]

    for change in @pendingChanges
      newIntactRanges = []
      for range in intactRanges
        if isNaN(change.screenDelta)
          change.screenDelta = change.end - change.start

        if change.end < range.start and change.screenDelta != 0
          newIntactRanges.push(
            start: range.start + change.screenDelta
            end: range.end + change.screenDelta
            domStart: range.domStart
          )
        else if change.end < range.start or change.start > range.end
          newIntactRanges.push(range)
        else
          if change.start > range.start
            newIntactRanges.push(
              start: range.start
              end: change.start - 1
              domStart: range.domStart)
          if change.end < range.end
            newIntactRanges.push(
              start: change.end + change.screenDelta + 1
              end: range.end + change.screenDelta
              domStart: range.domStart + change.end + 1 - range.start
            )

        intactRange = newIntactRanges[newIntactRanges.length - 1]
        if intactRange? and (isNaN(intactRange.end) or isNaN(intactRange.start))
          debugger

      intactRanges = newIntactRanges

    @truncateIntactRanges(intactRanges, firstRow, lastRow)

    @pendingChanges = []

    intactRanges

  # Truncates the intact ranges so that they doesn't expand past the visible
  # area of the minimap.
  #
  # intactRanges - The {Array} of ranges to truncate.
  # firstRow - The first visible row index {Number}.
  # lastRow - The last visible row index {Number}.
  #
  # Returns an {Array} of ranges.
  truncateIntactRanges: (intactRanges, firstRow, lastRow) ->
    i = 0
    while i < intactRanges.length
      range = intactRanges[i]
      if range.start < firstRow
        range.domStart += firstRow - range.start
        range.start = firstRow
      if range.end > lastRow
        range.end = lastRow
      if range.start >= range.end
        intactRanges.splice(i--, 1)
      i++
    intactRanges.sort (a, b) -> a.domStart - b.domStart
