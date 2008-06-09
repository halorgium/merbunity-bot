require 'rubygems'
require 'logger'
require 'yaml'
require 'json'
require 'set'
require 'xmpp4r'
require 'xmpp4r/roster'

$:.unshift File.dirname(__FILE__)

class Bot
  def self.logger
    @logger ||= Logger.new($stderr)
  end
  def logger; self.class.logger; end

  def start
    ::Jabber.debug = !!config["debug"]

    @client = Jabber::Client.new(config["jid"])
    @client.on_exception do |*a|
      logger.error "Got a client exception: #{a.inspect}"
      connect
    end
    @client.add_presence_callback do |p|
      handle_presence(p)
    end
    @client.add_message_callback do |m|
      handle_message(m)
    end
    connect

    Thread.stop
  end

  def connect
    @client.connect
    @client.auth(config["pass"])
    @client.send(Jabber::Presence.new)
    @roster ||= Jabber::Roster::Helper.new(@client)
  end

  def handle_presence(pres)
    return if pres.from.bare == @client.jid.bare
    case pres.type
    when :subscribe
      logger.info "Got a subscription request from #{pres.from}"
      @roster.accept_subscription(pres.from)
    when :unsubscribe
      logger.info "Got an unsubscription request from #{pres.from}"
      Thread.new {
        if @roster[pres.from].remove
          logger.info "#{pres.from} removed from the roster"
        else
          logger.warn "#{pres.from} not removed from the roster"
        end
      }
    end
  end

  def handle_message(msg)
    logger.debug "Handling message: #{msg.inspect}"
    return if msg.body.nil?
    return unless controlling_jid?(msg.from)

    case msg.body
    when "ping"
      logger.info "ping from #{msg.from}"
      reply = Jabber::Message.new(msg.from, "pong")
      @client.send(reply)
    when "who"
      logger.info "who request from #{msg.from}"
      watchers = online_watchers
      body = "#{watchers.size} jids online: "
      body << watchers.join(", ")
      reply = Jabber::Message.new(msg.from, body)
      @client.send(reply)
    else
      parse_command(msg.from, msg.body)
    end
  end

  def parse_command(from, command_string)
    command = JSON.parse(command_string)
    rcpts = command["rcpts"] || online_watchers

    logger.info "Delivering #{command["body"]} to #{rcpts.inspect}"

    rcpts.each do |rcpt|
      msg = Jabber::Message.new(rcpt, command["body"])
      msg.type = :chat
      @client.send(msg)
    end
  rescue
    logger.error "Failed to parse command: #{command_string.inspect} with #{$!.class}, #{$!.message}"
  end

  def online_watchers
    watchers = []
    @roster.items.each do |jid,item|
      watchers << jid if item.online?
    end
    watchers
  end

  def controlling_jid?(jid)
    logger.debug "Checking if #{jid.bare} is a controller"
    config["controllers"].include?(jid.bare.to_s)
  end

  def config
    @config ||= YAML.load_file(File.dirname(__FILE__) + '/../data/config.yml')
  end
end

begin
  Bot.logger.debug "Starting on #{$$}"
  b = Bot.new
  b.start
rescue Exception => e
  Bot.logger.error "Caught exception: #{e.class}, #{e.message}"
  Bot.logger.debug e.backtrace.join("\n")
end

Bot.logger.debug "Finishing on #{$$}"

# vim:sts=2:ts=2:sw=2:et
