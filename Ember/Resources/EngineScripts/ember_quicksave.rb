# Ember preload: save states ("save rápido") inside the game.
#
# A save state here is not a memory snapshot (the engine cannot take
# one). It is the game's own save data, taken at a quiet moment on the
# map, written to Ember's folder so the game's real save files are never
# touched. Three families of games:
#
#   :essentials  Pokémon Essentials v19+ (SaveData / Game.load)
#   :ace         RPG Maker VX Ace (DataManager)
#   :generic     RPG Maker XP / VX and older Essentials: the $game_*,
#                $Pokemon*, $Trainer... globals their own saves hold
#
# The app talks to this script through files in EMBER_STATE_DIR:
#   request   written by the app: "save:<slot>" or "load:<slot>"
#   response  written here: "ok:<verb>:<slot>", "busy:<reason>", "error:<message>"
#   <slot>.state / <slot>.png   the state and its screenshot
#   cheat_request   written by the app before it presses Input::HOME: the
#                   engine's cheat menu is loaded here if the engine has
#                   not (games that start before their last script runs)
#   thumb_request   written by the app when the game wrote a save: one
#                   PNG path per line, filled here with the last quiet
#                   map frame (the save screen itself says little)
# EMBER_AUTOSTATE_SECONDS: save slot "auto" that often, when quiet.
# EMBER_RESUME_SLOT: load that slot instead of showing the title screen.
#
# Must run on Ruby 1.8, 1.9 and 3.1: no modern syntax.

module EmberState
  DIR = ENV['EMBER_STATE_DIR'].to_s
  AUTO_SECONDS = ENV['EMBER_AUTOSTATE_SECONDS'].to_i
  POLL_FRAMES = 10
  # How often the last quiet map frame is kept for save thumbnails
  # (a GPU copy, no encoding until a save asks for it).
  SNAP_FRAMES = 180

  @frame = 0
  @last_auto = Time.now
  @resume_slot = ENV['EMBER_RESUME_SLOT']
  @resume_slot = nil if @resume_slot.to_s.empty?
  @busy = false

  class << self
    attr_accessor :resume_slot

    def enabled?
      !DIR.empty?
    end

    def kind
      if defined?(SaveData) && SaveData.respond_to?(:compile_save_hash) && defined?(Game) && Game.respond_to?(:load)
        :essentials
      elsif defined?(DataManager) && DataManager.respond_to?(:make_save_contents)
        :ace
      else
        :generic
      end
    end

    # --- Called every frame -------------------------------------------

    def tick
      return unless enabled?
      return if @busy
      @frame += 1
      return unless @frame % POLL_FRAMES == 0
      @busy = true
      begin
        install_title_hooks unless @hooked
        install_map_hook unless @map_hooked
        handle_thumbs
        handle_cheat_request
        handle_filter_request
        keep_map_frame
        handle_request
        autosave
      rescue Exception => e
        respond("error:#{e.class}: #{e.message}")
      ensure
        @busy = false
      end
    end

    def handle_request
      path = File.join(DIR, 'request')
      return unless File.exist?(path)
      text = File.open(path, 'rb') { |f| f.read }.to_s.strip
      verb, slot = text.split(':', 2)
      slot = 'auto' if slot.to_s.empty?
      reason = quiet_reason
      if reason
        # The app waits a little and gives up; a later frame may be
        # quiet enough, so the request stays.
        respond("busy:#{reason}")
        return
      end
      File.delete(path) rescue nil
      if verb == 'save'
        save(slot)
        respond("ok:save:#{slot}")
      elsif verb == 'load'
        payload = read(slot)
        if payload
          # Restored at the start of the next Scene_Map#update, never in
          # the middle of a frame: the old scene must not run another
          # update against the new game state.
          @pending_load = [slot, payload]
        else
          respond("error:no state #{slot}")
        end
      end
    end

    # --- Cheats -----------------------------------------------------------

    def handle_cheat_request
      path = File.join(DIR, 'cheat_request')
      return unless File.exist?(path)
      File.delete(path) rescue nil
      load_cheat_menu unless defined?(Scene_Cheat)
    end

    # The engine loads its cheat menu right before a game's last script
    # section; games whose loop starts earlier (The Witch's House) never
    # get there. Same choice as the engine's ScriptBootstrap.
    def load_cheat_menu
      dir = ENV['EMBER_POSTLOAD_DIR'].to_s
      return if dir.empty?
      name = if defined?(GameData) || defined?(PBItems) then 'cheat_pe19'
             elsif defined?(SceneManager) then 'cheat_rpgmvxace'
             elsif defined?(Window_Base) && Window_Base.method_defined?(:draw_currency_value) then 'cheat_rpgmvx'
             else 'cheat_rpgmxp'
             end
      file = File.join(dir, name + '.rb')
      return unless File.exist?(file)
      eval(File.open(file, 'rb') { |f| f.read }, TOPLEVEL_BINDING, name + '.rb')
      puts "[ember-state] cheat menu loaded late: #{name}"
    rescue Exception => e
      puts "[ember-state] cheat menu failed: #{e.class}: #{e.message}"
    end

    # --- Screen filter ----------------------------------------------------

    def handle_filter_request
      path = File.join(DIR, 'filter_request')
      return unless File.exist?(path)
      value = File.open(path, 'rb') { |f| f.read }.to_i
      File.delete(path) rescue nil
      Graphics.smooth_scaling = value if Graphics.respond_to?(:smooth_scaling=)
    rescue Exception
    end

    # --- Save thumbnails --------------------------------------------------

    def keep_map_frame
      return unless @frame % SNAP_FRAMES == 0
      # A game with its own scenes (Ember's demo) can say when its map
      # is free of menus and messages through $ember_quiet_map.
      if $ember_quiet_map.nil?
        return if quiet_reason
      else
        return unless $ember_quiet_map
      end
      return unless Graphics.respond_to?(:snap_to_bitmap)
      frame = Graphics.snap_to_bitmap
      @map_frame.dispose if @map_frame && !@map_frame.disposed?
      @map_frame = frame
    rescue Exception
    end

    def handle_thumbs
      path = File.join(DIR, 'thumb_request')
      return unless File.exist?(path)
      targets = File.open(path, 'rb') { |f| f.read }.to_s.split("\n")
      File.delete(path) rescue nil
      targets.each do |target|
        target = target.strip
        next if target.empty?
        begin
          if @map_frame && !@map_frame.disposed? && @map_frame.respond_to?(:to_file)
            @map_frame.to_file(target)
          elsif Graphics.respond_to?(:screenshot)
            Graphics.screenshot(target)
          end
        rescue Exception
        end
      end
    end

    def autosave
      return if AUTO_SECONDS <= 0
      return if Time.now - @last_auto < AUTO_SECONDS
      return if quiet_reason
      save('auto')
      @last_auto = Time.now
    end

    # --- Is now a safe moment? ----------------------------------------

    def current_scene
      if defined?(SceneManager) && SceneManager.respond_to?(:scene)
        SceneManager.scene
      else
        $scene
      end
    end

    # Nil when it is safe to save; otherwise why not.
    def quiet_reason
      return 'scene' unless defined?(Scene_Map) && current_scene.is_a?(Scene_Map)
      interpreter = nil
      begin
        interpreter = $game_system.map_interpreter if $game_system.respond_to?(:map_interpreter)
      rescue Exception
      end
      begin
        interpreter ||= $game_map.interpreter if $game_map && $game_map.respond_to?(:interpreter)
      rescue Exception
      end
      return 'event' if interpreter && interpreter.respond_to?(:running?) && interpreter.running?
      if $game_temp
        return 'message' if $game_temp.respond_to?(:message_window_showing) && $game_temp.message_window_showing
        return 'battle' if $game_temp.respond_to?(:in_battle) && $game_temp.in_battle
        return 'menu' if $game_temp.respond_to?(:in_menu) && $game_temp.in_menu
        return 'transfer' if $game_temp.respond_to?(:player_transferring) && $game_temp.player_transferring
      end
      if defined?($game_message) && $game_message && $game_message.respond_to?(:visible) && $game_message.visible
        return 'message'
      end
      if $game_player
        return 'moving' if $game_player.respond_to?(:moving?) && $game_player.moving?
        return 'transfer' if $game_player.respond_to?(:transfer?) && $game_player.transfer?
      end
      nil
    end

    # --- Save -----------------------------------------------------------

    def save(slot)
      data = case kind
             when :essentials then SaveData.compile_save_hash
             when :ace then DataManager.make_save_contents
             else generic_dump
             end
      payload = { 'ember' => 1, 'kind' => kind.to_s, 'data' => data,
                  'frame_count' => Graphics.frame_count, 'time' => Time.now.to_i }
      final = File.join(DIR, "#{slot}.state")
      temp = final + '.tmp'
      File.open(temp, 'wb') { |f| Marshal.dump(payload, f) }
      File.rename(temp, final)
      begin
        Graphics.screenshot(File.join(DIR, "#{slot}.png")) if Graphics.respond_to?(:screenshot)
      rescue Exception
      end
    end

    # Globals the games' own saves hold. Temporary ones ($game_temp,
    # $PokemonTemp) are rebuilt, never saved.
    GENERIC_NAME = /\A\$(game_(?!temp)|Pokemon(?!Temp)|Trainer\z|MapFactory\z|map_factory\z|player\z|bag\z|stats\z|storage\z)/

    def generic_dump
      values = {}
      global_variables.each do |name|
        name = name.to_s
        next unless name =~ GENERIC_NAME
        value = eval(name)
        next if value.nil?
        begin
          Marshal.dump(value)
          values[name] = value
        rescue Exception
          # Holds sprites, procs or IO: not game state.
        end
      end
      values
    end

    # --- Load -----------------------------------------------------------

    def read(slot)
      path = File.join(DIR, "#{slot}.state")
      return nil unless File.exist?(path)
      File.open(path, 'rb') { |f| Marshal.load(f) }
    end

    def pending_load?
      !@pending_load.nil?
    end

    # Called first thing in Scene_Map#update; the caller then returns,
    # and the scene's loop ends because $scene changed.
    def perform_pending_load
      slot, payload = @pending_load
      @pending_load = nil
      # Take the old map scene's sprites down while it is still $scene:
      # Essentials' disposal reads $scene (its map renderer), which is
      # the new scene once the state is restored. Its own disposal on
      # the way out then finds nothing left to do.
      scene = current_scene
      if scene.respond_to?(:disposeSpritesets, true)
        Graphics.freeze if Graphics.respond_to?(:freeze)
        scene.send(:disposeSpritesets)
      end
      restore(payload)
      respond("ok:load:#{slot}")
    rescue Exception => e
      respond("error:load #{e.class}: #{e.message}")
    end

    def install_map_hook
      return if @map_hooked
      return unless defined?(Scene_Map) && Scene_Map.method_defined?(:update)
      Scene_Map.class_eval do
        alias_method :ember_original_map_update, :update
        def update(*args)
          if EmberState.pending_load?
            EmberState.perform_pending_load
            return
          end
          ember_original_map_update(*args)
        end
      end
      @map_hooked = true
    end

    def restore(payload)
      Graphics.frame_count = payload['frame_count'] if payload['frame_count']
      data = payload['data']
      case payload['kind']
      when 'essentials'
        Game.load(data)
      when 'ace'
        DataManager.extract_save_contents(data)
        DataManager.reload_map_if_updated if DataManager.respond_to?(:reload_map_if_updated)
        $game_system.on_after_load if $game_system.respond_to?(:on_after_load)
        SceneManager.goto(Scene_Map)
      else
        generic_restore(data)
      end
    end

    DATABASE = %w[Actors Classes Skills Items Weapons Armors Enemies Troops
                  States Animations Tilesets CommonEvents System]

    # The title scene normally loads the database; resuming skips it.
    def ensure_database
      return unless $data_system.nil? || $data_tilesets.nil?
      ext = (defined?(RPG::BaseItem) ? 'rvdata' : 'rxdata')
      DATABASE.each do |name|
        global = "$data_" + name.gsub(/([a-z])([A-Z])/, '\\1_\\2').downcase
        begin
          @value = load_data("Data/#{name}.#{ext}")
          eval("#{global} = EmberState.instance_variable_get(:@value)")
        rescue Exception
        end
      end
      @value = nil
    end

    def generic_restore(values)
      ensure_database
      $game_temp = Game_Temp.new if defined?(Game_Temp)
      $game_message = Game_Message.new if defined?(Game_Message) && $game_message.nil?
      $PokemonTemp = PokemonTemp.new if defined?(PokemonTemp)
      values.each do |name, value|
        @value = value
        eval("#{name} = EmberState.instance_variable_get(:@value)")
      end
      @value = nil
      # Older Essentials keep the map in $MapFactory.
      factory = $MapFactory || (defined?($map_factory) ? $map_factory : nil)
      $game_map = factory.map if factory && factory.respond_to?(:map)
      if defined?(PokemonEncounters) && $game_map
        begin
          $PokemonEncounters = PokemonEncounters.new
          $PokemonEncounters.setup($game_map.map_id)
        rescue Exception
        end
      end
      begin
        $game_map.need_refresh = true if $game_map.respond_to?(:need_refresh=)
        if $game_system && $game_system.respond_to?(:bgm_play) && $game_system.respond_to?(:playing_bgm)
          $game_system.bgm_play($game_system.playing_bgm)
        elsif $game_map.respond_to?(:autoplay)
          $game_map.autoplay
        end
        $game_map.update if $game_map.respond_to?(:update)
        $PokemonMap.updateMap if defined?($PokemonMap) && $PokemonMap && $PokemonMap.respond_to?(:updateMap)
      rescue Exception
      end
      $scene = Scene_Map.new
    end

    # --- Resume at launch -------------------------------------------------

    # Called where the title or load screen would start. True when the
    # game was resumed (the caller then skips its screen).
    def resume_at_title
      slot = @resume_slot
      return false unless slot && enabled?
      @resume_slot = nil
      payload = read(slot)
      return false unless payload
      restore(payload)
      respond("ok:resume:#{slot}")
      true
    rescue Exception => e
      respond("error:resume #{e.class}: #{e.message}")
      false
    end

    # Skips the title / load screen when a resume slot is waiting.
    def install_title_hooks
      return if @hooked || @resume_slot.nil?
      if defined?(PokemonLoadScreen) && PokemonLoadScreen.method_defined?(:pbStartLoadScreen)
        PokemonLoadScreen.class_eval do
          alias_method :ember_original_pbStartLoadScreen, :pbStartLoadScreen
          def pbStartLoadScreen(*args)
            return if EmberState.resume_at_title
            ember_original_pbStartLoadScreen(*args)
          end
        end
        @hooked = true
      elsif defined?(Scene_Title) && Scene_Title.method_defined?(:main)
        Scene_Title.class_eval do
          alias_method :ember_original_main, :main
          def main(*args)
            if EmberState.resume_slot
              # RPG Maker loads its database in the title scene; resuming
              # skips the scene (generic_restore loads what is missing).
              send(:load_database) if respond_to?(:load_database, true)   # VX
              return if EmberState.resume_at_title
            end
            ember_original_main(*args)
          end
        end
        @hooked = true
      end
    end

    def respond(text)
      return unless enabled?
      File.open(File.join(DIR, 'response'), 'wb') { |f| f.write(text) }
    rescue Exception
    end
  end
end

puts "[ember-state] loaded, folder: #{EmberState::DIR.empty? ? '(none)' : EmberState::DIR}"

if EmberState.enabled?
  # Poll the app's requests once every few frames.
  class << Graphics
    unless method_defined?(:ember_original_update)
      alias_method :ember_original_update, :update
      def update(*args)
        ember_original_update(*args)
        EmberState.tick
      end
    end
  end

  # Resume hooks go in as soon as the game's classes exist. Some games
  # (Pokémon Flux) load their real scripts at run time, after postload,
  # so EmberState.tick keeps trying until a title class shows up.
  EmberState.install_title_hooks
end
