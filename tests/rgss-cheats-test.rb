# Runs App/Resources/EverPlayRGSS.rb against small stand-ins for VX Ace and XP: ruby tests/rgss-cheats-test.rb
require 'json'
require 'tmpdir'
ENV['TMPDIR'] = Dir.mktmpdir
module Graphics
  @frames = 0
  @frame_rate = 60
  class << self
    attr_accessor :frame_rate
    def update; @frames += 1; end
    def frames; @frames; end
  end
end
load File.expand_path('../App/Resources/EverPlayRGSS.rb', __dir__)
Dir.mkdir(EverPlayCheats::DIR)

Item = Struct.new(:id, :name)
class Actor
  attr_accessor :hp, :mp, :sp, :level
  attr_reader :id, :name
  def initialize(id, name); @id = id; @name = name; @hp = 1; @mp = 1; @sp = 1; @level = 1; end
  def recover_all; @hp = 100; end
end
class AceActor < Actor
  def mhp; 500; end
  def mmp; 50; end
  def max_level; 99; end
  def change_level(level, _show); @level = level; end
end
class XPActor < Actor
  undef_method :mp, :mp=
  def maxhp; 300; end
  def maxsp; 30; end
end
class Party
  attr_reader :gold, :actors
  def initialize(actors); @gold = 0; @counts = Hash.new(0); @actors = actors; end
  def gain_gold(n); @gold += n; end
  def counts; @counts; end
end
class AceParty < Party
  def all_members; actors; end
  def max_gold; 99_999_999; end
  def gain_item(item, n); @counts[item.name] += n; end
  def item_number(item); @counts[item.name]; end
  def max_item_number(_item); 99; end
end
class XPParty < Party
  def gain_item(id, n); @counts["i#{id}"] += n; end
  def gain_weapon(id, n); @counts["w#{id}"] += n; end
  def gain_armor(id, n); @counts["a#{id}"] += n; end
  def item_number(id); @counts["i#{id}"]; end
  def weapon_number(id); @counts["w#{id}"]; end
  def armor_number(id); @counts["a#{id}"]; end
end
class Player; end
class MapStub; attr_accessor :need_refresh; end
System = Struct.new(:variables, :switches)

$next = 0
def call(method, *args)
  $next += 1
  encoded = args.map { |a| a == true || a == false ? "b:#{a ? 1 : 0}" : a.is_a?(Numeric) ? "n:#{a}" : "s:#{a}" }
  File.write(File.join(EverPlayCheats::DIR, "request-#{$next}"), (['call', $next.to_s, method] + encoded).join("\t"))
  3.times { Graphics.update }
  path = File.join(EverPlayCheats::DIR, "reply-#{$next}.json")
  reply = JSON.parse(File.read(path))
  File.delete(path)
  reply
end
def check(ok, what) = (puts((ok ? 'ok   ' : 'FAIL ') + what); exit 1 unless ok)

check(call('status') == { 'engine' => 'RPG Maker XP', 'ready' => false }, 'not ready before a game')

# VX Ace: item objects, all_members, mhp/mmp.
module RPG; class BaseItem; end; end
$data_items = [nil, Item.new(1, 'Potion "big"'), Item.new(2, '')]
$data_weapons = [nil, Item.new(1, 'Sword')]
$data_armors = [nil]
$game_party = AceParty.new([AceActor.new(1, 'Eric'), AceActor.new(2, 'Natalie')])
$game_player = Player.new
$game_map = MapStub.new
$game_variables = [nil, 0, 7, [1, 2]]
$game_switches = [nil, false, true]
$data_system = System.new([nil, 'Money', '', ''], [nil, 'Door', ''])

status = call('addGold', 10_000)
check(status['ready'] && status['engine'] == 'RPG Maker VX Ace' && status['gold'] == 10_000 && status['maxGold'] == 99_999_999, 'status and gold')
check(call('setGold', 50)['gold'] == 50, 'set gold')
party = call('levelUp', 10)['party']
check(party.map { |a| [a['name'], a['level'], a['mhp']] } == [['Eric', 11, 500], ['Natalie', 11, 500]], 'level up')
check(call('heal')['party'].all? { |a| a['hp'] == 100 }, 'heal')
check(call('setSpeed', 3)['speed'] == 3 && Graphics.frame_rate == 180, 'speed')
check(call('setSpeed', 1)['speed'] == 1 && Graphics.frame_rate == 60, 'speed back')
check(call('setThrough', true)['through'] && $game_player.instance_variable_get(:@through), 'through walls')
call('setThrough', false)
check($game_player.instance_variable_get(:@through) == false, 'through walls off')
call('setNoEncounters', true)
check($game_player.instance_variable_get(:@encounter_count) == 9999, 'no encounters')
call('setGod', true)
$game_party.actors.each { |a| a.hp = 3 }
Graphics.update
check($game_party.actors.all? { |a| a.hp == 500 && a.mp == 50 }, 'god mode')
check(call('items', 'item', '') == [{ 'id' => 1, 'name' => 'Potion "big"', 'count' => 0, 'max' => 99 }], 'items (named only, quotes)')
call('gainItem', 'item', 1, 10)
check(call('items', 'item', '=10').size == 1 && call('items', 'item', '#2').empty?, 'gain item and search')
check(call('variables', '').map { |v| [v['id'], v['value'], v['number']] } == [[1, 0, true], [2, 7, true], [3, '[1, 2]', false]], 'variables')
call('setVariable', 1, 42.0)
check($game_variables[1] == 42 && $game_variables[1].is_a?(Integer) && $game_map.need_refresh, 'set variable')
check(call('variables', 'money') == [{ 'id' => 1, 'name' => 'Money', 'value' => 42, 'number' => true }], 'search variables')
call('setSwitch', 1, true)
check(call('switches', '').map { |s| [s['id'], s['value']] } == [[1, true], [2, true]], 'switches')
check(call('eval', 'puts 1').nil?, 'unknown methods do nothing')
check(call('gainItem', 'item', 99, 1).key?('error'), 'errors are reported')

# XP: ids, actors, maxhp/maxsp, level=.
RPG.send(:remove_const, :BaseItem)
$data_items = [nil, Item.new(1, 'Potion')]; $data_weapons = [nil, Item.new(1, 'Sword')]; $data_armors = [nil, Item.new(1, 'Shield')]
$game_party = XPParty.new([XPActor.new(1, 'Aluxes')])
status = call('levelUp', 200)
check(status['engine'] == 'RPG Maker XP' && status['party'] == [{ 'id' => 1, 'name' => 'Aluxes', 'level' => 99, 'hp' => 300, 'mhp' => 300, 'mp' => 30, 'mmp' => 30 }], 'XP status and level (god mode still on)')
%w[item weapon armor].each { |kind| call('gainItem', kind, 1, 5) }
check(%w[item weapon armor].all? { |kind| call('items', kind, '')[0]['count'] == 5 }, 'XP items')
$game_party.actors[0].hp = 2
Graphics.update
check($game_party.actors[0].hp == 300 && $game_party.actors[0].sp == 30, 'XP god mode')
check(Graphics.frames > 0, 'Graphics.update still runs the game')
puts 'all passed'
