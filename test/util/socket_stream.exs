defmodule SocketStream do
  def new(host, port) do
    Stream.resource(
        fn -> open_stream(host, port) end,
        &stream_loop/1,
        &close_stream/1)
  end

  defp open_stream(host, port) do
    {:ok, sock} = :gen_tcp.connect(host, port,
                        [:binary, {:active, false}, {:packet, :line}])
    req = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
    :gen_tcp.send(sock, req)
    sock
  end

  defp stream_loop(sock) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, data}       -> {data, sock}
      {:error, :closed} -> nil
    end
  end

  defp close_stream(sock) do
    :gen_tcp.close(sock)
  end
end
