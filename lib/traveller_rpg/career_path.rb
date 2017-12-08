require 'traveller_rpg'
require 'traveller_rpg/character'
require 'traveller_rpg/careers'
require 'traveller_rpg/skill'

module TravellerRPG
  class CareerPath
    class Ineligible < RuntimeError; end

    DRAFT_CAREERS = {
      1 => ['Navy'],
      2 => ['Army'],
      3 => ['Marines'],
      # TODO: define Merchant career
      # 4 => ['Merchant', 'Merchant Marine'],
      4 => ['Marines'],
      5 => ['Scout'],
      6 => ['Agent', 'Law Enforcement'],
    }

    def self.career_class(str)
      TravellerRPG.const_get(str.split('::').last)
    end

    def self.draft_career?(str)
      DRAFT_CAREERS.values.map(&:first).include? str
    end

    def self.run(careers, character:)
      puts "\n", character.report(desc: :long, stuff: false, credits: false)
      path = self.new(character)
      loop {
        careers = careers.select { |c| path.eligible? c }
        break if careers.empty?
        career = TravellerRPG.choose("Choose a career:", *careers)
        path.run(career)
        puts "\n", path.report, "\n"
        break if TravellerRPG.choose("Exit career mode?", :yes, :no) == :yes
      }
      puts
      puts character.log.join("\n")
      path
    end

    attr_reader :char, :careers

    def initialize(character)
      @char = character
      @char.log "Initiated new career path"
      @careers = []
    end

    def career(career_name)
      self.class.career_class(career_name).new(@char)
    end

    def finished
      @careers
    end
    alias_method :completed, :finished

    def eligible?(career)
      case career
      when Career
        return false if career.status != :new or career.term != 0
        cls = career.class
      when String
        cls = CareerPath.career_class(career)
      end
      cls == TravellerRPG::Drifter or !@careers.any? { |c| cls === c }
    end

    # Run career to completion; keep running terms while possible
    def run(career, asg = nil)
      run! self.apply career, asg
    end

    # Pass eligibility and qualify_check
    # Take Drifter or Draft if disqualified
    # Then enter career
    def apply(career, asg = nil)
      career = self.career(career) if career.is_a? String
      raise(Ineligible, career.name) unless self.eligible?(career)
      if career.qualify_check?(dm: -1 * @careers.size)
        @char.log "Qualified for #{career.name}"
        self.enter(career, asg)
      else
        @char.log "Did not qualify for #{career.name}"
        case TravellerRPG.choose("Choose fallback:", 'Drifter', 'Draft')
        when 'Drifter' then self.enter TravellerRPG::Drifter.new(@char), asg
        when 'Draft'   then self.draft
        end
      end
    end

    def enter(career, asg = nil)
      raise(Ineligible, career.name) unless self.eligible?(career)
      @char.log "Entering new career: #{career.name}"
      enter! career, asg
    end

    # return an active career, no qualification check, that has completed basic
    # training
    def draft
      roll = TravellerRPG.roll('d6', label: "Draft")
      career, asg = self.class::DRAFT_CAREERS.fetch(roll)
      @char.log "Drafted: #{[career, asg].compact.join(', ')}"
      enter! self.career(career), asg
    end

    def basic_training(career)
      return career unless career.term.zero?
      if @careers.length > 0
        skills = career.class::SERVICE_SKILLS.flatten.reject { |s|
          @char.skills[s]
        }
        return career if skills.empty?
        skills = [TravellerRPG.choose("Choose service skill:", *skills)]
      else
        # Take "all" SERVICE_SKILLS, but choose any choices
        skills = []
        career.class::SERVICE_SKILLS.each { |skill|
          if skill.is_a?(Array)
            skill = skill.reject { |s| @char.skills[s] }
            case skill.size
            when 0
              return career
            when 1
              skills << skill.first
            else
              skills << TravellerRPG.choose("Choose service skill:", *skill)
            end
          else
            skills << skill unless @char.skills[skill]
          end
        }
      end
      skills.each { |skill|
        @char.skills.provide(skill)
        @char.log "Acquired basic training skill: #{skill}"
      }
      career
    end

    def report(char: true, careers: true)
      [@char.report, @careers.map(&:report).join("\n\n")].join("\n\n")
    end

    private

    # activate a new career, with basic training
    def enter!(career, asg = nil)
      self.basic_training(career.activate(asg))
    end

    # take an active career and run_term until complete
    # muster_out and update career history
    def run!(career)
      raise(Error, "#{career.name} isn't active") unless career.active?
      loop {
        career.run_term
        break unless career.active?
        break if career.must_exit?
        next if career.must_remain?
        break if TravellerRPG.choose("Muster out?", :yes, :no) == :yes
      }
      career.muster_out
      @careers << career
      career
    end
  end
end
