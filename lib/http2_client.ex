defmodule HTTP2Client do
  use GenServer

  @initial_state %{socket: nil}

  def start_link do
    GenServer.start_link(__MODULE__, @initial_state, name: __MODULE__)
  end

  def init(state) do
    setup
    {:ok, state}
  end

  def setup do
    GenServer.cast(__MODULE__, :setup)
  end

  def send(msg) do
    GenServer.cast(__MODULE__, {:send, msg})
  end

  def handle_cast(:setup, %{socket: nil}) do
    IO.puts "Connecting..."

    {:ok, socket} = connect
    {:noreply, socket}
  end

  def handle_info({:tcp, socket, msg}, state) do
    IO.inspect Base.encode16(msg)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    IO.puts "The connection was closed!"
    setup
    {:noreply, %{socket: nil}}
  end

  def handle_cast({:send, msg}, socket) do
    :gen_tcp.send(socket, msg)

    {:noreply, socket}
  end

  defp connect do
    hostname = 'localhost'
    port = 80
    options = [:binary, active: true, nodelay: true]

    :gen_tcp.connect(hostname, port, options)
  end
end
