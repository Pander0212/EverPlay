# Runs App/Resources/EverPlayRGSS.rb against small stand-ins for VX Ace and XP: ruby tests/rgss-cheats-test.rb
require 'tmpdir'
ENV['TMPDIR'] = Dir.mktmpdir
module Graphics
  @frames = 0
  def self.update; @frames += 1; end
  def self.frames; @frames; end
end
load File.expand_path('../App/Resources/EverPlayRGSS.rb', __dir__)
Dir.mkdir(EverPlayCheats::DIR)

Item = Struct.new(:id, :name)
class Actor
  attr_accessor :hp, :mp, :sp, :level
  def initialize; @hp = 1; @mp = 1; @level = 1; end
  def recover_all; @hp = 100; end
end
class AceActor < Actor
  def mhp; 500; end
  def mmp; 50; end
  def max_level; 99; end
  def change_level(level, _show); @level = level; end
end
class XPActor < Actor
  def maxhp; 300; end
  def maxsp; 30; end
end
class Party
  attr_reader :gold, :items, :actors
  def initialize(actors); @gold = 0; @items = Hash.new(0); @actors = actors; end
  def gain_gold(n); @gold += n; end
end
class AceParty < Party
  def all_members; actors; end
  def gain_item(item, n); @items[item.name] += n; end
end
class XPParty < Party
  def gain_item(id, n); @items["i#{id}"] += n; end
  def gain_weapon(id, n); @items["w#{id}"] += n; end
  def gain_armor(id, n); @items["a#{id}"] += n; end
end
class Player; end
class MapStub; attr_accessor :need_refresh; end
System = Struct.new(:variables, :switches)

def command(text) = File.open(EverPlayCheats::COMMAND, 'a') { |f| f.puts(text) }
def frames(n) = n.times { Graphics.update }
def check(ok, what) = (puts((ok ? 'ok   ' : 'FAIL ') + what); exit 1 unless ok)

# VX Ace: item objects, all_members, mhp/mmp.
module RPG; class BaseItem; end; end
$data_items = [nil, Item.new(1, 'Potion'), Item.new(2, '')]
$data_weapons = [nil, Item.new(1, 'Sword')]
$data_armors = [nil]
$game_party = AceParty.new([AceActor.new, AceActor.new])
$game_player = Player.new
$game_map = MapStub.new
$game_variables = [nil, 0, 7]
$game_switches = [nil, false, true]
$data_system = System.new([nil, 'Money', ''], [nil, 'Door', ''])

command('gold 10000'); command('items 10'); command('level'); command('flag god on'); command('flag through on')
command('variable 1 42'); command('switch 1 on'); command('report')
frames(12)
check(Graphics.frames == 12, 'Graphics.update still runs the game')
check($game_party.gold == 10000, 'gold')
check($game_party.items == { 'Potion' => 10, 'Sword' => 10 }, 'items (named only)')
check($game_party.actors.all? { |a| a.level == 99 && a.hp == 500 && a.mp == 50 }, 'level and god mode')
check($game_player.instance_variable_get(:@through) == true, 'through walls')
check($game_variables[1] == 42 && $game_switches[1] == true && $game_map.need_refresh, 'variable and switch')
report = File.read(EverPlayCheats::REPORT)
check(report.include?("gold\t10000") && report.include?("variable\t1\tMoney\t42") && report.include?("variable\t2\t\t7") &&
      report.include?("switch\t1\tDoor\ton") && report.include?("switch\t2\t\ton"), 'report')
check(!File.exist?(EverPlayCheats::COMMAND), 'commands consumed')

command('flag god off'); command('bogus `rm -rf /`'); frames(6)
$game_party.actors.each { |a| a.hp = 3 }; frames(6)
check($game_party.actors.all? { |a| a.hp == 3 }, 'god mode off; unknown commands ignored')

# XP: ids, actors, maxhp/maxsp, level=.
RPG.send(:remove_const, :BaseItem)
$data_items = [nil, Item.new(1, 'Potion')]; $data_weapons = [nil, Item.new(1, 'Sword')]; $data_armors = [nil, Item.new(1, 'Shield')]
$game_party = XPParty.new([XPActor.new])
command('items 5'); command('level'); command('flag god on'); command('flag noencounter on'); frames(6)
check($game_party.items == { 'i1' => 5, 'w1' => 5, 'a1' => 5 }, 'XP items')
check($game_party.actors[0].level == 99 && $game_party.actors[0].hp == 300 && $game_party.actors[0].sp == 30, 'XP level and god mode')
check($game_player.instance_variable_get(:@encounter_count) == 9999, 'no encounters')
command('flag through off'); frames(6)
check($game_player.instance_variable_get(:@through) == false, 'through walls off')
puts 'all passed'
