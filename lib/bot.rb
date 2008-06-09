require 'rubygems'
require 'xmpp4r'
require 'logger'
require 'yaml'
require 'json'

$:.unshift File.dirname(__FILE__)

Jabber.debug = true

class Bot
  def self.logger
    @logger ||= Logger.new($stderr)
  end
  def logger; self.class.logger; end

  def initialize(config_filename)
    @config_filename = config_filename
  end
  attr_reader :config_filename

  def connect
    @stream = Jabber::Client.new(config["jid"])
    @stream.connect
    @stream.auth(config["pass"])

    @stream.on_exception do |*a|
      disconnect
    end

    @stream.add_presence_callback do |p|
      handle_presence(p)
    end
    @stream.add_message_callback do |m|
      handle_message(m)
    end

    pres = Jabber::Presence.new
    @stream.send(pres)

    loop { sleep 1 }
  end

  def handle_presence(pres)
    if pres.type == :subscribe
      logger.info "Got a subscription request from #{pres.from}"
      reply = Jabber::Presence.new
      reply.type = :subscribe
      reply.to = pres.from
      @stream.send(reply)
      reply = Jabber::Presence.new
      reply.type = :subscribed
      reply.to = pres.from
      @stream.send(reply)
    end
  end

  def handle_message(msg)
    logger.debug "msg: #{msg.inspect}"
    return if msg.body.nil?
    return unless controlling_jid?(msg.from)
    deliver_message(msg.body)
  end

  def deliver_message(body)
    command = JSON.parse(body)
    command["rcpts"].each do |rcpt|
      msg = Jabber::Message.new(rcpt, command["body"])
      msg.type = :chat
      @stream.send(msg)
    end
  rescue
    logger.error "Failed to deliver message: #{body.inspect}"
  end

  def controlling_jid?(jid)
    logger.debug "testing jid: #{jid.bare.to_s.inspect}"
    config["controllers"].include?(jid.bare.to_s)
  end

  def disconnect
    @stream.close if @stream
  rescue Exception => e
    logger.error "Failed to disconnect cleanly: #{e.class}, #{e.message}"
  end

  def config
    @config ||= YAML.load_file(config_filename)
  end
end

begin
  Bot.logger.debug "Starting on #{$$}"
  b = Bot.new(ARGV.first)
  b.connect
rescue Exception => e
  Bot.logger.error "Caught exception: #{e.class}, #{e.message}"
  Bot.logger.debug e.backtrace.join("\n")
  b.disconnect if b
end

Bot.logger.debug "Finishing on #{$$}"

# vim:sts=2:ts=2:sw=2:et
