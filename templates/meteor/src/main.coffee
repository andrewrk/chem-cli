chem = require 'chem'

{vec2d, Engine, Sprite, Label, Batch, button} = chem
ani = chem.resources.animations

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
      ani.star_small
      ani.star_big
    ]
    @imgMeteor = [
      ani.meteor_small
      ani.meteor_big
    ]
    @ship = new Sprite ani.ship,
      batch: @batch
      pos: vec2d(0, @engine.size.y / 2)
      zOrder: 2
    @shipVel = vec2d()

    @meteorInterval = 0.3
    @nextMeteorAt = @meteorInterval

    @starInterval = 0.1
    @nextStarAt = @starInterval

    @score = 0

    @scoreLabel = new Label "Score: 0",
      batch: @batch
      pos: vec2d(0, 30)
      zOrder: 3
      font: "30px Arial"
      fillStyle: "#ffffff"
    @gameOverLabel = new Label "GAME OVER",
      batch: @batch
      pos: @engine.size.scaled(0.5)
      textAlign: 'center'
      zOrder: 3
      font: "30px Arial"
      fillStyle: "#ffffff"
      visible: false
    @spaceToRestartLabel = new Label "space to restart",
      batch: @batch
      pos: @engine.size.scaled(0.5).offset(0, 70)
      textAlign: 'center'
      zOrder: 3
      font: "18px Arial"
      fillStyle: "#ffffff"
      visible: false
    @fpsLabel = @engine.createFpsLabel()

  start: ->
    @engine.on('draw', @draw)
    @engine.on('update', @update)

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
      @scoreLabel.text = "Score: #{Math.floor(@score)}"

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
    @gameOverLabel.setVisible(true)
    @spaceToRestartLabel.setVisible(true)
    @ship.setAnimation(ani.explosion)
    @ship.setFrameIndex(0)
    @ship.on 'animationend', => @ship.delete()

  draw: (context) =>
    context.fillStyle = '#000000'
    context.fillRect 0, 0, @engine.size.x, @engine.size.y
    @batch.draw context
    @fpsLabel.draw context


canvas = document.getElementById("game")
engine = new Engine(canvas)
engine.showLoadProgressBar()
engine.start()
canvas.focus()
chem.resources.on 'ready', ->
  game = new Game(engine)
  game.start()
