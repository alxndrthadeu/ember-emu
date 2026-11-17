# Ember preload: the game's messages translated on the device.
#
# When the player turns "Traduzir textos" on for a game, Ember sets
# EMBER_TRANSLATE_DIR. Each message about to show is sent to the app,
# which translates it with Apple's Translation framework (on the
# iPhone, nothing goes to a server) and writes the answer back:
#
#   req/<key>.txt   written here: the message, control codes replaced
#                   by markers the translation keeps
#   out/<key>.txt   written by the app: the translation
#
# Answers stay in out/ for the next time (the same line costs nothing
# twice). A message waits for its translation up to WAIT_FRAMES while
# the screen keeps drawing; if none comes, it shows as it was.
#
# Hooks, installed once the game's classes exist:
#   Pokémon Essentials   pbMessageDisplay (every message window)
#   RPG Maker VX Ace     Game_Message#all_text
#   RPG Maker VX         Window_Message#start_message ($game_message.texts)
#   RPG Maker XP         Window_Message#refresh ($game_temp.message_text)
#
# Must run on Ruby 1.8, 1.9 and 3.1: no modern syntax.

module EmberTranslate
  DIR = ENV['EMBER_TRANSLATE_DIR'].to_s
  WAIT_FRAMES = 150
  # \C[2], \N[1], \V[10], \G, \., \|, \!, \>, \<, \^, \$ and Essentials'
  # <ac>, <b>, <c2=...> tags: kept out of the translation.
  CODE = /\\[A-Za-z]+\[[^\]]*\]|\\[A-Za-z{}|.!<>^$]|<\/?[a-z0-9]+(=[^>]*)?>/

  @cache = {}
  @installed = false

  class << self
    def enabled?
      !DIR.empty?
    end

    def translate(text)
      return text unless enabled? && text.is_a?(String)
      plain = text.gsub(CODE, '').strip
      return text if plain.empty? || plain !~ /[[:alpha:]]|[^\x00-\x7F]/
      return @cache[text] if @cache.key?(text)

      codes = []
      marked = text.gsub(CODE) { |code| codes << code; "{#{codes.size - 1}}" }
      key = format('%08x%04x', Zlib.crc32(marked), marked.length % 65536)
      out = File.join(DIR, 'out', key + '.txt')
      unless File.exist?(out)
        req = File.join(DIR, 'req', key + '.txt')
        File.open(req + '.tmp', 'wb') { |f| f.write(marked) }
        File.rename(req + '.tmp', req)
        frames = 0
        while !File.exist?(out) && frames < WAIT_FRAMES
          Graphics.update
          frames += 1
        end
      end
      result = text
      if File.exist?(out)
        translated = File.open(out, 'rb') { |f| f.read }.to_s
        translated.force_encoding('UTF-8') if translated.respond_to?(:force_encoding)
        unless translated.strip.empty?
          result = translated.gsub(/\{(\d+)\}/) { codes[$1.to_i] || '' }
        end
      end
      @cache[text] = result
      result
    rescue Exception => e
      puts "[ember-translate] #{e.class}: #{e.message}"
      text
    end

    # Lines for windows that do not wrap (RPG Maker XP and VX): the
    # translation goes back into about as many characters per line as
    # the original had.
    def rewrap(original_lines, translated)
      width = original_lines.map { |l| l.to_s.gsub(CODE, '').length }.max.to_i
      width = 40 if width < 20
      lines = []
      line = ''
      translated.split(/\s+/).each do |word|
        if !line.empty? && (line.gsub(CODE, '').length + 1 + word.gsub(CODE, '').length) > width
          lines << line
          line = word
        else
          line = line.empty? ? word : line + ' ' + word
        end
      end
      lines << line unless line.empty?
      lines
    end

    def install_hooks
      return if @installed
      if Object.private_method_defined?(:pbMessageDisplay) || Object.method_defined?(:pbMessageDisplay)
        Object.class_eval do
          alias_method :ember_tr_pbMessageDisplay, :pbMessageDisplay
          def pbMessageDisplay(msgwindow, message, *args, &block)
            ember_tr_pbMessageDisplay(msgwindow, EmberTranslate.translate(message), *args, &block)
          end
          private :pbMessageDisplay
        end
        @installed = true
      elsif defined?(Game_Message) && Game_Message.method_defined?(:all_text)
        Game_Message.class_eval do
          alias_method :ember_tr_all_text, :all_text
          def all_text
            EmberTranslate.translate(ember_tr_all_text)
          end
        end
        @installed = true
      elsif defined?(Window_Message) && Window_Message.method_defined?(:start_message) &&
            defined?(Game_Message) && Game_Message.method_defined?(:texts)
        Window_Message.class_eval do
          alias_method :ember_tr_start_message, :start_message
          def start_message(*args)
            texts = $game_message.texts
            unless texts.empty?
              joined = texts.join(' ')
              translated = EmberTranslate.translate(joined)
              if translated != joined
                lines = EmberTranslate.rewrap(texts, translated)
                texts.clear
                lines.each { |l| texts << l }
              end
            end
            ember_tr_start_message(*args)
          end
        end
        @installed = true
      elsif defined?(Window_Message) && Window_Message.method_defined?(:refresh) && $game_temp &&
            $game_temp.respond_to?(:message_text)
        Window_Message.class_eval do
          alias_method :ember_tr_refresh, :refresh
          def refresh(*args)
            text = $game_temp.message_text
            if text && text != @ember_tr_done
              lines = text.split("\n")
              translated = EmberTranslate.translate(lines.join(' '))
              if translated != lines.join(' ')
                text = EmberTranslate.rewrap(lines, translated).join("\n")
                $game_temp.message_text = text
              end
              @ember_tr_done = text
            end
            ember_tr_refresh(*args)
          end
        end
        @installed = true
      end
      puts "[ember-translate] hooked" if @installed
    rescue Exception => e
      puts "[ember-translate] hook failed: #{e.class}: #{e.message}"
      @installed = true
    end

    def installed?
      @installed
    end
  end
end

if EmberTranslate.enabled?
  [File.join(EmberTranslate::DIR, 'req'), File.join(EmberTranslate::DIR, 'out')].each do |dir|
    Dir.mkdir(dir) unless File.directory?(dir)
  end
  puts "[ember-translate] on, folder: #{EmberTranslate::DIR}"
  class << Graphics
    unless method_defined?(:ember_tr_original_update)
      alias_method :ember_tr_original_update, :update
      def update(*args)
        ember_tr_original_update(*args)
        EmberTranslate.install_hooks unless EmberTranslate.installed?
      end
    end
  end
end
