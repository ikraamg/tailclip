RSpec.describe Center do
  subject(:app) { described_class }

  let(:listener) { [] }
  let(:post_text) { post '/clip', 'hello', 'CONTENT_TYPE' => 'text/plain', 'HTTP_X_DEVICE' => 'macbook' }

  describe 'POST /clip' do
    it 'answers 204' do
      post_text
      expect(last_response.status).to eq 204
    end

    it 'stores the clip' do
      post_text
      get '/clip'
      expect(last_response.body).to eq 'hello'
    end

    it 'keeps the content type' do
      post '/clip', 'png-bytes', 'CONTENT_TYPE' => 'image/png', 'HTTP_X_DEVICE' => 'macbook'
      get '/clip'
      expect(last_response.content_type).to eq 'image/png'
    end

    it 'tells listeners which device sent it' do
      described_class.listeners << listener
      post_text
      expect(listener.first).to eq "event: clip\ndata: #{{ type: 'text/plain', device: 'macbook', seq: 1 }.to_json}\n\n"
    end

    it 'numbers clips in order' do
      described_class.listeners << listener
      2.times { post '/clip', 'hello', 'CONTENT_TYPE' => 'text/plain', 'HTTP_X_DEVICE' => 'macbook' }
      expect(listener.last).to include '"seq":2'
    end

    it 'rejects a type it cannot store' do
      post '/clip', '<b>hi</b>', 'CONTENT_TYPE' => 'text/html', 'HTTP_X_DEVICE' => 'macbook'
      expect(last_response.status).to eq 415
    end

    it 'rejects a clip without a device' do
      post '/clip', 'hello', 'CONTENT_TYPE' => 'text/plain'
      expect(last_response.status).to eq 400
    end

    it 'rejects an empty clip' do
      post '/clip', '', 'CONTENT_TYPE' => 'text/plain', 'HTTP_X_DEVICE' => 'macbook'
      expect(last_response.status).to eq 400
    end

    it 'rejects a clip over the size cap' do
      stub_const('Center::MAX_BYTES', 4)
      post_text
      expect(last_response.status).to eq 413
    end
  end

  describe 'GET /clip' do
    it 'answers 404 before anything is sent' do
      get '/clip'
      expect(last_response.status).to eq 404
    end

    it 'names the device and sequence in headers' do
      post_text
      get '/clip'
      expect(last_response.headers.slice('x-device', 'x-seq')).to eq('x-device' => 'macbook', 'x-seq' => '1')
    end

    it 'is never cached' do
      post_text
      get '/clip'
      expect(last_response.headers['cache-control']).to eq 'no-store'
    end
  end

  describe 'GET /events' do
    include_context 'with a running server'

    let(:socket) { open_events }

    after { socket.close unless socket.closed? }

    it 'is an event stream' do
      expect(socket_headers).to include 'content-type: text/event-stream'
    end

    it 'registers the connection as a listener' do
      socket_headers
      expect(described_class.listeners.size).to eq 1
    end

    it 'pushes each clip as it arrives' do
      socket_headers
      post_text
      expect(socket.gets).to eq "event: clip\n"
    end

    it 'forgets a listener whose connection has closed' do
      socket_headers
      socket.close
      2.times { described_class.heartbeat && sleep(0.2) }
      expect(described_class.listeners).to be_empty
    end
  end

  describe 'GET /' do
    it 'serves the page' do
      get '/'
      expect(last_response.body).to include '<textarea'
    end
  end
end
