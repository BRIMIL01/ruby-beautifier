require 'rake/testtask'

$:.unshift "lib"

task :default => :test

desc "Run tests"
Rake::TestTask.new do |t|
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end

desc "rebuild parser"
task :parser do
  sh "kpeg -o lib/ruby-beautifier/beautifier.rb -s -f lib/ruby-beautifier/beautifier.kpeg"
end

