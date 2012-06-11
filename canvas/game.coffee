do ->
  atom_size = new Vec2d(32, 32)
  atom_radius = atom_size.x / 2

  max_bias = 400

  sign = (x) ->
    if x > 0
      1
    else if x < 0
      -1
    else
      0

  randInt = (min, max) -> Math.floor(min + Math.random() * (max - min + 1))

  Collision =
    Default: 0
    Claw: 1
    Atom: 2

  Control =
    MoveLeft: 0
    MoveRight: 1
    MoveUp: 2
    MoveDown: 3
    FireMain: 4
    FireAlt: 5
    SwitchToGrapple: 6
    SwitchToRay: 7
    SwitchToLazer: 8
    COUNT: 9
    MOUSE_OFFSET: 255

  class Atom
    @flavor_count = 6

    @atom_for_shape = {}
    @max_bonds = 2

    @id_count = 0

    constructor: (pos, @flavor_index, @sprite, @space) ->
      body = pymunk.Body(10, 100000)
      body.position = pos
      @shape = pymunk.Circle(body, atom_radius)
      @shape.friction = 0.5
      @shape.elasticity = 0.05
      @shape.collision_type = Collision.Atom
      @space.add(body, @shape)

      Atom.atom_for_shape[@shape] = this
      # atom => joint
      @bonds = {}
      @marked_for_deletion = false
      @rogue = false

      @id = Atom.id_count
      Atom.id_count += 1

    bondTo: (other) ->
      # already bonded
      if @bonds[other]?
        return false
      # too many bonds already
      if len(@bonds) >= Atom.max_bonds or len(other.bonds) >= Atom.max_bonds
        return false
      # wrong color
      if @flavor_index isnt other.flavor_index
        return false

      joint = pymunk.PinJoint(@shape.body, other.shape.body)
      joint.distance = atom_radius * 2.5
      joint.max_bias = max_bias
      @bonds[other] = joint
      other.bonds[this] = joint
      @space.add(joint)

      return true

    bondLoop: ->
      # returns null or a list of atoms in the bond loop which includes itself
      if len(@bonds) isnt 2
        return null
      seen = {this: true}
      [atom, dest] = @bonds.keys()
      loop
        seen[atom] = true
        if atom is dest
          return seen.keys()
        found = false
        for next_atom, joint of atom.bonds
          if not seen[next_atom]?
            atom = next_atom
            found = true
            break
        if not found
          return null

    unbond: ->
      for atom, joint of @bonds
        delete atom.bonds[this]
        @space.remove(joint)
      @bonds = {}

    cleanUp: ->
      @unbond()
      @space.remove(@shape)
      if not @rogue
        @space.remove(@shape.body)
      delete Atom.atom_for_shape[@shape]
      @sprite.delete()
      @sprite = null

  class Bomb
    @radius = 16
    @size = new Vec2d(@radius*2, @radius*2)

    constructor: (pos, @sprite, @space, @timeout) ->
      body = pymunk.Body(50, 10)
      body.position = pos
      @shape = pymunk.Circle(body, Bomb.radius)
      @shape.friction = 0.7
      @shape.elasticity = 0.02
      @shape.collision_type = Collision.Default
      @space.add(body, @shape)

    tick: (dt) ->
      @timeout -= dt

    cleanUp: ->
      @space.remove(@shape, @shape.body)
      @sprite.delete()
      @sprite = null

  class Rock
    @radius = 16
    @size = new Vec2d(@radius*2, @radius*2)

    constructor: (pos, @sprite, @space) ->
      body = pymunk.Body(70, 100000)
      body.position = pos
      @shape = pymunk.Circle(body, Rock.radius)
      @shape.friction = 0.9
      @shape.elasticity = 0.01
      @shape.collision_type = Collision.Default
      @space.add(body, @shape)

    tick: (dt) ->

    cleanUp: ->
      @space.remove(@shape, @shape.body)
      @sprite.delete()
      @sprite = null

  class Tank
    constructor: (@pos, @dims, @game, @tank_index) ->
      @size = @dims * atom_size
      @other_tank = null
      @atoms = set()
      @bombs = set()
      @rocks = set()

      @queued_asplosions = []

      @min_power = params.power or 3

      @sprite_arm = new engine.Sprite('arm', batch=@game.batch, group=@game.group_fg)
      @sprite_man = new engine.Sprite('still', batch=@game.batch, group=@game.group_main)
      @sprite_claw = new engine.Sprite('claw', batch=@game.batch, group=@game.group_main)

      @space = pymunk.Space()
      @space.gravity = new Vec2d(0, -400)
      @space.damping = 0.99
      @space.add_collision_handler(Collision.Claw, Collision.Default, post_solve=@clawHitSomething)
      @space.add_collision_handler(Collision.Claw, Collision.Atom, post_solve=@clawHitSomething)
      @space.add_collision_handler(Collision.Atom, Collision.Atom, post_solve=@atomHitAtom)

      @initControls()
      @mouse_pos = new Vec2d(0, 0)
      @man_dims = new Vec2d(1, 2)
      @man_size = new Vec2d(@man_dims.mult(atom_size))

      @time_between_drops = params.fastatoms or 1
      @time_until_next_drop = 0

      @initWalls()
      @initCeiling()

      @initMan()

      @initGuns()
      @arm_offset = new Vec2d(13, 43)
      @arm_len = 24
      @computeArmPos()

      @closest_atom = null

      @equipped_gun = Control.SwitchToGrapple
      @gun_animations = {}
      @gun_animations[Control.SwitchToGrapple] = "arm"
      @gun_animations[Control.SwitchToRay] = "raygun"
      @gun_animations[Control.SwitchToLazer] = "lazergun"

      @bond_queue = []

      @points = 0
      @points_to_crush = 50

      @point_end = new Vec2d(0.000001, 0.000001)
      
      # if you have this many atoms per tank y or more, you lose
      @lose_ratio = 95 / 300

      @tank_index ?= randInt(0, 1)
      @sprite_tank = new engine.Sprite("tank#{tank_index}", batch=@game.batch, group=@game.group_main)

      @game_over = false
      @winner = null

      @atom_drop_enabled = true
      @enable_point_calculation = true
      @sfx_enabled = true

    initGuns: ->
      @claw_in_motion = false
      @sprite_claw.visible = false
      @claw_radius = 8
      @claw_shoot_speed = 1200
      @min_claw_dist = 60
      @claw_pins_to_add = null
      @claw_pins = null
      @claw_attached = false
      @want_to_remove_claw_pin = false
      @want_to_retract_claw = false

      @lazer_timeout = 0.5
      @lazer_recharge = 0
      @lazer_line = null
      @lazer_line_timeout = 0
      @lazer_line_timeout_start = 0.2

      @ray_atom = null
      @ray_shoot_speed = 900

    initControls: ->
      @controls = {}
      @controls[Engine.Key.A] = Control.MoveLeft
      @controls[Engine.Key.D] = Control.MoveRight
      @controls[Engine.Key.W] = Control.MoveUp
      @controls[Engine.Key.S] = Control.MoveDown

      @controls[Engine.Key._1] = Control.SwitchToGrapple
      @controls[Engine.Key._2] = Control.SwitchToRay
      @controls[Engine.Key._3] = Control.SwitchToLazer

      @controls[Control.MOUSE_OFFSET+Engine.Mouse.Left] = Control.FireMain
      @controls[Control.MOUSE_OFFSET+Engine.Mouse.Right] = Control.FireAlt

      if params.keyboard is 'dvorak'
        @controls[Engine.Key.A] = Control.MoveLeft
        @controls[Engine.Key.E] = Control.MoveRight
        @controls[Engine.Key.Comma] = Control.MoveUp
        @controls[Engine.Key.S] = Control.MoveDown
      else if params.keyboard is 'colemak'
        @controls[Engine.Key.A] = Control.MoveLeft
        @controls[Engine.Key.S] = Control.MoveRight
        @controls[Engine.Key.W] = Control.MoveUp
        @controls[Engine.Key.R] = Control.MoveDown

      @control_state = (false for x in [0...Control.COUNT])
      @let_go_of_fire_main = true
      @let_go_of_fire_alt = true


    update: (dt) ->
      @adjustCeiling(dt)
      if @atom_drop_enabled
        @computeDrops(dt)

      # check if we died
      ratio = len(@atoms) / (@ceiling.body.position.y - @size.y / 2)
      if ratio > @lose_ratio or @ceiling.body.position.y < @man_size.y
        @lose()

      # process bombs
      for bomb in list(@bombs)
        bomb.tick(dt)
        if bomb.timeout <= 0
          # physics explosion
          # loop over every object in the space and apply an impulse
          for shape in @space.shapes
            vector = shape.body.position - bomb.shape.body.position
            dist = vector.get_length()
            direction = vector.normalized()
            power = 6000
            damp = 1 - dist / 800
            shape.body.apply_impulse(direction * power * damp)

          # explosion animation
          sprite = new engine.Sprite("bombsplode", batch=@game.batch, group=@game.group_fg)
          sprite.setPosition(@pos.plus(bomb.shape.body.position))
          do (sprite) ->
            removeBombSprite = -> sprite.delete()
          sprite.on("animation_end", removeBombSprite)
          @removeBomb(bomb)

          @playSfx("explode")

      @processInput(dt)


      # queued actions
      @processQueuedActions()

      @computeAtomPointedAt()

      # update physics
      step_count = Math.floor(dt / (1 / game_fps))
      if step_count < 1
        step_count = 1
      delta = dt / step_count
      for i in [0...step_count]
        @space.step(delta)

      if @want_to_remove_claw_pin
        @space.remove(@claw_pins)
        @claw_pins = null
        @want_to_remove_claw_pin = false

      @computeArmPos()

      # apply our constraints
      # man can't rotate
      @man.body.angle = @man_angle


    removeAtom: (atom) ->
      atom.cleanUp()
      @atoms.remove(atom)

    removeBomb: (bomb) ->
      bomb.cleanUp()
      @bombs.remove(bomb)

    initWalls: ->
      # add the walls of the tank to space
      r = 50
      borders = [
        # right wall
        [new Vec2d(@size.x + r, @size.y), new Vec2d(@size.x + r, 0)],
        # bottom wall
        [new Vec2d(@size.x, -r), new Vec2d(0, -r)],
        # left wall
        [new Vec2d(-r, 0), new Vec2d(-r, @size.y)],
      ]
      for [p1, p2] in borders
        shape = pymunk.Segment(pymunk.Body(), p1, p2, r)
        shape.friction = 0.99
        shape.elasticity = 0.0
        shape.collision_type = Collision.Default
        @space.add(shape)

    initCeiling: ->
      # physics for ceiling
      body = pymunk.Body(10000, 100000)
      body.position = new Vec2d(@size.x / 2, @size.y * 1.5)
      @ceiling = pymunk.Poly.create_box(body, @size)
      @ceiling.collision_type = Collision.Default
      @space.add(@ceiling)
      # per second
      @max_ceiling_delta = 200

    adjustCeiling: (dt) ->
      # adjust the descending ceiling as necessary
      if @game.server?
        other_points = @other_tank.points
      else
        other_points = @game.survival_points
      adjust = (@points - other_points) / @points_to_crush * @size.y
      if adjust > 0
        adjust = 0
      if @game_over
        adjust = 0
      target_y = @size.y * 1.5 + adjust

      direction = sign(target_y - @ceiling.body.position.y)
      amount = @max_ceiling_delta * dt
      new_y = @ceiling.body.position.y + amount * direction
      new_sign = sign(target_y - new_y)
      if direction is -new_sign
        # close enough to just set
        @ceiling.body.position.y = target_y
      else
        @ceiling.body.position.y = new_y

    initMan: (pos, vel) ->
      if not pos?
        pos = new Vec2d(@size.x / 2, @man_size.y / 2)
      if not vel?
        vel = new Vec2d(0, 0)
      # physics for man
      shape = pymunk.Poly.create_box(pymunk.Body(20, 10000000), @man_size)
      shape.body.position = pos
      shape.body.velocity = vel
      shape.body.angular_velocity_limit = 0
      @man_angle = shape.body.angle
      shape.elasticity = 0
      shape.friction = 3.0
      shape.collision_type = Collision.Default
      @space.add(shape.body, shape)
      @man = shape


    computeArmPos: ->
      @arm_pos = @man.body.position - @man_size / 2 + @arm_offset
      @point_vector = (@mouse_pos - @arm_pos).normalized()
      @point_start = @arm_pos + @point_vector * @arm_len

    get_drop_pos: (size) ->
      return new Vec2d(
        random.random() * (@size.x - size.x) + size.x / 2,
        @ceiling.body.position.y - @size.y / 2 - size.y / 2,
      )


    drop_bomb: ->
      # drop a bomb
      pos = @get_drop_pos(Bomb.size)
      sprite = pyglet.sprite.Sprite(@game.animations.get("bomb"), batch=@game.batch, group=@game.group_main)
      timeout = randInt(1, 5)
      bomb = new Bomb(pos, sprite, @space, timeout)
      @bombs.add(bomb)

    drop_rock: ->
      # drop a rock
      pos = @get_drop_pos(Rock.size)
      sprite = pyglet.sprite.Sprite(@game.animations.get("rock"), batch=@game.batch, group=@game.group_main)
      rock = new Rock(pos, sprite, @space)
      @rocks.add(rock)

    computeDrops: (dt) ->
      if @game_over
        return
      @time_until_next_drop -= dt
      if @time_until_next_drop <= 0
        @time_until_next_drop += @time_between_drops
        # drop a random atom
        flavor_index = randInt(0, Atom.flavor_count-1)
        pos = @get_drop_pos(atom_size)
        atom = new Atom(pos, flavor_index, pyglet.sprite.Sprite(@game.atom_imgs[flavor_index], batch=@game.batch, group=@game.group_main), @space)
        @atoms.add(atom)


    lose: ->
      if @game_over
        return
      @game_over = true
      @winner = false
      @explode_atoms(list(@atoms), "atomfail")

      @sprite_man.image = @game.animations.get("defeat")
      @sprite_arm.visible = false

      @retract_claw()

      if @other_tank?
        @other_tank.win()
      @playSfx("defeat")

    win: ->
      if @game_over
        return

      @game_over = true
      @winner = true
      @explode_atoms(list(@atoms))

      @sprite_man.image = @game.animations.get("victory")
      @sprite_arm.visible = false

      @retract_claw()

      if @other_tank?
        @other_tank.lose()

      @playSfx("victory")

    explodeAtom: (atom, animation_name="asplosion") ->
      if atom is @ray_atom
        @ray_atom = null
      if @claw_pins? and @claw_pins[0].b is atom.shape.body
        @unattachClaw()
      atom.marked_for_deletion = true
      clearSprite = ->
        @removeAtom(atom)
      atom.sprite.image = @game.animations.get(animation_name)
      atom.sprite.set_handler("on_animation_end", clear_sprite)


    explodeAtoms: (atoms, animation_name="asplosion") ->
      for atom in atoms
        @explodeAtom(atom, animation_name)

    processInput: (dt) ->
      if @game_over
        return

      feet_start = @man.body.position - @man_size / 2 + new Vec2d(1, -1)
      feet_end = new Vec2d(feet_start.x + @man_size.x - 2, feet_start.y - 2)
      bb = pymunk.BB(feet_start.x, feet_end.y, feet_end.x, feet_start.y)
      ground_shapes = @space.bb_query(bb)
      grounded = len(ground_shapes) > 0

      grounded_move_force = 1000
      not_moving_x = abs(@man.body.velocity.x) < 5.0
      air_move_force = 200
      grounded_move_boost = 30
      air_move_boost = 0
      move_force = if grounded then grounded_move_force else air_move_force
      move_boost = if grounded then grounded_move_boost else air_move_boost
      max_speed = 200
      move_left = @control_state[Control.MoveLeft] and not @control_state[Control.MoveRight]
      move_right = @control_state[Control.MoveRight] and not @control_state[Control.MoveLeft]
      if move_left
        if @man.body.velocity.x >= -max_speed and @man.body.position.x - @man_size.x / 2 - 5 > 0
          @man.body.apply_impulse(new Vec2d(-move_force, 0), new Vec2d(0, 0))
          if @man.body.velocity.x > -move_boost and @man.body.velocity.x < 0
            @man.body.velocity.x = -move_boost
      else if move_right
        if @man.body.velocity.x <= max_speed and @man.body.position.x + @man_size.x / 2 + 3 < @size.x
          @man.body.apply_impulse(new Vec2d(move_force, 0), new Vec2d(0, 0))
          if @man.body.velocity.x < move_boost and @man.body.velocity.x > 0
            @man.body.velocity.x = move_boost

      negate = if @mouse_pos.x < @man.body.position.x then "-" else ""
      # jumping
      if grounded
        if move_left or move_right
          animation_name = "walk"
        else
          animation_name = "still"
      else
        animation_name = "jump"

      if @control_state[Control.MoveUp] and grounded
        animation_name = "jump"
        @sprite_man.image = @game.animations.get(negate + animation_name)
        @man.body.velocity.y = 100
        @man.body.apply_impulse(new Vec2d(0, 2000), new Vec2d(0, 0))
        # apply a reverse force upon the atom we jumped from
        power = 1000 / len(ground_shapes)
        for shape in ground_shapes
          shape.body.apply_impulse(new Vec2d(0, -power), new Vec2d(0, 0))
        @playSfx('jump')

      # point the man+arm in direction of mouse
      animation = @game.animations.get(negate + animation_name)
      if @sprite_man.image isnt animation
        @sprite_man.image = animation

      # selecting a different gun
      if @control_state[Control.SwitchToGrapple] and @equipped_gun isnt Control.SwitchToGrapple
        @equipped_gun = Control.SwitchToGrapple
        @playSfx('switch_weapon')
      else if @control_state[Control.SwitchToRay] and @equipped_gun isnt Control.SwitchToRay
        @equipped_gun = Control.SwitchToRay
        @playSfx('switch_weapon')
      else if @control_state[Control.SwitchToLazer] and @equipped_gun isnt Control.SwitchToLazer
        @equipped_gun = Control.SwitchToLazer
        @playSfx('switch_weapon')

      if @equipped_gun is Control.SwitchToGrapple
        if @claw_in_motion
          ani_name = "arm-flung"
        else
          ani_name = "arm"
        arm_animation = @game.animations.get(negate + ani_name)
      else
        arm_animation = @game.animations.get(negate + @gun_animations[@equipped_gun])

      if @sprite_arm.image isnt arm_animation
        @sprite_arm.image = arm_animation

      if @equipped_gun is Control.SwitchToGrapple
        claw_reel_in_speed = 400
        claw_reel_out_speed = 200
        if not @want_to_remove_claw_pin and not @want_to_retract_claw and @let_go_of_fire_main and @control_state[Control.FireMain] and not @claw_in_motion
          @let_go_of_fire_main = false
          @claw_in_motion = true
          @sprite_claw.visible = true
          body = pymunk.Body(mass=5, moment=1000000)
          body.position = new Vec2d(@point_start)
          body.angle = @point_vector.get_angle()
          body.velocity = @man.body.velocity + @point_vector * @claw_shoot_speed
          @claw = pymunk.Circle(body, @claw_radius)
          @claw.friction = 1
          @claw.elasticity = 0
          @claw.collision_type = Collision.Claw
          @claw_joint = pymunk.SlideJoint(@claw.body, @man.body, new Vec2d(0, 0), new Vec2d(0, 0), 0, @size.get_length())
          @claw_joint.max_bias = max_bias
          @space.add(body, @claw, @claw_joint)

          @playSfx('shoot_claw')

        if @sprite_claw.visible
          claw_dist = (@claw.body.position - @man.body.position).get_length()

        if @control_state[Control.FireMain] and @claw_in_motion
          if claw_dist < @min_claw_dist + 8
            if @claw_pins?
              @want_to_retract_claw = true
              @let_go_of_fire_main = false
            else if @claw_attached and @let_go_of_fire_main
              @retract_claw()
              @let_go_of_fire_main = false
          else if claw_dist > @min_claw_dist
            # prevent the claw from going back out once it goes in
            if @claw_attached and @claw_joint.max > claw_dist
              @claw_joint.max = claw_dist
            else
              @claw_joint.max -= claw_reel_in_speed * dt
              if @claw_joint.max < @min_claw_dist
                @claw_joint.max = @min_claw_dist
        if @control_state[Control.FireAlt] and @claw_attached
          @unattachClaw()

      @lazer_recharge -= dt
      if @equipped_gun is Control.SwitchToLazer
        if @lazer_line?
          @lazer_line[0] = @point_start
        if @control_state[Control.FireMain] and @lazer_recharge <= 0
          # IMA FIRIN MAH LAZERZ
          @lazer_recharge = @lazer_timeout
          @lazer_line = [@point_start, @point_end]
          @lazer_line_timeout = @lazer_line_timeout_start

          if @closest_atom?
            @explodeAtom(@closest_atom, "atomfail")
            @closest_atom = null

          @playSfx('lazer')
      @lazer_line_timeout -= dt
      if @lazer_line_timeout <= 0
        @lazer_line = null

      if @ray_atom?
        # move the atom closer to the ray gun
        vector = @point_start - @ray_atom.shape.body.position
        delta = vector.normalized() * 1000 * dt
        if delta.get_length() > vector.get_length()
          # just move the atom to final location
          @ray_atom.shape.body.position = @point_start
        else
          @ray_atom.shape.body.position += delta

      if @equipped_gun is Control.SwitchToRay
        if (@control_state[Control.FireMain] and @let_go_of_fire_main) and @closest_atom? and not @ray_atom? and not @closest_atom.marked_for_deletion
          # remove the atom from physics
          @ray_atom = @closest_atom
          @ray_atom.rogue = true
          @closest_atom = null
          @space.remove(@ray_atom.shape.body)
          @let_go_of_fire_main = false
          @ray_atom.unbond()

          @playSfx('ray')
        else if ((@control_state[Control.FireMain] and @let_go_of_fire_main) or @control_state[Control.FireAlt]) and @ray_atom?
          @space.add(@ray_atom.shape.body)
          @ray_atom.rogue = false
          if @control_state[Control.FireMain]
            # shoot it!!
            @ray_atom.shape.body.velocity = @man.body.velocity + @point_vector * @ray_shoot_speed
            @playSfx('lazer')
          else
            @ray_atom.shape.body.velocity = new Vec2d(@man.body.velocity)
          @ray_atom = null
          @let_go_of_fire_main = false

      if not @control_state[Control.FireMain]
        @let_go_of_fire_main = true

        if @want_to_retract_claw
          @want_to_retract_claw = false
          @retract_claw()
      if not @control_state[Control.FireAlt] and not @let_go_of_fire_alt
        @let_go_of_fire_alt = true

    processQueuedActions: ->
      if @claw_pins_to_add?
        @claw_pins = @claw_pins_to_add
        @claw_pins_to_add = null
        @space.add(@claw_pins)

      for [atom1, atom2] in @bond_queue
        if atom1.marked_for_deletion or atom2.marked_for_deletion
          continue
        if atom1 is @ray_atom or atom2 is @ray_atom
          continue
        if atom1.bonds is null or not atom2.bonds?
          print("Warning: trying to bond with an atom that doesn't exist anymore")
          continue
        if atom1.bondTo(atom2)
          bond_loop = atom1.bondLoop()
          if bond_loop?
            len_bond_loop = len(bond_loop)
            # make all the atoms in this loop disappear
            if @enable_point_calculation
              @points += len_bond_loop
            @explode_atoms(bond_loop)
            @queued_asplosions.append([atom1.flavor_index, len_bond_loop])

            @playSfx("merge")
          else
            @playSfx("bond")

      @bond_queue = []

    clawHitSomething: (space, arbiter) ->
      if @claw_attached
        return
      # bolt these bodies together
      [claw, shape] = arbiter.shapes
      pos = arbiter.contacts[0].position
      shape_anchor = pos - shape.body.position
      claw_anchor = pos - claw.body.position
      claw_delta = claw_anchor.normalized() * -(@claw_radius + 8)
      @claw.body.position += claw_delta
      @claw_pins_to_add = [
        pymunk.PinJoint(claw.body, shape.body, claw_anchor, shape_anchor),
        pymunk.PinJoint(claw.body, shape.body, new Vec2d(0, 0), new Vec2d(0, 0)),
      ]
      for claw_pin in @claw_pins_to_add
        claw_pin.max_bias = max_bias
      @claw_attached = true

      @playSfx("claw_hit")

    atomHitAtom: (space, arbiter) ->
      [atom1, atom2] = [Atom.atom_for_shape[shape] for shape in arbiter.shapes]
      # bond the atoms together
      if atom1.flavor_index is atom2.flavor_index
        @bond_queue.append([atom1, atom2])

    playSfx: (name) ->
      if @sfx_enabled and @game.sfx?
        @game.sfx[name].play()

    retract_claw: ->
      if not @sprite_claw.visible
        return
      @claw_in_motion = false
      @sprite_claw.visible = false
      @sprite_arm.image = @game.animations.get("arm")
      @claw_attached = false
      @space.remove(@claw.body, @claw, @claw_joint)
      @claw = null
      @unattachClaw()
      @playSfx("retract")

    unattachClaw: ->
      if @claw_pins?
        #@claw.body.reset_forces()
        @want_to_remove_claw_pin = true

    computeAtomPointedAt: ->
      if @equipped_gun is Control.SwitchToGrapple
        @closest_atom = null
      else
        # iterate over each atom. check if intersects with line.
        @closest_atom = null
        closest_dist = null
        for atom in @atoms
          if atom.marked_for_deletion
            continue
          # http://stackoverflow.com/questions/1073336/circle-line-collision-detection
          f = atom.shape.body.position - @point_start
          if sign(f.x) isnt sign(@point_vector.x) or sign(f.y) isnt sign(@point_vector.y)
            continue
          a = @point_vector.dot(@point_vector)
          b = 2 * f.dot(@point_vector)
          c = f.dot(f) - atom_radius*atom_radius
          discriminant = b*b - 4*a*c
          if discriminant < 0
            continue

          dist = atom.shape.body.position.get_dist_sqrd(@point_start)
          if @closest_atom is null or dist < closest_dist
            @closest_atom = atom
            closest_dist = dist

      if @closest_atom?
        # intersection
        # use the coords of the closest atom
        @point_end = @closest_atom.shape.body.position
      else
        # no intersection
        # find the coords at the wall
        slope = @point_vector.y / (@point_vector.x+0.00000001)
        y_intercept = @point_start.y - slope * @point_start.x
        @point_end = @point_start + @size.get_length() * @point_vector
        if @point_end.x > @size.x
          @point_end.x = @size.x
          @point_end.y = slope * @point_end.x + y_intercept
        if @point_end.x < 0
          @point_end.x = 0
          @point_end.y = slope * @point_end.x + y_intercept
        if @point_end.y > @ceiling.body.position.y - @size.y / 2
          @point_end.y = @ceiling.body.position.y - @size.y / 2
          @point_end.x = (@point_end.y - y_intercept) / slope
        if @point_end.y < 0
          @point_end.y = 0
          @point_end.x = (@point_end.y - y_intercept) / slope

    respond_to_asplosion: (asplosion) ->
      [flavor, quantity] = asplosion

      power = quantity - @min_power
      if power <= 0
        return

      if flavor <= 3
        # bombs
        for i in range(power)
          @drop_bomb()
      else
        # rocks
        for i in range(power)
          @drop_rock()


    restore_state: (data) ->
      if @game_over
        return
      # destroy everything
      # man
      @space.remove(@man, @man.body)
      # atoms
      for atom in @atoms
        atom.cleanUp()
      @atoms = set()
      # bombs
      for bomb in @bombs
        bomb.cleanUp()
      @bombs = set()
      # rocks
      for rock in @rocks
        rock.cleanUp()
      @rocks = set()
      # claw gun
      if @sprite_claw.visible
        @space.remove(@claw.body, @claw, @claw_joint)
      if @claw_pins?
        @space.remove(@claw_pins)

      @claw_pins_to_add = null
      @want_to_remove_claw_pin = false
      @want_to_retract_claw = false

      # re-create everything
      # man
      body = data['man']['shape']['body']
      @initMan(pos=new Vec2d(body['position']), vel=new Vec2d(body['velocity']))

      @mouse_pos = new Vec2d(data['mouse_pos'])
      atoms_by_id = {}
      for obj in data['objects']
        if not obj?
          continue
        # atoms
        if obj['type'] is 'Atom'
          body = obj['shape']['body']
          pos = new Vec2d(body['position'])
          vel = new Vec2d(body['velocity'])
          flavor = obj['flavor']
          atom = new Atom(pos, flavor, pyglet.sprite.Sprite(@game.atom_imgs[flavor], batch=@game.batch, group=@game.group_main), @space)
          atom.shape.body.position = pos
          atom.shape.body.velocity = vel
          atom.shape.body.angle = body['angle']
          atom.shape.body.torque = body['torque']
          if obj['rogue']
            atom.rogue = true
            @space.remove(atom.shape.body)
            @ray_atom = atom
          atom.in_id = obj['id']
          atom.in_bonds = obj['bonds']
          atoms_by_id[atom.in_id] = atom
          @atoms.add(atom)
        else if obj['type'] is 'Bomb'
          body = obj['shape']['body']
          pos = new Vec2d(body['position'])
          vel = new Vec2d(body['velocity'])
          sprite = pyglet.sprite.Sprite(@game.animations.get("bomb"), batch=@game.batch, group=@game.group_main)
          bomb = new Bomb(pos, sprite, @space, 99)
          bomb.shape.body.position = pos
          bomb.shape.body.velocity = vel
          bomb.shape.body.angle = body['angle']
          bomb.shape.body.torque = body['torque']
          @bombs.add(bomb)
        else if obj['type'] is 'Rock'
          body = obj['shape']['body']
          pos = new Vec2d(body['position'])
          vel = new Vec2d(body['velocity'])
          sprite = pyglet.sprite.Sprite(@game.animations.get("rock"), batch=@game.batch, group=@game.group_main)
          rock = new Rock(pos, sprite, @space)
          rock.shape.body.position = pos
          rock.shape.body.velocity = vel
          rock.shape.body.angle = body['angle']
          rock.shape.body.torque = body['torque']
          @rocks.add(rock)

      for atom in @atoms
        for bond_id in atom.in_bonds
          atom.bondTo(atoms_by_id[bond_id])

      # state vars
      @points = data['points']

      winner = data['winner']
      if not @winner? and winner?
        if winner
          @lose()
        else
          @win()

      @equipped_gun = data['equipped_gun']

      # claw
      @claw_in_motion = data['claw_in_motion']
      @sprite_claw.visible = data['claw_visible']
      in_claw_pins = data['claw_pins']
      @claw_attached = data['claw_attached']
      if @claw_in_motion
        in_body = data['claw']['body']
        # create claw
        body = pymunk.Body(mass=5, moment=1000000)
        body.position = new Vec2d(in_body['position'])
        body.angle = in_body['angle']
        body.velocity = new Vec2d(in_body['velocity'])
        @claw = pymunk.Circle(body, @claw_radius)
        @claw.friction = 1
        @claw.elasticity = 0
        @claw.collision_type = Collision.Claw
        @claw_joint = pymunk.SlideJoint(@claw.body, @man.body, new Vec2d(0, 0), new Vec2d(0, 0), 0, data['claw_joint']['max'])
        @claw_joint.max_bias = max_bias
        @space.add(body, @claw, @claw_joint)
      if not in_claw_pins?
        @claw_pins = null
      else
        @claw_pins = []
        for in_joint in in_claw_pins
          joint = pymunk.PinJoint(@claw.body, @ceiling.body, new Vec2d(0, 0), new Vec2d(0, 0))
          joint.max_bias = max_bias
          @claw_pins.append(joint)
          @space.add(joint)

      # weapon drops
      for asplosion in data['queued_asplosions']
        @other_tank.respond_to_asplosion(asplosion)


    on_key_press: (symbol, modifiers) ->
      control = @controls[symbol]
      if control?
        @control_state[control] = true

    on_key_release: (symbol, modifiers) ->
      control = @controls[symbol]
      if control?
        @control_state[control] = false

    moveMouse: (x, y) ->
      @mouse_pos = new Vec2d(x, y) - @pos

      use_crosshair = @mouse_pos.x >= 0 and \
              @mouse_pos.y >= 0 and \
              @mouse_pos.x <= @size.x and \
              @mouse_pos.y <= @size.y
      cursor = if use_crosshair then @game.crosshair else @game.default_cursor
      @game.window.set_mouse_cursor(cursor)

    on_mouse_motion: (x, y, dx, dy) ->
      @moveMouse(x, y)

    on_mouse_drag: (x, y, dx, dy, buttons, modifiers) ->
      @moveMouse(x, y)

    on_mouse_press: (x, y, button, modifiers) ->
      control = @controls[Control.MOUSE_OFFSET+button]
      if control?
        @control_state[control] = true

    on_mouse_release: (x, y, button, modifiers) ->
      control = @controls[Control.MOUSE_OFFSET+button]
      if control?
        @control_state[control] = false

    moveSprites: ->
      # drawable things
      for drawable in itertools.chain(@atoms, @bombs, @rocks)
        drawable.sprite.setPosition(drawable.shape.body.position.plus(@pos))
        drawable.sprite.rotation = -drawable.shape.body.rotation_vector.get_angle_degrees()

      @sprite_man.setPosition(@man.body.position.plus(@pos))
      @sprite_man.rotation = -@man.body.rotation_vector.get_angle_degrees()

      @sprite_arm.setPosition(@arm_pos.plus(@pos))
      @sprite_arm.rotation = -(@mouse_pos - @man.body.position).get_angle_degrees()
      if @mouse_pos.x < @man.body.position.x
        @sprite_arm.rotation += 180

      @sprite_tank.setPosition(@pos.plus(@ceiling.body.position))

      if @sprite_claw.visible
        @sprite_claw.setPosition(@claw.body.position.plus(@pos))
        @sprite_claw.rotation = -@claw.body.rotation_vector.get_angle_degrees()

    drawPrimitives: ->
      # draw a line from gun hand to @point_end
      if not @game_over
        @drawLine(@point_start + @pos, @point_end + @pos, [0, 0, 0, 0.23])

        # draw a line from gun to claw if it's out
        if @sprite_claw.visible
          @drawLine(@point_start + @pos, @sprite_claw.position, [1, 1, 0, 1])

        # draw lines for bonded atoms
        for atom in @atoms
          if atom.marked_for_deletion
            continue
          for other, joint of atom.bonds
            @drawLine(@pos + atom.shape.body.position, @pos + other.shape.body.position, [0, 0, 1, 1])

        if @game.debug
          if @claw_pins
            for claw_pin in @claw_pins
              @drawLine(@pos + claw_pin.a.position + claw_pin.anchr1, @pos + claw_pin.b.position + claw_pin.anchr2, [1, 0, 1, 1])

        # lazer
        if @lazer_line?
          [start, end] = @lazer_line
          @drawLine(start + @pos, end + @pos, [1, 0, 0, 1])

    drawLine: (p1, p2, color) ->
      pyglet.gl.glColor4f(color[0], color[1], color[2], color[3])
      pyglet.graphics.draw(2, pyglet.gl.GL_LINES, ['v2f', [p1[0], p1[1], p2[0], p2[1]]])

  class Game
    constructor: (@gw, @window, @server) ->
      @debug = params.debug?

      @animations = new Animations()
      @animations.load()

      @batch = pyglet.graphics.Batch()
      @group_bg = pyglet.graphics.OrderedGroup(0)
      @group_main = pyglet.graphics.OrderedGroup(1)
      @group_fg = pyglet.graphics.OrderedGroup(2)

      img_bg = pyglet.resource.image("data/bg.png")
      img_bg_top = pyglet.resource.image("data/bg-top.png")
      @sprite_bg = pyglet.sprite.Sprite(img_bg, batch=@batch, group=@group_bg)
      @sprite_bg_top = pyglet.sprite.Sprite(img_bg_top, batch=@batch, group=@group_fg, y=img_bg.height-img_bg_top.height)

      @atom_imgs = [@animations.get("atom%i" % i) for i in range(Atom.flavor_count)]


      unless params.nofx?
        @sfx = {
          'jump': pyglet.resource.media('data/sfx/jump__dave-des__fast-simple-chop-5.ogg', streaming=false),
          'atom_hit_atom': pyglet.resource.media('data/sfx/atomscolide__batchku__colide-18-005.ogg', streaming=false),
          'ray': pyglet.resource.media('data/sfx/raygun__owyheesound__decelerate-discharge.ogg', streaming=false),
          'lazer': pyglet.resource.media('data/sfx/lazer__supraliminal__laser-short.ogg', streaming=false),
          'merge': pyglet.resource.media('data/sfx/atomsmerge__tigersound__disappear.ogg', streaming=false),
          'bond': pyglet.resource.media('data/sfx/bond.ogg', streaming=false),
          'victory': pyglet.resource.media('data/sfx/victory__iut-paris8__labbefabrice-2011-01.ogg', streaming=false),
          'defeat': pyglet.resource.media('data/sfx/defeat__freqman__lostspace.ogg', streaming=false),
          'switch_weapon': pyglet.resource.media('data/sfx/switchweapons__erdie__metallic-weapon-low.ogg', streaming=false),
          'explode': pyglet.resource.media('data/sfx/atomsexplode3-1.ogg', streaming=false),
          'claw_hit': pyglet.resource.media('data/sfx/shootingtheclaw__smcameron__rocks2.ogg', streaming=false),
          'shoot_claw': pyglet.resource.media('data/sfx/landonsurface__juskiddink__thud-dry.ogg', streaming=false),
          'retract': pyglet.resource.media('data/sfx/clawcomesback__simon-rue__studs-moln-v4.ogg', streaming=false),
        }
      else
        @sfx = null

      pyglet.clock.schedule_interval(@update, 1/game_fps)
      if params.fps?
        @fps_display = pyglet.clock.ClockDisplay()
      else
        @fps_display = null

      @crosshair = @window.get_system_mouse_cursor(@window.CURSOR_CROSSHAIR)
      @default_cursor = @window.get_system_mouse_cursor(@window.CURSOR_DEFAULT)

      tank_dims = new Vec2d(12, 16)
      tank_pos = [
        new Vec2d(109, 41),
        new Vec2d(531, 41),
      ]

      if not @server?
        @tanks = [new Tank(tank_pos[0], tank_dims, self)]
        @control_tank = @tanks[0]

        @survival_points = 0
        @survival_point_timeout = params.hard or 10
        @next_survival_point = @survival_point_timeout
        @weapon_drop_interval = params.bomb or 10

        tank_index = int(not @control_tank.tank_index)
        tank_name = "tank%i" % tank_index
        @sprite_other_tank = pyglet.sprite.Sprite(@animations.get(tank_name), batch=@batch, group=@group_main, x=tank_pos[1].x + @control_tank.size.x / 2, y=tank_pos[1].y + @control_tank.size.y / 2)
      else
        @tanks = [new Tank(pos, tank_dims, self, tank_index=i) for pos, i in enumerate(tank_pos)]

        @control_tank = @tanks[0]
        @enemy_tank = @tanks[1]

        @control_tank.other_tank = @enemy_tank
        @enemy_tank.other_tank = @control_tank

        @enemy_tank.atom_drop_enabled = false
        @enemy_tank.enable_point_calculation = false
        @enemy_tank.sfx_enabled = false



      @window.set_handler('on_draw', @on_draw)
      @window.set_handler('on_mouse_motion', @control_tank.on_mouse_motion)
      @window.set_handler('on_mouse_drag', @control_tank.on_mouse_drag)
      @window.set_handler('on_mouse_press', @control_tank.on_mouse_press)
      @window.set_handler('on_mouse_release', @control_tank.on_mouse_release)
      @window.set_handler('on_key_press', @control_tank.on_key_press)
      @window.set_handler('on_key_release', @control_tank.on_key_release)


      pyglet.gl.glEnable(pyglet.gl.GL_BLEND)
      pyglet.gl.glBlendFunc(pyglet.gl.GL_SRC_ALPHA, pyglet.gl.GL_ONE_MINUS_SRC_ALPHA)


      @state_render_timeout = 0.3
      @next_state_render = @state_render_timeout



    update: (dt) ->
      for tank in @tanks
        tank.update(dt)

      if not @server?
        # give enemy points
        @next_survival_point -= dt
        if @next_survival_point <= 0
          @next_survival_point += @survival_point_timeout
          old_number = Math.floor(@survival_points / @weapon_drop_interval)
          @survival_points += randInt(3, 6)
          new_number = Math.floor(@survival_points / @weapon_drop_interval)

          if new_number > old_number
            n = randInt(1, 2)
            if n is 1
              @control_tank.drop_bomb()
            else
              @control_tank.drop_rock()

      # send state to network
      if @server?
        @next_state_render -= dt
        if @next_state_render <= 0
          @next_state_render = @state_render_timeout

          @server.send_msg("StateUpdate", @control_tank.serialize_state())

          # get all server messages
          for [msg_name, data] in @server.get_messages()
            if msg_name is 'StateUpdate'
              @enemy_tank.restore_state(data)
            else if msg_name is 'YourOpponentLeftSorryBro'
              print("you win - your opponent disconnected.")
              @control_tank.win()


    on_draw: ->
      @window.clear()

      for tank in @tanks
        tank.moveSprites()

      @batch.draw()

      for tank in @tanks
        tank.drawPrimitives()
      

      if @fps_display?
        @fps_display.draw()

  class GameWindow
    constructor: (@window, @server) ->
      @current = null

    endCurrent: ->
      if @current?
        @current.end()
      @current = null

    title: ->
      @endCurrent()
      @current = new Title(@window, @server)

    play: (server_on=true) ->
      server = if server_on then @server else null
      @endCurrent()
      @current = new Game(@window, server)

    credits: ->
      @endCurrent()
      @current = new Credits(@window)

    controls: ->
      @endCurrent()
      @current = new ControlsScene(@window)

  class ControlsScene
    constructor: (@gw, @window) ->
      @img = pyglet.resource.image("data/howtoplay.png")
      @window.set_handler('on_draw', @on_draw)
      @window.set_handler('on_mouse_press', @on_mouse_press)
      pyglet.clock.schedule_interval(@update, 1/game_fps)

    update: (dt) ->

    on_draw: ->
      @window.clear()
      @img.blit(0, 0)

    end: ->
      @window.remove_handler('on_draw', @on_draw)
      @window.remove_handler('on_mouse_press', @on_mouse_press)
      pyglet.clock.unschedule(@update)

    on_mouse_press: (x, y, button, modifiers) ->
      @gw.title()


  class Credits
    constructor: (@gw, @window) ->
      @img = pyglet.resource.image("data/credits.png")
      @window.set_handler('on_draw', @on_draw)
      @window.set_handler('on_mouse_press', @on_mouse_press)
      pyglet.clock.schedule_interval(@update, 1/game_fps)

    update: (dt) ->

    on_draw: ->
      @window.clear()
      @img.blit(0, 0)

    end: ->
      @window.remove_handler('on_draw', @on_draw)
      @window.remove_handler('on_mouse_press', @on_mouse_press)
      pyglet.clock.unschedule(@update)

    on_mouse_press: (x, y, button, modifiers) ->
      @gw.title()


  class Title
    constructor: (@gw, @window, @server) ->
      @window.set_handler('on_mouse_press', @on_mouse_press)
      @window.set_handler('on_draw', @on_draw)
      pyglet.clock.schedule_interval(@update, 1/game_fps)

      @img = pyglet.resource.image("data/title.png")

      @start_pos = new Vec2d(409, 305)
      @credits_pos = new Vec2d(360, 229)
      @controls_pos = new Vec2d(525, 242)
      @click_radius = 50

      @lobby_pos = new Vec2d(746, 203)
      @lobby_size = new Vec2d(993.0 - @lobby_pos.x, 522.0 - @lobby_pos.y)

      if @server?
        @labels = []
        @users = []

        @nick_label = {}
        @nick_user = {}

        # guess a good nick
        @nick = "Guest %i" % randInt(1, 99999)
        @server.send_msg("UpdateNick", @nick)
        @my_nick_label = pyglet.text.Label(@nick, font_size=16, x=748, y=137)

        @challenged = {}

    create_labels: ->
      @labels = []
      @nick_label = {}
      @nick_user = {}
      h = 18
      next_pos = @lobby_pos + new Vec2d(0, @lobby_size.y - h)
      for user in @users
        nick = user['nick']
        if nick is @nick
          continue
        text = nick
        if user['playing']?
          text += " (playing vs %s)" % user['playing']
        else if @nick in user['want_to_play']
          text += " (click to accept challenge)"
        else if nick in @challenged
          text += " (challenge sent)"
        else
          text += " (click to challenge)"
        label = pyglet.text.Label(text, font_size=13, x=next_pos.x, y=next_pos.y)
        @nick_label[nick] = label
        @nick_user[nick] = user
        next_pos.y -= h
        @labels.append(label)

    update: (dt) ->
      if @server?
        for [name, payload] in server.get_messages()
          if name is 'LobbyList'
            @users = payload
            @create_labels()
          else if name is 'StartGame'
            @gw.play()
            return

    on_draw: ->
      @window.clear()
      @img.blit(0, 0)
      if @server?
        for label in @labels
          label.draw()
        @my_nick_label.draw()

    end: ->
      @window.remove_handler('on_draw', @on_draw)
      @window.remove_handler('on_mouse_press', @on_mouse_press)
      pyglet.clock.unschedule(@update)

    on_mouse_press: (x, y, button, modifiers) ->
      click_pos = new Vec2d(x, y)
      if click_pos.get_distance(@start_pos) < @click_radius
        @gw.play(server_on=false)
        return
      else if click_pos.get_distance(@credits_pos) < @click_radius
        @gw.credits()
        return
      else if click_pos.get_distance(@controls_pos) < @click_radius
        @gw.controls()
        return

      if @server?
        for nick, label of @nick_label
          label_pos = new Vec2d(label.x, label.y)
          label_size = new Vec2d(200, 18)
          if click_pos.x > label_pos.x and click_pos.y > label_pos.y and click_pos.x < label_pos.x + label_size.x and click_pos.y < label_pos.y + label_size.y
            user = @nick_user[nick]
            if not user?
              print("warn missing nick" + nick)
              return

            if not user['playing']
              if @nick in user['want_to_play']
                @server.send_msg("AcceptPlayRequest", nick)
              else
                @server.send_msg("PlayRequest", nick)
                @challenged[nick] = true
                @create_labels()
            return

  params = do ->
    obj = {}
    obj[key] = val for [key, val] in location.search.substring(1).split("&")
    obj

  canvas = document.getElementById("game")
  engine = new Engine(canvas)
  engine.on 'update', (dt, dx) ->
  engine.on 'draw', (context) ->
    context.clearRect 0, 0, engine.size.x, engine.size.y
    context.fillText "#{engine.fps} fps", 0, engine.size.y
  engine.on 'mousedown', (pos) -> console.log pos.x, pos.y
  engine.start()