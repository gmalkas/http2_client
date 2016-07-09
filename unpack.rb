#!/usr/bin/env ruby

require "http/2"
require "pp"
require "pry"

buffer = HTTP2::Buffer.new([ARGV.first].pack("H*"))
pp HTTP2::Framer.new.parse(buffer)
binding.pry
