#!/usr/bin/env ruby
# encoding: utf-8

require "rubygems"
require "net/irc"

Infinity = 1.0/0

class Method
  def arity_range
    p = parameters
    req = p.select { |a| a[0] == :req }.count
    opt = p.select { |a| a[0] == :opt }.count
    rest = p.select { |a| a[0] == :rest }.count

    if rest > 0
      opt = Infinity
    else
      opt = req + opt
    end

    (req..opt)
  end
end

class DB
  def initialize dir
    @dir = dir
  end

  def sanitize a
    a.gsub("/", "⁄").gsub("\0", "°")
  end

  def [] *a
    a = a.map{|i| i.to_s}.join("::")
    begin
      File.open(@dir+sanitize(a)+".m") do |f|
        Marshal.load(f)
      end
    rescue Exception
      nil
    end
  end

  def []= *a, b
    a = a.map{|i| i.to_s}.join("::")
    File.open(@dir+sanitize(a)+".m", "w") do |f|
      Marshal.dump(b, f)
    end
  end
end

class VichanBot < Net::IRC::Client
  def initialize(*args)
    super

    @methods = Ops.instance_methods false
    @db = DB.new("data/")
  end

  def on_rpl_welcome(m)
    super
    post JOIN, "#vichan,#karachan,#karachan-meta,#vichan-devel,#radiocp"
  end

  def on_message(m)
    return false unless m.prefix and m.prefix.nick
    @db[:seen, m.prefix.nick.downcase] = {cmd: m.command, parm: m.params, on: Time.now}

    if me = @db[:memo, m.prefix.nick.downcase]
      return false if me.length == 0
      post PRIVMSG, m.prefix.nick, "#{m.prefix.nick}, memos for you:"

      me.each do |i|
        post PRIVMSG, m.prefix.nick, i
      end

      @db[:memo, m.prefix.nick.downcase] = []
    end

    false
  end

  def on_privmsg(m)
    @chan = m[0]

    @chan[0] == ?# or return

    @msg = m[1]
    @issuer = m.prefix.nick

    if @msg[0] == ?@
      params = @msg.split(" ")

      cmd = params.shift

      cmd = cmd.gsub("@", '')

      if Ops.method_defined? cmd
        arity = method(cmd).arity_range

        if arity.include? params.count
          send cmd, *params
        else
          respond "Wrong arity! Expected #{arity} got #{params.count}!"
        end
      end
    end
  end

  def respond(m)
    post PRIVMSG, @chan, "#@issuer: #{m}"
  end


  module Ops
    include Net::IRC::Constants

    def help
      respond @methods.map { |i| "@#{i}" }.join(", ")
    end

    def pick b,*a
      a<<b
      respond a.shuffle.join(" > ")
    end

    def ping
      respond "pong!"
    end

    def memo who, *memo
      memo = memo.join(" ")

      s = @db[:memo, who.downcase]
      s ||= []
      s << "[#{Time.now}] <#{@issuer}> #{memo}"
      @db[:memo, who.downcase] = s

      respond "Memo sent!"     
    end

    def seen whom
      if s=@db[:seen, whom.downcase]
        respond "I have last seen #{whom} doing #{s[:cmd]} with #{s[:parm].join(", ")} on #{s[:on]}"
      else
        respond "I haven't seen #{whom} ;__;"
      end
    end

    def f5
      post MODE, @chan, "-D+D"
    end

    def papiez
      przymiotniki = File.read("data/przymiotniki").split("\n")
      respond "Papież #{przymiotniki.sample}"
    end

    def jan n=nil
      czasowniki = File.read('data/czasowniki').split("\n")
      rzeczowniki = File.read('data/rzeczowniki').split("\n")
      if n == nil
        respond "Jan Paweł II #{czasowniki.sample} małe #{rzeczowniki.sample}"
      elsif n[n.length-1] == "ł" || n[n.length-1] == "l"
        respond "Jan Paweł II #{n} małe #{rzeczowniki.sample}"
      else
        respond "Jan Paweł II #{czasowniki.sample} małe #{n}"
      end
    end

  end
  

  include Ops
end

VichanBot.new("sundance.6irc.net", "6667", {
  :nick => "sraczek",
  :user => "sraczek",
  :real => "sraczek",
}).start

