# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "daily_validator/version"

Gem::Specification.new do |s|
  s.name        = "daily_validator"
  s.version     = DailyValidator::VERSION
  s.authors     = ["Tomas Svarovsky"]
  s.email       = ["svarovsky.tomas@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "daily_validator"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "rspec"
  s.add_runtime_dependency "tztime"
  s.add_runtime_dependency "pry"
  s.add_runtime_dependency "active_support"
  s.add_runtime_dependency "google-spreadsheet-ruby"
  s.add_runtime_dependency "gooddata"
  s.add_runtime_dependency "fsdb"
  s.add_runtime_dependency "eventmachine"
end
