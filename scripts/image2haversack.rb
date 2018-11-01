#!/bin/sh
BINDIR="`dirname $0`/../bin"
exec $BINDIR/run_ruby "$0" "$@"
#!ruby

BINPATH=File.dirname File.expand_path __FILE__
$:.unshift File.join(BINPATH, '..', 'lib')

require 'haversackit/haversack/image_class'
require 'optparse'
require 'ostruct'

require 'pp'

options = OpenStruct.new
options.m_id = []
options.output_pathname = '/quod-prep/prep/o/objectclass/.haversack'
options.debug = false
option_parser = OptionParser.new do |opts|
  opts.on "--collid [COLLID]" do |value|
    options.collid = value
  end
  opts.on "--m_id [M_ID]" do |value|
    options.m_id << value
  end
  opts.on "--output_pathname [PATHNAME]" do |value|
    options.output_pathname = value
  end
  opts.on "--debug" do
    options.debug = true
  end
end
option_parser.parse!(ARGV)

prep = HaversackIt::Batch::ImageClass.create(collid: options.collid, m_id: options.m_id)
prep.build
prep.save!(options[:output_pathname])

STDERR.puts "-30-"
