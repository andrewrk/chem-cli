client_src = [
  "vec2d.coffee"
  "engine.coffee"
  "game.coffee"
]
client_out = "./public/game.js"
spritesheet_out = "./public/spritesheet.png"
animations_json_out = "./public/animations.json"


coffee = "./node_modules/coffee-script/bin/coffee"
img_path = "./assets/img"

{spawn} = require("child_process")
exec = (cmd, args=[], cb=->) ->
  bin = spawn(cmd, args)
  bin.stdout.on 'data', (data) ->
    process.stdout.write data
  bin.stderr.on 'data', (data) ->
    process.stderr.write data
  bin.on 'exit', cb

extend = (obj, args...) ->
  for arg in args
    obj[prop] = val for prop, val of arg
  obj

sign = (n) -> if n > 0 then 1 else if n < 0 then -1 else 0

Canvas = require('canvas')
Image = Canvas.Image
fs = require('fs')
{Vec2d} = require('./vec2d')
{Spritesheet} = require('./spritesheet')
createSpritesheet = ->
  # gather data about all image files
  # and place into array
  {_default, animations} = require("./animations")
  frame_list = []
  for name, anim of animations
    # apply the default animation properties
    animations[name] = anim = extend {}, _default, anim

    # change the frames array into an array of objects
    files = anim.frames
    anim.frames = []

    for file in files
      image = new Image()
      image.src = fs.readFileSync("#{img_path}/#{file}")
      frame =
        image: image
        size: new Vec2d(image.width, image.height)
        filename: file
        pos: new Vec2d(0, 0)
      frame_list.push frame
      anim.frames.push frame

    if anim.anchor is "center"
      anim.anchor = anim.frames[0].size.scaled(0.5).floor()

  sheet = new Spritesheet(frame_list)
  sheet.calculatePositions()

  # render to png
  canvas = new Canvas(sheet.size.x, sheet.size.y)
  context = canvas.getContext('2d')
  for frame in frame_list
    context.drawImage frame.image, frame.pos.x, frame.pos.y
  out = fs.createWriteStream(spritesheet_out)
  stream = canvas.createPNGStream()
  stream.on 'data', (chunk) -> out.write chunk

  # strip properties from animations that we do not wish to commit to disk
  for name, anim of animations
    for frame in anim.frames
      delete frame.image
      delete frame.filename

  # render json animation data
  fs.writeFileSync animations_json_out, JSON.stringify(animations, null, 4), 'utf8'

task 'spritesheet', createSpritesheet

compile = (watch_flag="") ->
  exec coffee, ["-#{watch_flag}cbj", client_out].concat(client_src)

task 'watch', -> compile('w')

task 'build', ->
  compile()
  createSpritesheet()