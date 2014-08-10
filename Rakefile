desc "pry"
task :console do
  ARGV.shift()
  ENV['RUBYLIB'] ||= ''
  ENV['RUBYLIB'] += ":#{File.expand_path('.')}/lib"
  exec "pry -I. -r hexbug_parser -r irtoy -r hexbug"
end

task :irb => :console
task :pry => :console
