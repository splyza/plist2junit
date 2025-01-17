#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 Foobar.xcresult"
  exit 1
end

$xcresult = ARGV[0]

def get_object id
  result = nil
  IO.popen(%w{xcrun xcresulttool get --format json --path} << $xcresult << '--id' << id) do |object|
    result = JSON.load object
  end
  result
end

# get test result id from xcresults
results = nil
IO.popen(%w{xcrun xcresulttool get --format json --path} << $xcresult) do |result_summary|
  results = JSON.load result_summary
end

# load test results by id
testsRef = results['actions']['_values'][0]['actionResult']['testsRef']['id']['_value']
tests = get_object testsRef

# transform to a dictionary that mimics the output structure

test_suites = []

tests['summaries']['_values'][0]['testableSummaries']['_values'].each do |target|
  target_name = target['targetName']['_value']
  test_classes = target['tests']['_values']

  # if the test target failed to launch at all
  # FIXME: where are failuresummaries kept now?
  if test_classes.empty?
    test_suites << {name: target_name, error: "No tests found in target"}
    next
  end

  # else process the test classes in each target
  # first two levels are just summaries, so skip those
  test_classes[0]['subtests']['_values'][0]['subtests']['_values'].each do |test_class|
    suite = {name: "#{target_name}.#{test_class['name']['_value']}", cases: []}

    # process the tests in each test class
    test_class['subtests']['_values'].each do |test|
      duration = 0
      if test['duration']
        duration = test['duration']['_value']
      end

      testcase = {name: test['name']['_value'], time: duration}

      if test['testStatus']['_value'] == 'Failure'
        failure = get_object(test['summaryRef']['id']['_value'])['failureSummaries']['_values'][0]

        filename = failure['fileName']['_value']
        message = failure['message']['_value']

        if filename == '<unknown>'
          testcase[:error] = message
        else
          testcase[:failure] = message
          testcase[:failure_location] = "#{filename}:#{failure['lineNumber']['_value']}"
        end
      end

      suite[:cases] << testcase
    end

    suite[:count] = suite[:cases].size
    suite[:failures] = suite[:cases].count { |testcase| testcase[:failure] }
    suite[:errors] = suite[:cases].count { |testcase| testcase[:error] }
    test_suites << suite
  end
end

# format the data

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites>"
test_suites.each do |suite|
  if suite[:error]
    puts "<testsuite name=#{suite[:name].encode xml: :attr} errors='1'>"
    puts "<error>#{suite[:error].encode xml: :text}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name=#{suite[:name].encode xml: :attr} tests='#{suite[:count]}' failures='#{suite[:failures]}' errors='#{suite[:errors]}'>"

    suite[:cases].each do |testcase|
      print "<testcase classname=#{suite[:name].encode xml: :attr} name=#{testcase[:name].encode xml: :attr} time='#{testcase[:time]}'"
      if testcase[:failure]
        puts '>'
        puts "<failure message=#{testcase[:failure].encode xml: :attr}>#{testcase[:failure_location].encode xml: :text}</failure>"
        puts '</testcase>'
      elsif testcase[:error]
        puts '>'
        puts "<error>#{testcase[:error].encode xml: :text}</error>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
