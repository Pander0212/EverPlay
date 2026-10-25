# EverPlay cheats for RPG Maker XP, VX and VX Ace games under mkxp-z: the same methods as
# RPGMakerCheats.js for MV/MZ, so EverPlay shows the same cheat screen. EverPlay loads this file
# before the game's own scripts (mkxp.json "preloadScript"). The cheat screen writes one request per
# file into DIR ("call <id> <method> <arguments>", tab-separated); the game answers at its next
# frames with reply-<id>.json. Only the methods below exist: nothing read is evaluated as code.
module EverPlayCheats
  DIR = File.join(ENV['TMPDIR'] || '/tmp', 'everplay-rgss')
  LIMIT = 400

  @state = { speed: 1, through: false, no_encounters: false, god: false }
  @frame = 0
  @base_rate = nil

  class << self
    def tick
      @frame += 1
      poll if @frame % 3 == 0
      hold
    rescue StandardError
      nil
    end

    private

    def poll
      Dir.glob(File.join(DIR, 'request-*')).each do |path|
        line = File.read(path)
        File.delete(path)
        words = line.chomp.split("\t")
        next unless words[0] == 'call' && words[1] =~ /\A[\w-]+\z/
        answer(words[1], words[2], words[3..-1].map { |word| argument(word) })
      end
    end

    def argument(word)
      kind, value = word.split(':', 2)
      case kind
      when 'n' then value.include?('.') ? value.to_f : value.to_i
      when 'b' then value == '1'
      else value.to_s
      end
    end

    METHODS = %w[status addGold setGold heal levelUp setSpeed setThrough setNoEncounters setGod
                 variables setVariable switches setSwitch items gainItem].freeze

    def answer(id, method, arguments)
      result = METHODS.include?(method) ? send(method, *arguments) : nil
      json = encode(result)
    rescue StandardError => error
      json = encode({ 'error' => error.message })
    ensure
      path = File.join(DIR, "reply-#{id}.json")
      File.write(path + '.tmp', json)
      File.rename(path + '.tmp', path)
    end

    # RPG Maker data is UTF-8 text, numbers, flags, arrays and hashes.
    def encode(value)
      case value
      when nil then 'null'
      when true then 'true'
      when false then 'false'
      when Integer then value.to_s
      when Float then value.finite? ? value.to_s : 'null'
      when Array then '[' + value.map { |entry| encode(entry) }.join(',') + ']'
      when Hash then '{' + value.map { |key, entry| encode(key.to_s) + ':' + encode(entry) }.join(',') + '}'
      else
        text = value.to_s.dup.force_encoding('UTF-8').scrub('?')
        '"' + text.gsub(/[\\"\u0000-\u001f]/) { |c| c == '\\' || c == '"' ? "\\#{c}" : format('\\u%04x', c.ord) } + '"'
      end
    end

    def ready?
      !$game_party.nil? && !$data_system.nil? && !$game_variables.nil? && !$game_switches.nil?
    end

    def members
      return $game_party.all_members if $game_party.respond_to?(:all_members)
      return $game_party.members if $game_party.respond_to?(:members)
      $game_party.actors
    end

    def engine
      return 'RPG Maker VX Ace' if defined?(RPG::BaseItem) && $game_party.respond_to?(:all_members)
      defined?(RPG::BaseItem) ? 'RPG Maker VX' : 'RPG Maker XP'
    end

    def max_hp(actor) = actor.respond_to?(:mhp) ? actor.mhp : actor.maxhp
    def mp(actor) = actor.respond_to?(:mp) ? actor.mp : actor.sp

    def max_mp(actor)
      return actor.mmp if actor.respond_to?(:mmp)
      actor.respond_to?(:maxmp) ? actor.maxmp : actor.maxsp
    end

    def max_gold = $game_party.respond_to?(:max_gold) ? $game_party.max_gold : 9_999_999

    def status
      return { 'engine' => engine, 'ready' => false } unless ready?
      {
        'engine' => engine, 'ready' => true, 'gold' => $game_party.gold, 'maxGold' => max_gold,
        'party' => members.map do |actor|
          { 'id' => actor.id, 'name' => actor.name, 'level' => actor.level, 'hp' => actor.hp,
            'mhp' => max_hp(actor), 'mp' => mp(actor), 'mmp' => max_mp(actor) }
        end,
        'speed' => @state[:speed], 'through' => @state[:through], 'noEncounters' => @state[:no_encounters],
        'god' => @state[:god]
      }
    end

    def addGold(amount)
      $game_party.gain_gold(amount.to_i)
      status
    end

    def setGold(amount)
      $game_party.gain_gold(amount.to_i - $game_party.gold)
      status
    end

    def heal
      members.each(&:recover_all)
      status
    end

    def levelUp(levels)
      members.each do |actor|
        top = actor.respond_to?(:max_level) ? actor.max_level : 99
        level = [[actor.level + levels.to_i, 1].max, top].min
        actor.respond_to?(:change_level) ? actor.change_level(level, false) : actor.level = level
      end
      status
    end

    # Runs the game faster by raising its frame rate (mkxp-z does not wait for the display).
    def setSpeed(speed)
      @base_rate ||= Graphics.frame_rate
      @state[:speed] = [[speed.to_i, 1].max, 4].min
      Graphics.frame_rate = @base_rate * @state[:speed]
      status
    end

    def setThrough(on)
      @state[:through] = on ? true : false
      $game_player.instance_variable_set(:@through, false) if !on && $game_player
      status
    end

    def setNoEncounters(on)
      @state[:no_encounters] = on ? true : false
      status
    end

    def setGod(on)
      @state[:god] = on ? true : false
      status
    end

    # "abc" searches names, "#12" an id, "=5" a value (as in RPGMakerCheats.js).
    def matches(query, id, name, value)
      q = query.to_s.strip.downcase
      return true if q.empty?
      return id.to_s == q[1..-1].strip if q.start_with?('#')
      return value.to_s.downcase == q[1..-1].strip if q.start_with?('=')
      name.to_s.downcase.include?(q)
    end

    def plain(value)
      value.is_a?(Numeric) || value == true || value == false || value.is_a?(String) ? value : value.inspect[0, 80]
    end

    def variables(query)
      names = $data_system.variables
      out = []
      (1...names.size).each do |id|
        break if out.size >= LIMIT
        name = names[id].to_s
        value = $game_variables[id]
        next if name.empty? && (value.nil? || value == 0)
        next unless matches(query, id, name, plain(value))
        out << { 'id' => id, 'name' => name, 'value' => plain(value), 'number' => value.is_a?(Numeric) }
      end
      out
    end

    def setVariable(id, value)
      value = value.to_i if value.is_a?(Float) && value == value.floor
      $game_variables[id.to_i] = value
      $game_map.need_refresh = true if $game_map
      true
    end

    def switches(query)
      names = $data_system.switches
      out = []
      (1...names.size).each do |id|
        break if out.size >= LIMIT
        name = names[id].to_s
        value = $game_switches[id] ? true : false
        next if name.empty? && !value
        next unless matches(query, id, name, value)
        out << { 'id' => id, 'name' => name, 'value' => value }
      end
      out
    end

    def setSwitch(id, on)
      $game_switches[id.to_i] = on ? true : false
      $game_map.need_refresh = true if $game_map
      true
    end

    def data_for(kind)
      { 'item' => $data_items, 'weapon' => $data_weapons, 'armor' => $data_armors }.fetch(kind)
    end

    # VX and VX Ace count and give item objects; XP uses ids and a method per kind.
    def count(kind, entry)
      return $game_party.item_number(entry) if defined?(RPG::BaseItem)
      $game_party.send({ 'item' => :item_number, 'weapon' => :weapon_number, 'armor' => :armor_number }[kind], entry.id)
    end

    def max_count(entry)
      $game_party.respond_to?(:max_item_number) ? $game_party.max_item_number(entry) : 99
    end

    def items(kind, query)
      out = []
      data_for(kind).each_with_index do |entry, id|
        break if out.size >= LIMIT
        next if entry.nil? || entry.name.to_s.empty?
        number = count(kind, entry)
        next unless matches(query, id, entry.name, number)
        out << { 'id' => id, 'name' => entry.name, 'count' => number, 'max' => max_count(entry) }
      end
      out
    end

    def gainItem(kind, id, amount)
      entry = data_for(kind)[id.to_i]
      raise 'unknown item' unless entry
      if defined?(RPG::BaseItem)
        $game_party.gain_item(entry, amount.to_i)
      else
        $game_party.send({ 'item' => :gain_item, 'weapon' => :gain_weapon, 'armor' => :gain_armor }[kind], entry.id, amount.to_i)
      end
      true
    end

    # These hold every frame: games reset them on map changes and battles.
    def hold
      return if $game_party.nil?
      if @state[:god]
        members.each do |actor|
          actor.hp = max_hp(actor)
          actor.respond_to?(:mp=) ? actor.mp = max_mp(actor) : actor.sp = max_mp(actor)
        end
      end
      $game_player.instance_variable_set(:@through, true) if @state[:through] && $game_player
      $game_player.instance_variable_set(:@encounter_count, 9999) if @state[:no_encounters] && $game_player
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
