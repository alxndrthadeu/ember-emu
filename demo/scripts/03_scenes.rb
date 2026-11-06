# encoding: utf-8
#
# Scenes: the title, the camp map (walk, talk, a menu).

class DemoScene
  def main
    start
    Graphics.transition(24)
    loop do
      Graphics.update
      Input.update
      update
      break if $scene != self
    end
    Graphics.freeze
    terminate
  end

  def start; end
  def update; end
  def terminate; end

  def cream; Pix.c(0xF4E9D8); end
  def amber; Pix.c(0xF7B538); end
  def ink; Pix.c(0x2B211C); end
end

# MARK: - Title

class TitleScene < DemoScene
  def start
    w, h = Graphics.width, Graphics.height
    @sky = Sprite.new
    @sky.bitmap = Bitmap.new(w, h)
    @sky.bitmap.gradient_fill_rect(0, 0, w, h, Pix.c(0x141A33), Pix.c(0x3A2A40), true)
    # Stars.
    60.times do |i|
      n = Art.noise(i, i * 3, 7)
      x = (n * 37 + i * 89) % w
      y = (n * 13 + i * 41) % (h - 140)
      s = i % 7 == 0 ? 4 : 2
      @sky.bitmap.fill_rect(x, y, s, s, Pix.c(0xF4E9D8, 120 + (n % 120)))
    end
    # Hills.
    hill = Pix.c(0x1C1726)
    w.times do |x|
      top = h - 96 + (Math.sin(x / 70.0) * 18).round + (Math.sin(x / 23.0) * 5).round
      @sky.bitmap.fill_rect(x - x % 4, top - top % 4, 4, h - top + 4, hill)
    end

    @fire = Sprite.new
    @fire.bitmap = Art.frames(Art::FIRE, Art::FIRE_PALETTE, 6)
    @fire.src_rect.set(0, 0, 96, 96)
    @fire.x, @fire.y = (w - 96) / 2, h - 142

    @glow = Sprite.new
    @glow.bitmap = MapScene.glow_bitmap(220)
    @glow.blend_type = 1
    @glow.x, @glow.y = w / 2 - 110, h - 202

    @text = Sprite.new
    @text.bitmap = Bitmap.new(w, h)
    @text.z = 10
    @saved = Demo.saved_game
    @index = 0
    @frame = 0
    draw_text
  end

  def items
    [Demo.t(:new_game), Demo.t(:continue), Demo.t(:quit)]
  end

  def draw_text
    b = @text.bitmap
    b.clear
    b.font.size = 44
    b.font.bold = true
    b.font.color = cream
    b.draw_text(0, 44, b.width, 56, Demo.t(:title), 1)
    b.font.size = 18
    b.font.bold = false
    b.font.color = Pix.c(0xB9A794)
    b.draw_text(0, 98, b.width, 24, Demo.t(:subtitle), 1)
    b.font.size = 22
    items.each_with_index do |label, i|
      y = 150 + i * 34
      enabled = i != 1 || @saved
      selected = i == @index
      if selected
        Pix.round_rect(b, b.width / 2 - 90, y - 2, 180, 32, Pix.c(0xF7B538, 230), 8)
      end
      b.font.color = selected ? ink : (enabled ? cream : Pix.c(0xF4E9D8, 90))
      b.draw_text(0, y, b.width, 28, label, 1)
    end
  end

  def update
    @frame += 1
    @fire.src_rect.x = ((@frame / 6) % 3) * 96
    @glow.opacity = 150 + (Math.sin(@frame / 5.0) * 30).round
    if Input.repeat?(Input::DOWN) || Input.repeat?(Input::UP)
      step = Input.repeat?(Input::DOWN) ? 1 : -1
      @index = (@index + step) % 3
      @index = (@index + step) % 3 if @index == 1 && !@saved
      draw_text
    end
    if Input.trigger?(Input::C)
      case @index
      when 0 then $scene = MapScene.new
      when 1 then $scene = MapScene.new(@saved)
      when 2 then $scene = nil
      end
    end
  end

  def terminate
    [@sky, @fire, @glow, @text].each { |s| s.bitmap.dispose; s.dispose }
  end
end

# MARK: - The camp

class MapScene < DemoScene
  MAP = [
    'TTTTTTTTTTTTTTTTT',
    'T..F......TTT...T',
    'T.HHH.........F.T',
    'T.HHH..WWW......T',
    'T.HDH..WWWW..T..T',
    'T..P...WWW......T',
    'T..PPPPPPPPPP...T',
    'T..F..L.P.......T',
    'T....LCKP...F.T.T',
    'T.T...L.P.......T',
    'T.......PP..S...T',
    'T..F.....P....F.T',
    'TTTTTTTTTPTTTTTTT',
  ]
  WALKABLE = ['.', 'P', 'F']
  DIRS = { 2 => [0, 1, :down], 4 => [-1, 0, :left], 6 => [1, 0, :right], 8 => [0, -1, :up] }
  SHEET_ROW = { :down => 0, :left => 1, :right => 2, :up => 3 }

  # A soft warm light, added on top (blend 1).
  def self.glow_bitmap(size)
    bitmap = Bitmap.new(size, size)
    r = size / 2.0
    step = 4
    (0...size).step(step) do |y|
      (0...size).step(step) do |x|
        d = Math.sqrt((x - r) ** 2 + (y - r) ** 2) / r
        next if d >= 1
        a = ((1 - d) ** 2 * 140).round
        bitmap.fill_rect(x, y, step, step, Color.new(255, 150, 60, a))
      end
    end
    bitmap
  end

  attr_reader :hx, :hy, :facing

  def initialize(saved = nil)
    @saved = saved
  end

  def start
    $demo_map = self
    @ground = Sprite.new
    @ground.bitmap = build_ground

    @fire = Sprite.new
    @fire.bitmap = Art.frames(Art::FIRE, Art::FIRE_PALETTE)
    @fire.src_rect.set(0, 0, 32, 32)
    @fire.x, @fire.y, @fire.z = 6 * 32, 8 * 32, 8 * 32

    @cat = Sprite.new
    @cat.bitmap = Art.frames(Art::CAT, Art::CAT_PALETTE)
    @cat.src_rect.set(0, 0, 32, 32)
    @cat.x, @cat.y, @cat.z = 7 * 32, 8 * 32, 8 * 32

    @hero = Sprite.new
    @hero.bitmap = Art.hero_sheet
    @hx, @hy = 9, 11
    @facing = :up
    if @saved
      @hx, @hy = @saved['x'].to_i, @saved['y'].to_i
      @facing = @saved['facing'].to_sym if SHEET_ROW.key?(@saved['facing'].to_s.to_sym)
    end
    @px, @py = @hx * 32, @hy * 32
    @step = 0
    @moving = 0

    # Dusk: a blue veil, and warm light around the fire and windows.
    @veil = Sprite.new
    @veil.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @veil.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(30, 30, 80, 95))
    @veil.z = 500
    @glow = Sprite.new
    @glow.bitmap = MapScene.glow_bitmap(200)
    @glow.blend_type = 1
    @glow.x, @glow.y, @glow.z = 6 * 32 + 16 - 100, 8 * 32 + 16 - 100, 510
    @windows = [[2 * 32 + 24, 4 * 32 + 2], [2 * 32 + 72, 4 * 32 + 2]].map do |x, y|
      s = Sprite.new
      s.bitmap = MapScene.glow_bitmap(72)
      s.blend_type = 1
      s.x, s.y, s.z = x - 36, y - 36, 510
      s
    end

    @fireflies = (0...7).map do |i|
      s = Sprite.new
      s.bitmap = Bitmap.new(4, 4)
      s.bitmap.fill_rect(0, 0, 4, 4, Pix.c(0xF7E27A))
      s.z = 520
      s.blend_type = 1
      s
    end

    @place = Sprite.new
    @place.bitmap = Bitmap.new(260, 40)
    Pix.panel(@place.bitmap, 0, 0, 260, 40)
    @place.bitmap.font.size = 18
    @place.bitmap.font.color = cream
    @place.bitmap.draw_text(0, 0, 260, 40, Demo.t(:place), 1)
    @place.x, @place.y, @place.z = 16, 16, 900
    @place_timer = 180

    @message = MessageBox.new
    @menu = nil
    @frame = 0
    update_hero_sprite
  end

  def build_ground
    bitmap = Bitmap.new(Graphics.width, Graphics.height)
    MAP.each_with_index do |row, ty|
      row.length.times do |tx|
        case row[tx, 1]
        when 'P' then Art.path(bitmap, tx, ty)
        when 'W' then Art.water(bitmap, tx, ty)
        when 'F' then Art.flowers(bitmap, tx, ty)
        else Art.grass(bitmap, tx, ty)
        end
      end
    end
    MAP.each_with_index do |row, ty|
      row.length.times do |tx|
        case row[tx, 1]
        when 'T' then Pix.paint(bitmap, tx * 32, ty * 32, Art::TREE, Art::TREE_PALETTE)
        when 'L' then Art.log(bitmap, tx, ty)
        when 'S' then Art.sign(bitmap, tx, ty)
        end
      end
    end
    Art.house(bitmap, 2, 2)
    bitmap
  end

  def tile(x, y)
    return 'T' if y < 0 || y >= MAP.size || x < 0 || x >= MAP[0].length
    MAP[y][x, 1]
  end

  def update_scene
    @frame += 1
    @fire.src_rect.x = ((@frame / 6) % 3) * 32
    @cat.src_rect.x = ((@frame / 40) % 2) * 32
    flicker = (Math.sin(@frame / 5.0) * 25).round + (Math.sin(@frame / 2.3) * 8).round
    @glow.opacity = 210 + flicker
    @fireflies.each_with_index do |f, i|
      t = @frame / 60.0 + i * 1.7
      f.x = (60 + i * 70 + Math.sin(t * 0.9 + i) * 30).round
      f.y = (70 + (i * 53) % 260 + Math.cos(t * 0.7 + i * 2) * 20).round
      f.opacity = (128 + Math.sin(t * 3 + i) * 127).round
    end
    if @place_timer > 0
      @place_timer -= 1
      @place.opacity = [@place_timer * 6, 255].min
    end

    if @menu
      @menu.update
      if @menu.closed?
        @menu.dispose
        @menu = nil
      end
      return
    end
    if @message.active?
      @message.update
      return
    end
    update_walk
    return if @moving > 0
    if Input.trigger?(Input::C)
      interact
    elsif Input.trigger?(Input::B)
      @menu = GameMenu.new
    end
  end

  def update
    update_scene
    # Tells Ember when the map is free of menus and messages: pictures
    # for save thumbnails come from these moments.
    $ember_quiet_map = @menu.nil? && !@message.active?
  end

  def update_walk
    if @moving > 0
      dx, dy = DIRS.values.find { |v| v[2] == @facing }
      @px += dx * 4
      @py += dy * 4
      @moving -= 4
      @step = 1 - @step if @moving == 16
      update_hero_sprite
      return
    end
    dir = Input.dir4
    return if dir == 0
    dx, dy, facing = DIRS[dir]
    @facing = facing
    nx, ny = @hx + dx, @hy + dy
    if WALKABLE.include?(tile(nx, ny))
      @hx, @hy = nx, ny
      @moving = 32
    end
    update_hero_sprite
  end

  def update_hero_sprite
    @hero.src_rect.set(@step * 32, SHEET_ROW[@facing] * 32, 32, 32)
    @hero.x, @hero.y = @px, @py - 4
    @hero.z = @py + 16
  end

  def interact
    dx, dy = DIRS.values.find { |v| v[2] == @facing }
    key = case tile(@hx + dx, @hy + dy)
          when 'K' then :cat
          when 'C' then :fire
          when 'S' then :sign
          when 'D' then :door
          when 'W' then :water
          end
    @message.open(Demo.talk(key)) if key
  end

  def terminate
    sprites = [@ground, @fire, @cat, @hero, @veil, @glow, @place] + @windows + @fireflies
    sprites.each { |s| s.bitmap.dispose; s.dispose }
    @message.dispose
    @menu.dispose if @menu
  end
end

# MARK: - Message box

class MessageBox
  W, H = 512, 112

  def initialize
    @sprite = Sprite.new
    @sprite.bitmap = Bitmap.new(W, H + 30)
    @sprite.x, @sprite.y, @sprite.z = 16, Graphics.height - H - 30 - 12, 1000
    @sprite.visible = false
    @lines = []
  end

  def active?
    @sprite.visible
  end

  def open(pages)
    @pages = pages
    @page = 0
    @sprite.visible = true
    show_page
  end

  def show_page
    speaker, text = @pages[@page]
    @speaker = speaker ? Demo.t(speaker) : nil
    @sprite.bitmap.font.size = 21
    @lines = Pix.wrap(@sprite.bitmap, text, W - 48)
    @shown = 0
    @total = @lines.join.length
    @blink = 0
    redraw
  end

  def redraw
    b = @sprite.bitmap
    b.clear
    Pix.panel(b, 0, 30, W, H)
    if @speaker
      b.font.size = 17
      b.font.bold = true
      width = b.text_size(@speaker).width + 28
      Pix.round_rect(b, 16, 14, width, 30, Pix.c(0xF7B538), 8)
      b.font.color = Pix.c(0x2B211C)
      b.draw_text(16, 14, width, 30, @speaker, 1)
    end
    b.font.size = 21
    b.font.bold = false
    b.font.color = Pix.c(0xF4E9D8)
    left = @shown
    @lines.each_with_index do |line, i|
      break if left <= 0
      part = line[0, left]
      left -= line.length
      b.draw_text(24, 30 + 20 + i * 28, W - 48, 28, part)
    end
    if @shown >= @total && (@blink / 20) % 2 == 0
      Pix.triangle(b, W - 34, 30 + H - 22, Pix.c(0xF7B538))
    end
  end

  def update
    if @shown < @total
      @shown += 2
      @shown = @total if Input.trigger?(Input::C)
      redraw
      return
    end
    @blink += 1
    redraw if @blink % 20 == 0
    if Input.trigger?(Input::C) || Input.trigger?(Input::B)
      @page += 1
      if @page >= @pages.size
        @sprite.visible = false
      else
        show_page
      end
    end
  end

  def dispose
    @sprite.bitmap.dispose
    @sprite.dispose
  end
end

# MARK: - Menu

class GameMenu
  def initialize
    @commands = [:items, :status, :save, :close]
    @index = 0
    @toast = 0
    @dim = Sprite.new
    @dim.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @dim.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(10, 8, 6, 120))
    @dim.z = 1500
    @sprite = Sprite.new
    @sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprite.z = 1600
    @portrait = Art.hero_sheet
    redraw
  end

  def closed?
    @closed
  end

  def redraw
    b = @sprite.bitmap
    b.clear
    cream, amber, ink, muted = Pix.c(0xF4E9D8), Pix.c(0xF7B538), Pix.c(0x2B211C), Pix.c(0xB9A794)

    # Commands, on the right.
    Pix.panel(b, 372, 16, 156, 16 + @commands.size * 40)
    b.font.size = 21
    @commands.each_with_index do |cmd, i|
      y = 24 + i * 40
      if i == @index
        Pix.round_rect(b, 380, y, 140, 36, amber, 8)
        b.font.color = ink
      else
        b.font.color = cream
      end
      b.draw_text(396, y, 120, 36, Demo.t(cmd))
    end

    # Lia's card.
    Pix.panel(b, 16, 16, 340, 150)
    b.stretch_blt(Rect.new(28, 30, 96, 96), @portrait, Rect.new(0, 0, 32, 32))
    b.font.size = 24
    b.font.bold = true
    b.font.color = cream
    b.draw_text(138, 28, 200, 30, Demo.t(:hero))
    b.font.bold = false
    b.font.size = 16
    b.font.color = muted
    b.draw_text(138, 56, 200, 22, Demo.t(:hero_role))
    b.font.color = amber
    b.draw_text(290, 30, 56, 26, "#{Demo.t(:level)} 7", 2)
    bar(b, 138, 88, 'HP', 86, 120, Pix.c(0xEE6A2A))
    bar(b, 138, 116, 'MP', 24, 40, Pix.c(0x4DB3A8))

    # Items.
    Pix.panel(b, 16, 178, 340, 150)
    b.font.size = 18
    items = [[:potion, 3], [:bread, 2], [:lantern, 1], [:map_item, 1]]
    items.each_with_index do |(key, count), i|
      y = 192 + i * 32
      b.fill_rect(32, y + 8, 12, 12, [amber, Pix.c(0xE8C27A), Pix.c(0xEE6A2A), Pix.c(0xC9A46A)][i])
      b.font.color = cream
      b.draw_text(56, y, 220, 28, Demo.t(key))
      b.font.color = muted
      b.draw_text(260, y, 80, 28, "×#{count}", 2)
    end

    # Coins.
    Pix.panel(b, 16, 340, 340, 44)
    b.font.size = 18
    b.font.color = muted
    b.draw_text(32, 348, 160, 28, Demo.t(:gold))
    b.font.color = amber
    b.draw_text(180, 348, 160, 28, '350', 2)

    if @toast > 0
      Pix.round_rect(b, 372, 200, 156, 40, Pix.c(0x2E8C83), 8)
      b.font.size = 17
      b.font.color = cream
      b.draw_text(372, 200, 156, 40, Demo.t(:saved), 1)
    end
  end

  def bar(b, x, y, label, value, max, color)
    b.font.size = 15
    b.font.color = Pix.c(0xB9A794)
    b.draw_text(x, y - 4, 36, 22, label)
    Pix.round_rect(b, x + 36, y + 4, 150, 10, Pix.c(0x4A3D35), 4)
    Pix.round_rect(b, x + 36, y + 4, (150 * value / max), 10, color, 4)
    b.font.color = Pix.c(0xF4E9D8)
    b.draw_text(x + 36, y - 4, 166, 22, "#{value}/#{max}", 2)
  end

  def update
    if @toast > 0
      @toast -= 1
      redraw if @toast == 0
    end
    if Input.repeat?(Input::DOWN)
      @index = (@index + 1) % @commands.size
      redraw
    elsif Input.repeat?(Input::UP)
      @index = (@index - 1) % @commands.size
      redraw
    elsif Input.trigger?(Input::B)
      @closed = true
    elsif Input.trigger?(Input::C)
      case @commands[@index]
      when :save
        Demo.save_game($demo_map) if $demo_map
        @toast = 90
        redraw
      when :close
        @closed = true
      end
    end
  end

  def dispose
    [@dim, @sprite].each { |s| s.bitmap.dispose; s.dispose }
    @portrait.dispose
  end
end
