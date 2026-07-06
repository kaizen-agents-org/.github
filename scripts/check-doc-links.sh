#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require "pathname"

root = Pathname.new(Dir.pwd)
broken = []

Dir.glob("docs/**/*.md").sort.each do |file|
  text = File.read(file)
  text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
    target = raw_target.strip.split(/[ \t]/, 2).first.to_s
    target = target[1...-1] if target.start_with?("<") && target.end_with?(">")
    next if target.empty?
    next if target.start_with?("#")
    next if target.match?(/\A[a-z][a-z0-9+.-]*:/i)
    next if target.start_with?("//")

    path_part = target.split("#", 2).first.split("?", 2).first
    next if path_part.empty?

    resolved = (root + File.dirname(file) + path_part).cleanpath
    unless resolved.to_s.start_with?(root.to_s + File::SEPARATOR)
      broken << "#{file}:#{target} leaves repository"
      next
    end

    broken << "#{file}:#{target} missing target" unless resolved.exist?
  end
end

if broken.any?
  warn broken.join("\n")
  exit 1
end

puts "All docs Markdown links resolve."
RUBY
