chem = require 'chem'

{vec2d, Engine, Sprite, Batch, button} = chem

randInt = (min, max) -> Math.floor(min + Math.random() * (max - min + 1))

class MovingSprite
  constructor: (@sprite, @vel) ->
    @gone = false

  delete: ->
    @gone = true
    @sprite?.delete()
    @sprite = null

class Game
  constructor: (@engine) ->
    @hadGameOver = false
    @stars = []
    @meteors = []
    @batch = new Batch()
    @imgStar = [
      'star_small'
      'star_big'
    ]
    @imgMeteor = [
      'meteor_small'
      'meteor_big'
    ]
    @ship = new Sprite 'ship',
      batch: @batch
      pos: vec2d(0, @engine.size.y / 2)
      zOrder: 2
    @shipVel = vec2d()

    @meteorInterval = 0.3
    @nextMeteorAt = @meteorInterval

    @starInterval = 0.1
    @nextStarAt = @starInterval

    @score = 0

  start: ->
    @engine.on('draw', @draw)
    @engine.on('update', @update)
    @engine.start()

  createStar: ->
    sprite = new Sprite @imgStar[randInt(0, 1)],
      batch: @batch
      pos: vec2d(@engine.size.x, randInt(0, @engine.size.y))
      zOrder: 0
    obj = new MovingSprite(sprite, vec2d(-400 + Math.random() * 200, 0))
    @stars.push(obj)

  createMeteor: ->
    sprite = new Sprite @imgMeteor[randInt(0, 1)],
      batch: @batch
      pos: vec2d(@engine.size.x, randInt(0, @engine.size.y))
      zOrder: 1
    obj = new MovingSprite(sprite, vec2d(-600 + Math.random() * 400, -200 + Math.random() * 400))
    @meteors.push(obj)

  update: (dt) =>
    if @hadGameOver
      if @engine.buttonJustPressed(button.KeySpace)
        location.href = location.href
        return
    else
      scorePerSec = 60
      @score += scorePerSec * dt

    @nextMeteorAt -= dt
    if @nextMeteorAt <= 0
      @nextMeteorAt = @meteorInterval
      @createMeteor()

    if not @hadGameOver
      @meteorInterval -= dt * 0.01

    @nextStarAt -= dt
    if @nextStarAt <= 0
      @nextStarAt = @starInterval
      @createStar()

    for listName in ['stars', 'meteors']
      cleanedList = []
      objList = @[listName]
      for obj in objList
        if not obj.gone
          obj.sprite.pos.add(obj.vel.scaled(dt))
          if obj.sprite.getRight() < 0
            obj.delete()
          else
            cleanedList.push(obj)
      @[listName] = cleanedList

    if not @hadGameOver
      shipAccel = 600

      if @engine.buttonState(button.KeyLeft)
        @shipVel.x -= shipAccel * dt
      if @engine.buttonState(button.KeyRight)
        @shipVel.x += shipAccel * dt
      if @engine.buttonState(button.KeyUp)
        @shipVel.y -= shipAccel * dt
      if @engine.buttonState(button.KeyDown)
        @shipVel.y += shipAccel * dt

    @ship.pos.add(@shipVel.scaled(dt))

    if not @hadGameOver
      corner = @ship.getTopLeft()
      if corner.x < 0
        @ship.setLeft(0)
        @shipVel.x = 0
      if corner.y < 0
        @ship.setTop(0)
        @shipVel.y = 0
      corner = @ship.getBottomRight()
      if corner.x > @engine.size.x
        @ship.setRight(@engine.size.x)
        @shipVel.x = 0
      if corner.y > @engine.size.y
        @ship.setBottom(@engine.size.y)
        @shipVel.y = 0

      for meteor in @meteors
        if meteor.gone
          continue
        if @ship.isTouching(meteor.sprite)
          @gameOver()
          break
    return

  gameOver: ->
    if @hadGameOver
      return
    @hadGameOver = true
    @ship.setAnimationName('explosion')
    @ship.setFrameIndex(0)
    @ship.on 'animationend', => @ship.delete()

  draw: (context) =>
    context.fillStyle = '#000000'
    context.fillRect 0, 0, @engine.size.x, @engine.size.y
    @engine.draw @batch
    context.fillStyle = "#ffffff"
    context.font = "30px Arial"
    context.fillText "Score: #{Math.floor(@score)}", 0, 30
    if @hadGameOver
      context.fillText "GAME OVER", @engine.size.x / 2, @engine.size.y / 2
      context.font = "18px Arial"
      context.fillText "space to restart", \
        @engine.size.x / 2, \
        @engine.size.y / 2 + 70

    context.font = "12px Arial"
    context.fillStyle = '#ffffff'
    @engine.drawFps()


chem.onReady ->
  canvas = document.getElementById("game")
  engine = new Engine(canvas)
  canvas.focus()
  game = new Game(engine)
  game.start()

