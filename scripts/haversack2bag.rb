#!/bin/sh
BINDIR="`dirname $0`/../bin"
exec $BINDIR/run_ruby "$0" "$@"
#!ruby

BINPATH=File.dirname File.expand_path __FILE__
$:.unshift File.join(BINPATH, '..', 'lib')

require 'pp'
require 'optparse'
require 'ostruct'

require 'haversackit/builder'

options = OpenStruct.new
options.output_pathname = "/quod-prep/prep/o/objectclass"
options.debug = false
option_parser = OptionParser.new do |opts|
  opts.on "--input_pathname [PATHNAME]" do |value|
    options.input_pathname = value
  end
  opts.on "--debug" do
    options.debug = true
  end
end
option_parser.parse!(ARGV)

# hashing things
builder = HaversackIt::Builder.new \
  input_pathname: options[:input_pathname],
  output_pathname: options[:output_pathname]

builder.build!

STDERR.puts "-30-"
