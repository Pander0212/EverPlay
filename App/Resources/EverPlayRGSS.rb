# EverPlay cheats for RPG Maker XP, VX and VX Ace games under mkxp-z. EverPlay loads this file
# before the game's own scripts (mkxp.json "preloadScript"). The in-game EverPlay menu appends
# commands to COMMAND; the game applies them at its next frames. Only the fixed commands below
# exist: nothing read from the file is evaluated as code.
module EverPlayCheats
  DIR = File.join(ENV['TMPDIR'] || '/tmp', 'everplay-rgss')
  COMMAND = File.join(DIR, 'command')
  REPORT = File.join(DIR, 'report')

  @flags = {}
  @frame = 0

  class << self
    def tick
      @frame += 1
      poll if @frame % 6 == 0
      apply_flags unless @flags.empty?
    rescue StandardError
      nil
    end

    private

    def poll
      return unless File.exist?(COMMAND)
      taken = COMMAND + '.taking'
      File.rename(COMMAND, taken)
      lines = File.read(taken).split("\n")
      File.delete(taken)
      lines.each { |line| run(line.split(' ')) }
    end

    def run(words)
      return if $game_party.nil?
      case words[0]
      when 'gold' then $game_party.gain_gold(words[1].to_i)
      when 'heal' then members.each(&:recover_all)
      when 'level' then members.each { |actor| max_level(actor) }
      when 'items' then give_items(words[1].to_i)
      when 'flag'
        @flags[words[1]] = (words[2] == 'on')
        $game_player.instance_variable_set(:@through, false) if words[1] == 'through' && words[2] != 'on' && $game_player
      when 'variable' then set_variable(words[1].to_i, words[2].to_i)
      when 'switch' then set_switch(words[1].to_i, words[2] == 'on')
      when 'report' then report
      end
    rescue StandardError
      nil
    end

    def members
      return $game_party.all_members if $game_party.respond_to?(:all_members)
      return $game_party.members if $game_party.respond_to?(:members)
      $game_party.actors
    end

    def max_level(actor)
      if actor.respond_to?(:change_level)
        actor.change_level(actor.respond_to?(:max_level) ? actor.max_level : 99, false)
      else
        actor.level = 99
      end
      actor.recover_all
    end

    # VX and VX Ace take item objects; XP takes ids and has a method per kind.
    def give_items(count)
      if defined?(RPG::BaseItem)
        [$data_items, $data_weapons, $data_armors].each do |list|
          list.each { |item| $game_party.gain_item(item, count) if item && !item.name.empty? }
        end
      else
        $data_items.each { |item| $game_party.gain_item(item.id, count) if item && !item.name.empty? }
        $data_weapons.each { |item| $game_party.gain_weapon(item.id, count) if item && !item.name.empty? }
        $data_armors.each { |item| $game_party.gain_armor(item.id, count) if item && !item.name.empty? }
      end
    end

    def set_variable(id, value)
      return unless $game_variables && id > 0
      $game_variables[id] = value
      $game_map.need_refresh = true if $game_map
    end

    def set_switch(id, value)
      return unless $game_switches && id > 0
      $game_switches[id] = value
      $game_map.need_refresh = true if $game_map
    end

    # Flags hold every frame: games reset these on map changes and battles.
    def apply_flags
      return if $game_party.nil?
      if @flags['god']
        members.each do |actor|
          actor.hp = actor.respond_to?(:mhp) ? actor.mhp : actor.maxhp
          if actor.respond_to?(:mmp) then actor.mp = actor.mmp
          elsif actor.respond_to?(:maxmp) then actor.mp = actor.maxmp
          elsif actor.respond_to?(:maxsp) then actor.sp = actor.maxsp
          end
        end
      end
      $game_player.instance_variable_set(:@through, true) if @flags['through'] && $game_player
      $game_player.instance_variable_set(:@encounter_count, 9999) if @flags['noencounter'] && $game_player
    end

    # Named variables and switches, and those in use, for the menu's list.
    def report
      lines = ["gold\t#{$game_party.gold}"]
      names = $data_system.variables
      (1...names.size).each do |id|
        value = $game_variables[id]
        next if (names[id].nil? || names[id].empty?) && (value.nil? || value == 0)
        lines << "variable\t#{id}\t#{names[id]}\t#{value.is_a?(Numeric) ? value : value.inspect}"
      end
      names = $data_system.switches
      (1...names.size).each do |id|
        value = $game_switches[id]
        next if (names[id].nil? || names[id].empty?) && !value
        lines << "switch\t#{id}\t#{names[id]}\t#{value ? 'on' : 'off'}"
      end
      File.write(REPORT + '.tmp', lines.join("\n"))
      File.rename(REPORT + '.tmp', REPORT)
    end
  end
end

class << Graphics
  alias_method :everplay_update, :update

  def update(*args)
    EverPlayCheats.tick
    everplay_update(*args)
  end
end
