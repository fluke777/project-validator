require 'daily_validator'

describe 'working hours' do

  before :each do
    @projects = ['pid1', 'pid2']
    @working_hours = {
      
      'pid1' => '8:00 - 10:00',
      'pid2' => '22:00 - 02:00',
      'pid3' => '22:00 - 02:00'
    }
    Time.zone = 'CET'
    @db = {
      'pid1' => 1293836400.to_s,
      # Time.zone.local(2011, 1, 10).utc.to_i,
      'pid2' => 1293836401.to_s
      # Time.zone.local(2011, 1, 1).utc.to_i
    }
  end

  it "should be outside of working hours" do
    pid = @projects.first
    now = Time.zone.local(2011, 1, 11, 11, 30)
    DailyValidator.is_outside_working_hours?(now, @working_hours[pid]).should == false
  end
  
  it "should be inside of working hours" do
    pid = @projects.first
    now = Time.zone.local(2011, 1, 11, 9, 30)
    DailyValidator.is_outside_working_hours?(now, @working_hours[pid]).should == true
  end
  
  it "should be outside of working hours even when they work over midnight" do
    pid = @projects[1]
    now = Time.zone.local(2011, 1, 11, 11, 30)
    DailyValidator.is_outside_working_hours?(now, @working_hours[pid]).should == false
  end
  
  it "should be inside of working hours even when they work over midnight" do
    pid = @projects[1]
    now = Time.zone.local(2011, 1, 11, 23, 30)
    DailyValidator.is_outside_working_hours?(now, @working_hours[pid]).should == true
  end
  
  it "should have run in previous week" do
    now = Date.new(2011, 1, 4)
    back_then = Date.new(2011, 1, 1)
    DailyValidator.run_in_last_week?(now, back_then).should == true
  end
  
  it "ran way in the past" do
    now = Date.new(2010, 1, 4)
    back_then = Date.new(2011, 1, 1)
    DailyValidator.run_in_last_week?(now, back_then).should == false
  end
  
  it "ran way in the future" do
    now = Date.new(2012, 1, 4)
    back_then = Date.new(2011, 1, 1)
    DailyValidator.run_in_last_week?(now, back_then).should == false
  end
  
  it "should find next" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    DailyValidator.find_next(@projects, @db, now, @working_hours).should == 'pid2'
  end
  
  it "should find next even if it was not validated before" do
    projects = ["pid1", "pid3"]
    now = Time.zone.local(2011, 1, 14, 23, 0)
    DailyValidator.find_next(projects, @db, now, @working_hours).should == 'pid3'
  end
  
  it "should throw if there are no workign hours for a project" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    lambda { DailyValidator.find_next(@projects, @db, now, {}) }.should raise_error
  end

  it "Should fail even when the project was not validated before" do
    projects = ["pid1", "pid3"]
    now = Time.zone.local(2011, 1, 14, 23, 0)
    lambda { DailyValidator.find_next(projects, {}, now, {}) }.should raise_error
  end

  it "should parse correct working hour representation" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    d1 = Time.zone.local(2011, 1, 14, 8, 0)
    d2 = Time.zone.local(2011, 1, 14, 10, 0)
    DailyValidator.parse_working_hours(now, '8:00 - 10:00').should == (d1..d2)
  end

  it "should parse correct working hour representation over midnight" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    d1 = Time.zone.local(2011, 1, 14, 8, 0)
    d2 = Time.zone.local(2011, 1, 15, 6, 0)
    DailyValidator.parse_working_hours(now, '8:00 - 6:00').should == (d1..d2)
  end

  it "should throw error when parsing incorrect working hour representation over midnight" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    lambda { DailyValidator.parse_working_hours(now, '8:000 - 6:00') }.should raise_error
  end

  it "should store and load time in utc but we should not need to care" do
    now = Time.zone.local(2011, 1, 14, 23, 0)
    pid = '12312'
    DailyValidator.store_time_to_db(pid, @db, now)
    now_2 = DailyValidator.read_time_from_db(pid, @db)
    now.should == now_2
    now.zone.should == now_2.zone
    now.zone.should == DailyValidator::LOCAL_ZONE
  end

end