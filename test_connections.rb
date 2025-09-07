#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing database connection..."
begin
  ActiveRecord::Base.connection
  puts "✅ Database connected successfully"
  
  # Test table existence
  puts "Tables: #{ActiveRecord::Base.connection.tables}"
  
rescue => e
  puts "❌ Database connection failed: #{e.message}"
end

puts "\nTesting Redis connection..."
begin
  redis = Redis.new(host: 'localhost', port: 6379, db: 0)
  result = redis.ping
  puts "✅ Redis connected successfully: #{result}"
  
  # Test Redis operations
  redis.set("test_key", "test_value")
  value = redis.get("test_key")
  puts "✅ Redis read/write test: #{value}"
  redis.del("test_key")
  
rescue => e
  puts "❌ Redis connection failed: #{e.message}"
end

puts "\nTesting Python module..."
begin
  sentence = "running worked better"
  python_command = "cd #{Rails.root} && source venv/bin/activate && python lib/word.py \"#{sentence}\""
  result = `#{python_command}`
  parsed_result = JSON.parse(result)
  puts "✅ Python module test successful:"
  parsed_result.each { |word| puts "  #{word['word']} -> #{word['root']} (#{word['pos']})" }
rescue => e
  puts "❌ Python module test failed: #{e.message}"
  puts "Raw output: #{result}"
end