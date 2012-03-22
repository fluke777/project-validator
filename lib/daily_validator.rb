require 'rubygems'
require 'bundler/setup'
require 'google_spreadsheet'
require 'daily_validator/version'
require 'active_support/time'
require 'pry'
require 'gooddata'
require 'fsdb'
require 'eventmachine'
require 'gd'

module DailyValidator

  HOSTNAME = `hostname`.chomp
  LOCAL_ZONE = 'CET'


  class WorkingHoursNotDefined < Exception
    attr_accessor :pid
    def initialize(message, pid)
      super(message)
      @pid = pid
    end
  end

  def self.is_outside_working_hours?(now, working_hours)
    working_hours = parse_working_hours(now, working_hours)
    working_hours.include? now
  end

  def self.run_in_last_week?(now, back_then)
    now.advance(:days => -7) < back_then && now > back_then
  end
  
  def self.get_projects_from_gd
    GoodData.connect('login', 'pass')
    GoodData.get(user_uri)
  end

  def self.get_project_names(projects)
    project_names = {}
    projects['projects'].each do |project|
      pid = project['project']['links']['self'].split('/').last
      project_names[pid] = project['project']['meta']['title']
    end
    project_names
  end

  def self.blame
    puts "Grabbing sheet"
    sheet_projects = get_projects_from_sheet
    sheet_pids = sheet_projects.map {|project| project[:pid]}

    puts "Grabbing projects"
    gd_projects = get_projects_from_gd
    gd_pids = gd_projects['projects'].map {|p| p['project']['links']['self'].split('/').last}

    puts "User NOT INVITED into projects mentioned in sheet"
    pids = sheet_pids - gd_pids
    pp pids.map {|pid| x = sheet_projects.detect {|project| project[:pid] == pid}; "#{x[:pid]} - #{x[:customer]} - #{x[:project]} (#{x[:ms_rep]})"}
  end

  def self.get_projects_from_sheet
    session = GoogleSpreadsheet.login("login", "pass")
    s = session.spreadsheet_by_key 'key'
    ws = s.worksheets.first
    
    headers = ws.rows.first
    indexes = {}
    
    headers.each do |header|
      indexes[header] = headers.index(header)
    end
    live_without_pid = []    
    sheet_projects = ws.rows[1..ws.num_rows].reduce([]) do |memo, row|
      project = {
        :customer       => row[indexes['Customer']],
        :project        => row[indexes['Project']],
        :pid            => row[indexes['Project pid']],
        :status         => row[indexes['Status']],
        :ms_rep         => row[indexes['MS Person']],
        :working_hours  => row[indexes['Working Hours']]
      }
      
      live_without_pid << project if project[:status] == 'Live' && project[:pid].empty?
      memo << project if !project[:pid].empty? && project[:status] == 'Live'
      memo
    end
  end

  def self.get_working_hours
    projects = get_projects_from_sheet
    working_hours = {}
    projects.each do |project|
      working_hours[project[:pid]] = parse_working_hours(project[:working_hours])
    end
    working_hours
  end
    
  def self.find_next(projects, db, now, working_hours)
    projects.find do |pid|
      last_run = Time.zone.at(db[pid].to_i)
      project_working_hours = working_hours[pid]
      
      if last_run.nil?
        fail WorkingHoursNotDefined.new("Working hours not defined for project #{pid}", pid) if project_working_hours.nil? || project_working_hours.empty?
        true
      else
        if run_in_last_week?(now, last_run) then
          false
        else
          fail WorkingHoursNotDefined.new("Working hours not defined for project #{pid}", pid) if (project_working_hours.nil? || project_working_hours.empty?) && !ran
          ran = run_in_last_week?(now, last_run)
          can_run_now = is_outside_working_hours?(now, project_working_hours)
          !ran && can_run_now
        end
      end
    end
  end

  def find_project_name(pid, projects)
    projects
  end

  def self.parse_working_hours(now, working_hours)
    # fail "Incorrect format" if working_hours !=~ /%d{1,2}:%d%d - %d{1,2}:%d%d/
    fragments = working_hours.split('-')
    from  = fragments[0].strip
    from_hour = from.split(":")[0]
    from_min = from.split(":")[1]

    to    = fragments[1].strip
    to_hour = to.split(":")[0]
    to_min = to.split(":")[1]

    now = now.time
    from_time = Time.zone.local(now.year, now.month, now.day, from_hour, from_min)
    to_time = Time.zone.local(now.year, now.month, now.day, to_hour, to_min)
    to_time = to_time.advance(:days => 1) if from_time > to_time
    
    (from_time..to_time)
  end

  def self.store_time_to_db(pid, db, time_in_local)
    # everything should be in local timezone and that is CET
    # prague office is in CET, info in spreadsheet is in CET
    # in the db though it should be stored in UTC
    db[pid] = time_in_local.utc.to_i.to_s
  end

  def self.read_time_from_db(pid, db)
    # everything should be in local timezone and that is CET
    # prague office is in CET, info in spreadsheet is in CET
    # in the db though it should be stored in UTC
    Time.zone.at(db[pid].to_i)
  end

  def self.run

    gd_projects = get_projects_from_gd
    gd_pids = gd_projects['projects'].map {|p| p['project']['links']['self'].split('/').last}
    Time.zone = LOCAL_ZONE
    # builder = TZTime::LocalTime::Builder.new('CET')
    working_hours = self.get_working_hours

    project_names = get_project_names(gd_projects)

    # WARN: Enable FSBD
    db = FSDB::Database.new('./db')
    EM.run do
      EM.add_periodic_timer(600) do
        puts "update_working_hours"
        working_hours = self.get_working_hours
        pp working_hours
      end
      
      EM.add_periodic_timer(600) do
        puts "update_projects"
        gd_projects = get_projects_from_gd
        gd_pids = gd_projects['projects'].map {|p| p['project']['links']['self'].split('/').last}
        project_names = get_project_names(gd_projects)
      end

      EM.add_periodic_timer(10) do
        puts "validating"

        begin
          now = Time.zone.now
          pid = find_next(gd_pids, db, now, working_hours)
        rescue WorkingHoursNotDefined => e
          pp e.inspect
          store_time_to_db(e.pid, db, now)
          retry
        end
        if pid
          puts "Would Validate #{pid} and set time of validation to #{now.to_s}"
          store_time_to_db(pid, db, now)
          result, description = Gd::Commands.validate_project(pid)
          
          # Is splunk logging hapenning in utc or local
          now = Time.now.utc
          message = %Q|#{now.to_s} #{HOSTNAME} logger: run_id="#{pid}.#{now.strftime('%s')}" type="ref-integrity-validation" task_name="#{project_names[pid]}" action="validation" status="#{result ? "end" : "error"}" eventdate="#{now.strftime('%Y-%m-%d %H:%M:%S')}"|
          # File.open('/mnt/log/gdc-clover', 'a') do |f|
          File.open('.aaaaa', 'a') do |f|
            f.write message
          end
        end
      end
    end
  end
end