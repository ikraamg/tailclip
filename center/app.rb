require 'json'
require 'sinatra/base'

# Holds the latest clipboard item and tells every connected device when it changes.
class Center < Sinatra::Base
  MAX_BYTES = 10 * 1024 * 1024
  TYPES = %w[text/plain image/png].freeze
  HEARTBEAT_SECONDS = 15
  LOGINS = ENV['TAILCLIP_LOGINS'].to_s.split(',').map(&:strip).reject(&:empty?).freeze

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
  # Any other Host is a browser on this Mac being DNS-rebound at 127.0.0.1:8788.
  set :host_authorization, permitted_hosts: ['localhost', '127.0.0.1', '.ts.net']

  # Tailscale Serve stamps this header over anything the client sent; a request without it came from this Mac.
  before do
    login = request.env['HTTP_TAILSCALE_USER_LOGIN']
    halt 403, 'login not permitted' if login && LOGINS.any? && !LOGINS.include?(login)
  end

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
    queue << ": connected\n\n" # Puma holds the headers until the first body byte
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
