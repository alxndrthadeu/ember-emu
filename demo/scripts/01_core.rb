# encoding: utf-8
#
# A Última Brasa: the small demo game that ships with Ember.
# Original code and art (drawn here, pixel by pixel). No RPG Maker
# default scripts and no RTP: it runs on the engine alone.
#
# Ruby 1.9 compatible (the engine runs RGSS3 games on Ruby 1.9).

module Demo
  LANG = begin
    code = System.user_language.to_s.downcase[0, 2]
    code == 'pt' ? :pt : (code == 'es' ? :es : :en)
  rescue StandardError
    :en
  end

  TEXT = {
    :title     => { :pt => 'A Última Brasa', :en => 'The Last Ember', :es => 'La Última Brasa' },
    :subtitle  => { :pt => 'uma pequena aventura do Ember', :en => 'a tiny Ember adventure', :es => 'una pequeña aventura de Ember' },
    :new_game  => { :pt => 'Novo jogo', :en => 'New game', :es => 'Nueva partida' },
    :continue  => { :pt => 'Continuar', :en => 'Continue', :es => 'Continuar' },
    :quit      => { :pt => 'Sair', :en => 'Quit', :es => 'Salir' },
    :items     => { :pt => 'Itens', :en => 'Items', :es => 'Objetos' },
    :status    => { :pt => 'Status', :en => 'Status', :es => 'Estado' },
    :save      => { :pt => 'Salvar', :en => 'Save', :es => 'Guardar' },
    :close     => { :pt => 'Fechar', :en => 'Close', :es => 'Cerrar' },
    :saved     => { :pt => 'Progresso salvo', :en => 'Progress saved', :es => 'Progreso guardado' },
    :level     => { :pt => 'Nv.', :en => 'Lv.', :es => 'Nv.' },
    :gold      => { :pt => 'Moedas', :en => 'Coins', :es => 'Monedas' },
    :place     => { :pt => 'Acampamento da Brasa', :en => 'Ember Camp', :es => 'Campamento de la Brasa' },
    :cat       => { :pt => 'Faísca', :en => 'Spark', :es => 'Chispa' },
    :hero      => { :pt => 'Lia', :en => 'Lia', :es => 'Lia' },
    :hero_role => { :pt => 'Guardiã da fogueira', :en => 'Keeper of the fire', :es => 'Guardiana del fuego' },
    :potion    => { :pt => 'Poção de brasa', :en => 'Ember potion', :es => 'Poción de brasa' },
    :bread     => { :pt => 'Pão de mel', :en => 'Honey bread', :es => 'Pan de miel' },
    :map_item  => { :pt => 'Mapa antigo', :en => 'Old map', :es => 'Mapa antiguo' },
    :lantern   => { :pt => 'Lanterna', :en => 'Lantern', :es => 'Linterna' },
  }

  TALK = {
    :cat => {
      :pt => [[:cat, 'Miau! Você também veio se aquecer na fogueira?'],
              [:cat, 'Dizem que esta é a última brasa da floresta. Enquanto ela queimar, a noite não vence.'],
              [:hero, 'Então eu cuido dela. Prometo.']],
      :en => [[:cat, 'Meow! Did you come to warm up by the fire too?'],
              [:cat, 'They say this is the last ember in the forest. As long as it burns, the night cannot win.'],
              [:hero, 'Then I will look after it. I promise.']],
      :es => [[:cat, '¡Miau! ¿Tú también viniste a calentarte junto al fuego?'],
              [:cat, 'Dicen que esta es la última brasa del bosque. Mientras arda, la noche no gana.'],
              [:hero, 'Entonces yo la cuidaré. Lo prometo.']],
    },
    :fire => {
      :pt => [[nil, 'O fogo estala baixinho. Um calor gostoso sobe pelas mãos.']],
      :en => [[nil, 'The fire crackles softly. A pleasant warmth rises through your hands.']],
      :es => [[nil, 'El fuego chisporrotea suave. Un calor agradable sube por las manos.']],
    },
    :sign => {
      :pt => [[nil, 'Acampamento da Brasa. Descanse aqui, viajante, e deixe o fogo aceso.']],
      :en => [[nil, 'Ember Camp. Rest here, traveler, and keep the fire alive.']],
      :es => [[nil, 'Campamento de la Brasa. Descansa aquí, viajero, y mantén el fuego vivo.']],
    },
    :door => {
      :pt => [[nil, 'A porta está trancada. Talvez numa próxima versão.']],
      :en => [[nil, 'The door is locked. Maybe in the next version.']],
      :es => [[nil, 'La puerta está cerrada. Quizás en la próxima versión.']],
    },
    :water => {
      :pt => [[nil, 'O lago reflete as estrelas.']],
      :en => [[nil, 'The pond reflects the stars.']],
      :es => [[nil, 'El lago refleja las estrellas.']],
    },
  }

  def self.t(key)
    TEXT[key][LANG]
  end

  def self.talk(key)
    TALK[key][LANG]
  end

  # A real save file, like any RPG Maker VX Ace game: Save01.rvdata2 in
  # the game folder, so Ember's saves screen, export and AirDrop work.
  SAVE_FILE = 'Save01.rvdata2'

  def self.save_game(map)
    data = { 'version' => 1, 'x' => map.hx, 'y' => map.hy, 'facing' => map.facing.to_s }
    File.open(SAVE_FILE, 'wb') { |f| Marshal.dump(data, f) }
    true
  rescue Exception
    false
  end

  def self.saved_game
    return nil unless File.exist?(SAVE_FILE)
    data = File.open(SAVE_FILE, 'rb') { |f| Marshal.load(f) }
    data.is_a?(Hash) && data['version'] == 1 ? data : nil
  rescue Exception
    nil
  end
end

# Colors and drawing helpers.
module Pix
  def self.c(hex, alpha = 255)
    Color.new((hex >> 16) & 255, (hex >> 8) & 255, hex & 255, alpha)
  end

  # Paints rows of characters, one palette entry per character
  # ('.' and missing keys are transparent), `scale` pixels each.
  def self.paint(bitmap, x, y, rows, palette, scale = 2)
    rows.each_with_index do |row, ry|
      row.length.times do |rx|
        color = palette[row[rx, 1]]
        next unless color
        bitmap.fill_rect(x + rx * scale, y + ry * scale, scale, scale, color)
      end
    end
  end

  def self.mirror(rows)
    rows.map { |row| row.reverse }
  end

  # A rounded rectangle.
  def self.round_rect(bitmap, x, y, w, h, color, r = 6)
    bitmap.fill_rect(x + r, y, w - r * 2, h, color)
    bitmap.fill_rect(x, y + r, w, h - r * 2, color)
    r.times do |i|
      inset = (r - Math.sqrt(r * r - (r - i - 0.5) ** 2)).round
      bitmap.fill_rect(x + inset, y + i, w - inset * 2, 1, color)
      bitmap.fill_rect(x + inset, y + h - 1 - i, w - inset * 2, 1, color)
    end
  end

  # A panel: a cream edge around a dark warm fill.
  def self.panel(bitmap, x, y, w, h, fill = c(0x2B211C, 236), edge = c(0xF4E9D8, 230))
    round_rect(bitmap, x, y, w, h, edge, 8)
    round_rect(bitmap, x + 2, y + 2, w - 4, h - 4, fill, 7)
  end

  # Splits text into lines that fit `width` with the bitmap's font.
  def self.wrap(bitmap, text, width)
    lines = []
    line = ''
    text.split(' ').each do |word|
      candidate = line.empty? ? word : line + ' ' + word
      if bitmap.text_size(candidate).width > width && !line.empty?
        lines << line
        line = word
      else
        line = candidate
      end
    end
    lines << line unless line.empty?
    lines
  end

  # A small down-pointing triangle (the "more text" cursor).
  def self.triangle(bitmap, x, y, color)
    5.times { |i| bitmap.fill_rect(x + i, y + i, 10 - i * 2, 1, color) }
  end
end
