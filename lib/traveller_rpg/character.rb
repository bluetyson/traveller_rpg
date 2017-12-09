require 'traveller_rpg'
require 'traveller_rpg/homeworld'
require 'traveller_rpg/skill_set'

module TravellerRPG
  class Character
    Stats = Struct.new(:strength, :dexterity, :endurance,
                       :intelligence, :education, :social_status) do
      def self.roll
        self.new(*Array.new(6) { TravellerRPG.roll '2d6' })
      end

      def self.empty
        self.new(*Array.new(6) { 0 })
      end

      def boost(hsh)
        hsh.each { |k,v| self[k] += v if self[k] }
        self
      end

      def bump(sym, level = nil)
        if level
          self[sym] = level if level > self[sym]
        else
          self[sym] += 1
        end
      end

      def report
        rpt = []
        w = 'Social Status'.size + 2
        self.members.each { |sym|
          rpt << format("%s: %s", sym.to_s.capitalize.rjust(w, ' '), self[sym])
        }
        rpt.join("\n")
      end
    end

    Description = Struct.new(:name, :gender, :age,
                             :appearance, :plot, :temperament) do
      def merge(other)
        self.class.new(other[:name]        || self.name,
                       other[:gender]      || self.gender,
                       other[:age]         || self.age,
                       other[:appearance]  || self.appearance,
                       other[:plot]        || self.plot,
                       other[:temperament] || self.temperament)
      end

      def report(short: false)
        rpt = []
        w = (short ? 'Gender' : 'Temperament').size + 2
        self.members.each { |sym|
          next if short and [:appearance, :plot, :temperament].include?(sym)
          rpt << format("%s: %s", sym.to_s.capitalize.rjust(w, ' '), self[sym])
        }
        rpt.join("\n")
      end
    end

    def self.stats_dm(stat_val)
      case stat_val
      when 0 then -3
      when 1..2 then -2
      when 3..5 then -1
      when 6..8 then 0
      when 9..11 then 1
      when 12..14 then 2
      when 15..20 then 3
      else
        raise "unexpected stat: #{stat_val} (#{stat_val.class})"
      end
    end

    attr_reader :desc, :stats, :skills, :stuff, :credits, :cash_rolls

    def initialize(desc:, stats:, skills: SkillSet.new, stuff: {},
                   log: [], credits: 0, cash_rolls: 0, homeworld: nil)
      @desc = desc
      @stats = stats
      @skills = skills
      @stuff = stuff
      @log = log
      @credits = credits
      @cash_rolls = cash_rolls # max 3 lifetime
      birth(homeworld) if homeworld
    end

    def stats_dm(stat_sym)
      self.class.stats_dm(@stats[stat_sym])
    end

    # accepts an array of strings or a single string
    # choose from the array; provide a single skill
    # return nil if no skill was trained
    def basic_training(skill, label: nil)
      if skill.is_a?(Array)
        skill = SkillSet.choose(skill.reject { |s| @skills[s] },
                                label: 'basic training') or return
      end
      unless @skills[skill]
        self.log "Basic Training: #{skill} 0"
        @skills.provide skill
      end
    end

    def benefit(item)
      if item.is_a?(Integer)
        if item != 0
          @credits += item
          self.log "Career benefit: #{item} credits"
        end
      elsif item.is_a?(String)
        @stuff[item] ||= 0
        @stuff[item] += 1
        self.log "Career benefit: #{item}"
      elsif item.is_a?(Array)
        self.benefit TravellerRPG.choose("Choose benefit:", *item)
      else
        raise "unexpected benefit: #{benefit.inspect}"
      end
    end

    def log(msg = nil)
      return @log unless msg
      puts msg
      @log << msg
      self
    end

    # convenience
    def name
      @desc.name
    end

    def age(years = nil)
      years ? @desc.age += years : @desc.age
    end

    def cash_roll(amount)
      @cash_rolls += 1
      if @cash_rolls <= 3
        @credits += amount
        self.log "Cash roll ##{@cash_rolls}: #{amount} credits"
      else
        self.log "Cash roll ##{@cash_rolls}: Ignored"
      end
      self
    end

    def report(desc: :short, stats: true, skills: true, stuff: true,
               log: false, credits: true)
      hsh = {}
      hsh['Description'] = @desc.report(short: desc == :short) if desc
      hsh['Characteristics'] = @stats.report if stats
      hsh['Skills'] = @skills.report if skills
      hsh['Stuff'] = @stuff if stuff
      hsh['Log'] = @log if log
      if credits
        hsh['Credits'] = {
          'Total' => @credits,
          'Cash Rolls' => @cash_rolls,
        }
      end
      report = []
      hsh.each { |section, tbl|
        report << "#{section}\n==="
        if tbl.empty?
          report << "(none)"
        elsif tbl.is_a?(Hash)
          width = tbl.keys.map(&:size).max + 2
          tbl.each { |k, v|
            report << format("%s: %s", k.to_s.rjust(width, ' '), v)
          }
        elsif tbl.is_a?(Array)
          report += tbl
        else
          report << tbl
        end
        report << ' '
      }
      report.join("\n")
    end

    private

    # gain background skills based on homeworld
    def birth(homeworld)
      raise "log should be empty" unless @log.empty?
      skill_count = 3 + self.stats_dm(:education)
      self.log format("%s was born on %s (%s)",
                      @desc.name,
                      homeworld.name,
                      homeworld.traits.join(' '))
      self.log format("Education %i provides up to %i background skills",
                      @stats.education, skill_count)
      homeworld.choose_skills(skill_count).each { |skill|
        self.log "Background skill: #{skill} 0"
        @skills.provide skill
      }
    end
  end
end
