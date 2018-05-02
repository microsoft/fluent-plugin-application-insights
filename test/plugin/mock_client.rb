require "application_insights"

class MockSender < Channel::SenderBase
  def initialize
  end

  def start
  end
end

class MockQueue
  attr_accessor :sender
  attr_accessor :queue

  def initialize(sender)
    @sender = sender
    @queue = []
  end

  def push(item)
    return unless item
    @queue << item
  end

  def empty?
    @queue.empty?
  end

  def [](index)
    @queue[index]
  end

  def flush
    @queue = []
  end
end

