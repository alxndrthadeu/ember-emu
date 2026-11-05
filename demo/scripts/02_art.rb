# encoding: utf-8
#
# The art, drawn in code. Sprites are 16×16 pixel maps painted at 2×
# (32-pixel tiles, the RGSS3 grid on a 544×416 screen).

module Art
  TILE = 32

  # Lia, the traveler. h hair, s skin, K eyes, r cheeks, S scarf,
  # b tunic, p trousers, k boots.
  HERO_PALETTE = {
    'h' => Pix.c(0x5A3A28), 's' => Pix.c(0xF0C8A0), 'K' => Pix.c(0x2B211C),
    'r' => Pix.c(0xE0907A), 'S' => Pix.c(0xEE6A2A), 'b' => Pix.c(0x3A5F8F),
    'p' => Pix.c(0x3B3440), 'k' => Pix.c(0x2B211C),
  }

  HERO_TOP = {
    :down => [
      '................',
      '.....hhhhhh.....',
      '....hhhhhhhh....',
      '....hssssssh....',
      '....sKssssKs....',
      '....ssssssss....',
      '.....ssrrss.....',
      '....SSSSSSSS....',
      '...bSSbbbbSSb...',
      '...bbbbbbbbbb...',
      '...sbbbbbbbbs...',
      '....bbbbbbbb....',
    ],
    :up => [
      '................',
      '.....hhhhhh.....',
      '....hhhhhhhh....',
      '....hhhhhhhh....',
      '....hhhhhhhh....',
      '....shhhhhhs....',
      '.....ssssss.....',
      '....SSSSSSSS....',
      '...bSSSSSSSSb...',
      '...bbbbbbbbbb...',
      '...sbbbbbbbbs...',
      '....bbbbbbbb....',
    ],
    :left => [
      '................',
      '.....hhhhhh.....',
      '....hhhhhhhh....',
      '....ssshhhhh....',
      '....sKsshhhh....',
      '....ssssshhh....',
      '.....rsssss.....',
      '....SSSSSSSS....',
      '...bSSbbbbbbb...',
      '...bbbbbbbbbb...',
      '....sbbbbbbb....',
      '....bbbbbbbb....',
    ],
  }

  HERO_LEGS = [
    ['....pppppppp....',
     '....pp....pp....',
     '....kk....kk....',
     '................'],
    ['....pppppppp....',
     '.....pp..pp.....',
     '.....kk..kk.....',
     '................'],
  ]

  # Faísca, the cat. o fur, d darker fur, K eyes, n nose, w chest.
  CAT_PALETTE = {
    'o' => Pix.c(0xE08A3A), 'd' => Pix.c(0xB8642A), 'K' => Pix.c(0x2B211C),
    'n' => Pix.c(0xE89AA0), 'w' => Pix.c(0xF4E9D8),
  }

  CAT = [
    [
      '................',
      '................',
      '....o.....o.....',
      '....oo...oo.....',
      '....ooooooo.....',
      '....oKoooKo.....',
      '....ooondoo.....',
      '.....ooooo......',
      '....ooooooo.....',
      '...ooowwwooo....',
      '...oowwwwwoo..o.',
      '...oowwwwwoo.oo.',
      '...ooowwwooo.o..',
      '....ooooooooo...',
      '....dd...dd.....',
      '................',
    ],
    [
      '................',
      '................',
      '....o.....o.....',
      '....oo...oo.....',
      '....ooooooo.....',
      '....oKoooKo.....',
      '....ooondoo.....',
      '.....ooooo......',
      '....ooooooo.....',
      '...ooowwwooo....',
      '...oowwwwwoo....',
      '...oowwwwwoo...o',
      '...ooowwwooo..oo',
      '....ooooooooooo.',
      '....dd...dd.....',
      '................',
    ],
  ]

  # The campfire. 1 deep red, 2 orange, 3 amber (the Ember flame
  # colors), L logs, O stones.
  FIRE_PALETTE = {
    '1' => Pix.c(0xC83A1E), '2' => Pix.c(0xEE6A2A), '3' => Pix.c(0xF7B538),
    'L' => Pix.c(0x6B4A2E), 'l' => Pix.c(0x4E3420), 'O' => Pix.c(0x8C8580), 'o' => Pix.c(0x6E6862),
  }

  FIRE = [
    [
      '................',
      '.......1........',
      '.......11.......',
      '......121.......',
      '.....1221...1...',
      '.....12321..1...',
      '....1233221.....',
      '....12333321....',
      '....12333321....',
      '.....123321.....',
      '...LLl1331lLL...',
      '..LLLLLllLLLLL..',
      '...lLL....LLl...',
      '..OoO.OooO.OoO..',
      '.OOOOOOOOOOOOOO.',
      '................',
    ],
    [
      '................',
      '........1.......',
      '.......11.......',
      '.......121......',
      '...1..1221......',
      '...1.12321......',
      '.....1223321....',
      '....12333321....',
      '....12333321....',
      '.....123321.....',
      '...LLl1331lLL...',
      '..LLLLLllLLLLL..',
      '...lLL....LLl...',
      '..OoO.OooO.OoO..',
      '.OOOOOOOOOOOOOO.',
      '................',
    ],
    [
      '................',
      '................',
      '.......1........',
      '......121.......',
      '......1221......',
      '.....12321......',
      '....1233321.....',
      '....12333321....',
      '....12333321....',
      '.....123321.....',
      '...LLl1331lLL...',
      '..LLLLLllLLLLL..',
      '...lLL....LLl...',
      '..OoO.OooO.OoO..',
      '.OOOOOOOOOOOOOO.',
      '................',
    ],
  ]

  TREE_PALETTE = {
    'G' => Pix.c(0x2F5E2A), 'g' => Pix.c(0x3F7A35), 'L' => Pix.c(0x5E9C48), 'T' => Pix.c(0x6B4A2E),
  }

  TREE = [
    '.....GGGGGG.....',
    '...GGGgggGGGG...',
    '..GGgggggggGGG..',
    '.GGggggLggggGGG.',
    '.GgggLLgggggggG.',
    'GGggggggggLgggGG',
    'GgggLgggggggggGG',
    'GGgggggggLgggGG.',
    '.GGggggggggggGG.',
    '..GGGgggggGGGG..',
    '....GGGGGGGG....',
    '.......TT.......',
    '......TTTT......',
    '......TTTT......',
    '.....TTTTTT.....',
    '................',
  ]

  def self.hero(direction, step)
    top = HERO_TOP[direction == :right ? :left : direction]
    rows = top + HERO_LEGS[step]
    rows = Pix.mirror(rows) if direction == :right
    rows
  end

  # Every hero frame in one bitmap: 4 directions × 2 steps.
  def self.hero_sheet
    bitmap = Bitmap.new(TILE * 2, TILE * 4)
    [:down, :left, :right, :up].each_with_index do |dir, row|
      2.times { |step| Pix.paint(bitmap, step * TILE, row * TILE, hero(dir, step), HERO_PALETTE) }
    end
    bitmap
  end

  def self.frames(maps, palette, scale = 2)
    size = 16 * scale
    bitmap = Bitmap.new(size * maps.size, size)
    maps.each_with_index { |rows, i| Pix.paint(bitmap, i * size, 0, rows, palette, scale) }
    bitmap
  end

  # MARK: Ground

  GRASS = Pix.c(0x5B8C3A)
  GRASS_DARK = Pix.c(0x4A7A30)
  GRASS_LIGHT = Pix.c(0x74A84C)
  PATH = Pix.c(0xC9A46A)
  PATH_DARK = Pix.c(0xAE8A52)
  WATER = Pix.c(0x3A6EA5)
  WATER_LIGHT = Pix.c(0x6AA6D6)
  WATER_DARK = Pix.c(0x2C5683)

  # A tiny deterministic noise, so the ground looks the same each time.
  def self.noise(x, y, i)
    ((x * 73 + y * 151 + i * 29 + x * y * 7) % 97)
  end

  def self.grass(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    bitmap.fill_rect(x, y, TILE, TILE, GRASS)
    6.times do |i|
      n = noise(tx, ty, i)
      px, py = (n * 3) % 15, (n * 7) % 15
      bitmap.fill_rect(x + px * 2, y + py * 2, 2, 4, i.even? ? GRASS_DARK : GRASS_LIGHT)
    end
  end

  def self.path(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    bitmap.fill_rect(x, y, TILE, TILE, PATH)
    4.times do |i|
      n = noise(tx, ty, i + 10)
      bitmap.fill_rect(x + ((n * 5) % 14) * 2, y + ((n * 3) % 14) * 2, 4, 2, PATH_DARK)
    end
  end

  def self.water(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    bitmap.fill_rect(x, y, TILE, TILE, WATER)
    bitmap.fill_rect(x, y, TILE, 2, WATER_DARK)
    2.times do |i|
      n = noise(tx, ty, i + 20)
      bitmap.fill_rect(x + 4 + (n % 10) * 2, y + 8 + i * 12, 10, 2, WATER_LIGHT)
    end
  end

  def self.flowers(bitmap, tx, ty)
    grass(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    colors = [Pix.c(0xF7B538), Pix.c(0xE89AA0), Pix.c(0xF4E9D8)]
    3.times do |i|
      n = noise(tx, ty, i + 30)
      fx, fy = x + 4 + (n % 11) * 2, y + 4 + ((n * 3) % 11) * 2
      bitmap.fill_rect(fx, fy, 4, 4, colors[i])
      bitmap.fill_rect(fx + 1, fy + 4, 2, 4, GRASS_DARK)
    end
  end

  def self.log(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    bitmap.fill_rect(x + 4, y + 14, 24, 10, Pix.c(0x6B4A2E))
    bitmap.fill_rect(x + 4, y + 14, 24, 2, Pix.c(0x8A6442))
    bitmap.fill_rect(x + 2, y + 16, 4, 6, Pix.c(0xC9A46A))
    bitmap.fill_rect(x + 26, y + 16, 4, 6, Pix.c(0xC9A46A))
  end

  def self.sign(bitmap, tx, ty)
    x, y = tx * TILE, ty * TILE
    bitmap.fill_rect(x + 14, y + 14, 4, 16, Pix.c(0x6B4A2E))
    bitmap.fill_rect(x + 4, y + 4, 24, 14, Pix.c(0x8A6442))
    bitmap.fill_rect(x + 4, y + 4, 24, 2, Pix.c(0xA67C52))
    bitmap.fill_rect(x + 8, y + 9, 16, 2, Pix.c(0x4E3420))
    bitmap.fill_rect(x + 8, y + 13, 12, 2, Pix.c(0x4E3420))
  end

  # The cottage: three tiles wide, its walls on rows ty+1..ty+2 and
  # its roof reaching up into row ty.
  def self.house(bitmap, tx, ty)
    ox, oy = tx * TILE, ty * TILE + 8
    roof, roof_dark = Pix.c(0x8A3B2A), Pix.c(0x6E2E22)
    wall, plank = Pix.c(0xE8D3B0), Pix.c(0xD4BB92)
    wood, glow = Pix.c(0x6B4A2E), Pix.c(0xF7B538)
    # Chimney.
    bitmap.fill_rect(ox + 68, oy - 4, 10, 20, Pix.c(0x7A6A60))
    # Roof, in pixel steps.
    16.times do |r|
      inset = ((16 - r) * 2.5).round
      bitmap.fill_rect(ox + inset, oy + r * 2, 96 - inset * 2, 2, r % 4 == 3 ? roof_dark : roof)
    end
    # Walls.
    bitmap.fill_rect(ox + 6, oy + 32, 84, 48, wall)
    4.times { |i| bitmap.fill_rect(ox + 6, oy + 40 + i * 10, 84, 2, plank) }
    # Windows, lit from inside.
    [14, 62].each do |wx|
      bitmap.fill_rect(ox + wx, oy + 42, 20, 16, wood)
      bitmap.fill_rect(ox + wx + 2, oy + 44, 16, 12, glow)
      bitmap.fill_rect(ox + wx + 9, oy + 44, 2, 12, wood)
      bitmap.fill_rect(ox + wx + 2, oy + 49, 16, 2, wood)
    end
    # Door.
    bitmap.fill_rect(ox + 40, oy + 52, 16, 28, wood)
    bitmap.fill_rect(ox + 42, oy + 54, 12, 26, Pix.c(0x8A6442))
    bitmap.fill_rect(ox + 50, oy + 66, 2, 2, glow)
  end
end
