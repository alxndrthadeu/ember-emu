#!/usr/bin/env ruby
# Packs demo/scripts/*.rb into a VX Ace game folder at demo/game:
# Game.ini and Data/Scripts.rvdata2 (Marshal of [id, name, deflated
# code], the format RPG Maker VX Ace writes). The game draws all its
# art in code, so these two files are the whole game.
#
# Usage: ruby scripts/build-demo.rb
require 'zlib'
require 'fileutils'

root = File.expand_path('..', __dir__)
sources = Dir[File.join(root, 'demo/scripts/*.rb')].sort
out = File.join(root, 'demo/game')
FileUtils.rm_rf(out)
FileUtils.mkdir_p(File.join(out, 'Data'))

scripts = sources.each_with_index.map do |path, i|
  code = File.read(path, encoding: 'UTF-8')
  name = File.basename(path, '.rb').sub(/^\d+_/, '')
  [1000 + i, name.dup.force_encoding('UTF-8'), Zlib::Deflate.deflate(code)]
end
File.binwrite(File.join(out, 'Data/Scripts.rvdata2'), Marshal.dump(scripts))

File.write(File.join(out, 'Game.ini'), <<~INI)
  [Game]
  Library=System\\RGSS301.dll
  Scripts=Data\\Scripts.rvdata2
  Title=A Última Brasa
INI
puts "demo: #{sources.size} scripts -> #{out}"
