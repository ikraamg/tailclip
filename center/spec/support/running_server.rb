require 'puma'
require 'socket'

RSpec.shared_context 'with a running server' do
  let(:port) { server.connected_ports.first }
  let(:server) do
    Puma::Server.new(Center, nil, log_writer: Puma::LogWriter.null).tap do |puma|
      puma.add_tcp_listener('127.0.0.1', 0)
      puma.run
    end
  end

  after do
    Center.listeners.each(&:close)
    server.stop(true)
  end

  def open_events
    TCPSocket.new('127.0.0.1', port).tap do |socket|
      socket.timeout = 2
      socket.write "GET /events HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n"
    end
  end

  def socket_headers
    @socket_headers ||= [].tap { |lines| lines << socket.gets until lines.last == "\r\n" }.join
  end
end
