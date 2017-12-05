require 'traveller_rpg'

module TravellerRPG
  class Career
    class Error < RuntimeError; end
    class UnknownAssignment < Error; end

    #
    # Actually useful defaults

    TERM_YEARS = 4
    ADVANCED_EDUCATION = 8

    #
    # Examples -- but should not be used as actual defaults

    QUALIFICATION = [:default, 5]

    PERSONAL_SKILLS = Array.new(6) { :default }
    SERVICE_SKILLS = Array.new(6) { :default }
    ADVANCED_SKILLS = Array.new(6) { :default }

    RANKS = { 0 => ['Rookie', :default, 0] }
    SPECIALIST = {
      default: {
        skills: Array.new(6) { :default },
        survival: [:default, 5],
        advancement: [:default, 5],
        ranks: RANKS,
      }
    }

    EVENTS = {
      2 => nil,
      3 => nil,
      4 => nil,
      5 => nil,
      6 => nil,
      7 => nil,
      8 => nil,
      9 => nil,
      10 => nil,
      11 => nil,
      12 => nil,
    }
    MISHAPS = {
      1 => nil,
      2 => nil,
      3 => nil,
      4 => nil,
      5 => nil,
      6 => nil,
    }

    MUSTER_OUT = {
      1 => [0, 'Default'],
      2 => [0, 'Default'],
      3 => [5, 'Default'],
      4 => [5, 'Default'],
      5 => [10, 'Default'],
      6 => [10, 'Default'],
      7 => [5000, 'Default'], # Gambler DM +1
    }

    def self.roll_check?(label, dm:, check:, roll: nil)
      roll ||= TravellerRPG.roll('2d6')
      puts format("%s check: rolled %i (DM %i) against %i",
                  label, roll, dm, check)
      (roll + dm) >= check
    end

    attr_reader :term, :status, :rank, :title, :assignment

    def initialize(char, term: 0, status: :new, rank: 0)
      @char = char

      # career tracking
      @term = term
      @status = status
      @rank = rank
      @term_mandate = nil
      @title = nil
    end

    # move status from :new to :active
    # take on an assignment
    # take any rank 0 title or skill
    #
    def activate(assignment = nil)
      raise("invalid status: #{@status}") unless @status == :new
      @status = :active
      s = self.class::SPECIALIST
      if assignment
        raise(UnknownAssignment, assignment.inspect) unless s.key?(assignment)
        @assignment = assignment
      else
        @assignment = TravellerRPG.choose("Choose a specialty:", *s.keys)
      end
      @title, skill, level = self.rank_benefit
      @char.train(skill, level) if skill
      self
    end

    def officer?
      false
    end

    def active?
      @status == :active
    end

    def finished?
      [:mishap, :finished].include? @status
    end

    def must_remain?
      @term_mandate == :must_remain
    end

    def must_exit?
      @term_mandate == :must_exit
    end

    def qualify_check?(dm: 0)
      stat, check = self.class::QUALIFICATION
      @char.log "#{self.name} qualification: #{stat} #{check}+"
      dm += @char.stats_dm(stat)
      self.class.roll_check?('Qualify', dm: dm, check: check)
    end

    def survival_check?(dm: 0)
      stat, check = self.specialty.fetch(:survival)
      @char.log "#{self.name} #{@assignment} survival: #{stat} #{check}+"
      dm += @char.stats_dm(stat)
      self.class.roll_check?('Survival', dm: dm, check: check)
    end

    def advancement_check?(dm: 0)
      stat, check = self.specialty.fetch(:advancement)
      @char.log "#{self.name} #{@assignment} advancement: #{stat} #{check}+"
      dm += @char.stats_dm(stat)
      roll = TravellerRPG.roll('2d6')
      if roll <= @term
        @term_mandate = :must_exit
      elsif roll == 12
        @term_mandate = :must_remain
      else
        @term_mandate = nil
      end
      self.class.roll_check?('Advancement', dm: dm, check: check, roll: roll)
    end

    def advanced_education?
      @char.stats[:education] >= self.class::ADVANCED_EDUCATION
    end

    # any skills obtained start at level 1
    def training_roll
      choices = [:personal, :service, :specialist]
      choices << :advanced if self.advanced_education?
      choices << :officer if self.officer?
      choice = TravellerRPG.choose("Choose skills regimen:", *choices)
      roll = TravellerRPG.roll('d6')
      @char.log "Training roll: #{roll}"
      @char.train \
              case choice
              when :personal then self.class::PERSONAL_SKILLS.fetch(roll - 1)
              when :service  then self.class::SERVICE_SKILLS.fetch(roll - 1)
              when :specialist
                self.class::SPECIALIST.dig(@assignment, :skills, roll - 1)
              when :advanced then self.class::ADVANCED_SKILLS.fetch(roll - 1)
              when :officer  then self.class::OFFICER_SKILLS.fetch(roll - 1)
              end
      self
    end

    def event_roll(dm: 0)
      roll = TravellerRPG.roll('2d6')
      clamped = (roll + dm).clamp(2, 12)
      puts "Event roll: #{roll} (DM #{dm}) = #{clamped}"
      @char.log "Event: #{self.class::EVENTS.fetch(clamped) || roll}"
      # TODO: actually perform the event stuff
    end

    def mishap_roll
      roll = TravellerRPG.roll('d6')
      puts "Mishap roll: #{roll}"
      @char.log "Mishap: #{self.class::MISHAPS.fetch(roll) || roll}"
      # TODO: actually perform the mishap stuff
    end

    def advance_rank
      @rank += 1
      @char.log "Advanced career to rank #{@rank}"
      title, skill, level = self.rank_benefit
      if title
        @char.log "Awarded rank title: #{title}"
        @title = title
      end
      if skill
        @char.log "Achieved rank skill: #{skill} #{level}"
        @char.train(skill, level)
      end
      self
    end

    def run_term
      raise(Error, "career is inactive") unless self.active?
      raise(Error, "must exit") if self.must_exit?
      @term += 1
      @char.log format("%s term %i started, age %i",
                       self.name, @term, @char.age)
      self.training_roll

      # TODO: DM?
      if self.survival_check?
        @char.log format("%s term %i completed successfully.",
                         self.name, @term)
        @char.age TERM_YEARS

        # TODO: DM?
        self.commission_roll if self.respond_to?(:commission_roll)

        # TODO: DM?
        if self.advancement_check?
          self.advance_rank
          self.training_roll
        end

        # TODO: DM?
        self.event_roll
      else
        years = rand(TERM_YEARS) + 1
        @char.log format("%s career ended with a mishap after %i years.",
                         self.name, years)
        @char.age years
        self.mishap_roll
        @status = :mishap
      end
    end

    def retirement_bonus
      @term >= 5 ? @term * 2000 : 0
    end

    def muster_roll(label)
      roll = TravellerRPG.roll('d6')
      dm = @char.skill_check?(:gambler, 1) ? 1 : 0
      puts "#{label} roll: #{roll} (DM #{dm})"
      self.class::MUSTER_OUT.fetch(roll + dm)
    end

    def muster_out(dm: 0)
      @char.log "Muster out: #{self.name}"
      raise(Error, "career has not started") unless @term > 0
      cash_rolls = @term.clamp(0, 3 - @char.cash_rolls)
      benefit_rolls = @term

      case @status
      when :active
        @char.log "Muster out: Career in good standing; collect all benefits"
      when :mishap
        @char.log "Muster out: Career ended early; lose last term benefit"
        benefit_rolls -= 1
      when :new, :finished
        raise "invalid status: #{@status}"
      else
        raise "unknown status: #{@status}"
      end

      # Collect "muster out" benefits
      cash_rolls.times { @char.cash_roll self.muster_roll('Cash').first }
      benefit_rolls.times { @char.benefit self.muster_roll('Benefit').last }
      @char.benefit self.retirement_bonus
      @status = :finished
      self
    end

    def name
      self.class.name.split('::').last
    end

    def specialty
      self.class::SPECIALIST.fetch(@assignment)
    end

    # possibly nil
    def rank_benefit
      self.specialty.fetch(:ranks)[@rank]
    end

    def report(term: true, status: true, rank: true, spec: true)
      hsh = {}
      hsh['Term'] = @term if term
      hsh['Status'] = @status if status
      hsh['Specialty'] = @assignment if spec
      hsh['Title'] = @title if @title
      if rank
        if self.officer?
          hsh['Officer Rank'] = @officer_rank
          hsh['Enlisted Rank'] = @rank
        else
          hsh['Rank'] = @rank
        end
      end
      report = ["Career: #{self.name}", "==="]
      hsh.each { |label, val|
        val = val.to_s.capitalize if val.is_a? Symbol
        report << format("%s: %s", label.to_s.rjust(15, ' '), val.to_s)
      }
      report.join("\n")
    end
  end


  #
  # MilitaryCareer adds Officer commission and parallel Officer ranks

  class MilitaryCareer < Career

    #
    # Actually useful defaults

    COMMISSION = [:social_status, 8]

    #
    # Examples -- but should not be used as actual defaults

    AGE_PENALTY = 40
    OFFICER_SKILLS = Array.new(6) { :default }
    OFFICER_RANKS = {}

    def initialize(char, **kwargs)
      super(char, **kwargs)
      @officer = false
    end

    # Implement age penalty
    def qualify_check?(dm: 0)
      dm -= 2 if @char.age >= self.class::AGE_PENALTY
      super(dm: dm)
    end

    def commission_check?(dm: 0)
      stat, check = self.class::COMMISSION
      @char.log "#{self.name} commission: #{stat} #{check}"
      dm += @char.stats_dm(stat)
      self.class.roll_check?('Commission', dm: dm, check: check)
    end

    #
    # Achieve an officer commission

    def commission_roll(dm: 0)
      return if @officer
      if TravellerRPG.choose("Apply for commission?", :yes, :no) == :yes
        if self.commission_check?
          @char.log "Became an officer!"
          @officer = 0       # officer rank
          self.advance_rank  # officers start at rank 1
        else
          @char.log "Commission was rejected"
        end
      end
    end

    #
    # Handle parallel officer track, conditional on officer commission

    def officer?
      !!@officer
    end

    def enlisted_rank
      @rank
    end

    def rank
      @officer ? @officer : @rank
    end

    def rank_benefit
      @officer ? self.class::OFFICER_RANKS[@officer] : super
    end

    def advance_rank
      return super unless @officer
      @officer += 1
      @char.log "Advanced career to officer rank #{@officer}"
      title, skill, level = self.rank_benefit
      if title
        @char.log "Awarded officer rank title: #{title}"
        @title = title
      end
      if skill
        @char.log "Achieved officer rank skill: #{skill} #{level}"
        @char.train(skill, level)
      end
    end
  end
end
