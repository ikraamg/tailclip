require 'json'
require 'sinatra/base'

# Holds the latest clipboard item and tells every connected device when it changes.
class Center < Sinatra::Base
  MAX_BYTES = 10 * 1024 * 1024
  TYPES = %w[text/plain image/png].freeze
  HEARTBEAT_SECONDS = 15

  class << self
    attr_reader :clip, :listeners

    def reset!
      @clip = nil
      @seq = 0
      @listeners = []
      @lock = Mutex.new
    end

    def store(body, type, device)
      @lock.synchronize do
        @clip = { body:, type:, device:, seq: @seq += 1 }
        broadcast "event: clip\ndata: #{@clip.except(:body).to_json}\n\n"
      end
    end

    def heartbeat = @lock.synchronize { broadcast ": ping\n\n" }

    private

    def broadcast(message) = @listeners.each { |queue| queue << message }
  end

  reset!
  set :views, File.join(__dir__, 'views')
  # Tailscale decides who can reach this; Sinatra's default host list would 403 the tailnet name.
  set :host_authorization, permitted_hosts: []

  get('/') { erb :index }

  get '/clip' do
    clip = self.class.clip or halt 404
    headers 'Cache-Control' => 'no-store', 'X-Device' => clip[:device], 'X-Seq' => clip[:seq].to_s
    content_type clip[:type]
    clip[:body]
  end

  post '/clip' do
    halt 415 unless TYPES.include?(request.media_type)
    device = request.env['HTTP_X_DEVICE'].to_s
    halt 400, 'X-Device header is required' if device.empty?
    body = request.body.read
    halt 400, 'empty clip' if body.empty?
    halt 413 if body.bytesize > MAX_BYTES
    self.class.store(body, request.media_type, device)
    204
  end

  # One queue per connection; the stream blocks on it and ends when the client's socket fails a write.
  get '/events' do
    content_type 'text/event-stream'
    headers 'Cache-Control' => 'no-store'
    queue = Queue.new
    self.class.listeners << queue
    stream do |out|
      while (message = queue.pop)
        out << message
      end
    ensure
      self.class.listeners.delete(queue)
    end
  end
end

Thread.new { loop { sleep Center::HEARTBEAT_SECONDS; Center.heartbeat } } unless ENV['RACK_ENV'] == 'test'
