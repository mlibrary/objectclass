#!/bin/sh
BINDIR="`dirname $0`/../bin"
exec $BINDIR/run_ruby "$0" "$@"
#!ruby

BINPATH=File.dirname File.expand_path __FILE__
$:.unshift File.join(BINPATH, '..', 'lib')

require 'haversackit/haversack/textclass'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.output_pathname = '/quod-prep/prep/o/objectclass/.haversack'
options.debug = false
option_parser = OptionParser.new do |opts|
  opts.on "--collid [COLLID]" do |value|
    options.collid = value
  end
  opts.on "--idno [IDNO]" do |value|
    options.idno = value
  end
  opts.on "--output_pathname [PATHNAME]" do |value|
    options.output_pathname = value
  end
  opts.on "--debug" do
  	options.debug = true
  end
end
option_parser.parse!(ARGV)

prep = HaversackIt::Haversack::TextClass.new(collid: options[:collid], idno: options[:idno])
prep.build
prep.save!(options[:output_pathname])

STDERR.puts "-30-"
