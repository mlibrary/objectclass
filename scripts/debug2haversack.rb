#!/bin/sh
BINDIR="`dirname $0`/../bin"
exec $BINDIR/run_ruby "$0" "$@"
#!ruby

BINPATH=File.dirname File.expand_path __FILE__
$:.unshift File.join(BINPATH, '..', 'lib')

require 'haversackit/haversack/text_class'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.output_pathname = "/quod-prep/prep/o/objectclass/.haversack"
options.debug = false
options.parts = { 1=> "Title", 2=>"Volume"}
options.symlink = true
option_parser = OptionParser.new do |opts|
  opts.on "--collid [COLLID]" do |value|
    options.collid = value
  end
  opts.on "--idno [IDNO]" do |value|
    options.idno = value
  end
  opts.on "--output_pathname [PATHNAME]" do |value|
    if value == ':local'
      value = "#{ENV['DLXSROOT']}/prep/o/objectclass/.haversack"
    end
    options.output_pathname = value
  end
  opts.on "--part.1 [VALUE]" do |value|
    options.parts[1] = value
  end
  opts.on "--part.2 [VALUE]" do |value|
    options.parts[2] = value
  end
  opts.on "--debug" do
    options.debug = true
  end
  opts.on "--no-symlink" do
    options.symlink = false
  end
end
option_parser.parse!(ARGV)

prep = HaversackIt::Haversack::TextClass.new(
  collid: options[:collid],
  idno: options[:idno],
  parts: options[:parts],
  symlink: options[:symlink])
prep.build
prep.save!(options[:output_pathname])

STDERR.puts "-30-"
