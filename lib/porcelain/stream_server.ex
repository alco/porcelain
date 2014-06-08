defmodule Porcelain.Driver.Basic.StreamServer do
  @moduledoc false

  # Internal module used to make output streams work

  require Record
  Record.defrecordp :state, [:done, :data, :client]

  use GenServer

  def start() do
    GenServer.start(__MODULE__, state(data: []))
  end

  def get_data(pid) do
    log "Stream server get data #{inspect self()}"
    GenServer.call(pid, :get_data, :infinity)
  end

  def put_data(pid, data) do
    log "Stream server put data"
    GenServer.cast(pid, {:data, data})
  end

  def finish(pid) do
    log "Stream server finish"
    GenServer.cast(pid, :done)
  end

  ###

  def handle_call(:get_data, _from, state(done: true, data: data)) do
    reply = if data == [], do: nil, else: data
    log "Stream server did stop with reply"
    {:stop, :shutdown, reply, nil}
  end

  def handle_call(:get_data, from, state(data: [])=state) do
    log "get_data: []"
    {:noreply, state(state, client: from)}
  end

  def handle_call(:get_data, _from, state(data: data)=state) do
    log "get_data: <data>"
    {:reply, data, state(state, data: [])}
  end


  def handle_cast({:data, new_data}, state(data: data, client: nil)=state) do
    log "Stream server got data"
    {:noreply, state(state, data: [data, new_data])}
  end

  def handle_cast({:data, new_data}, state(data: [], client: client)=state) do
    log "Stream server got data. Sending to client"
    GenServer.reply(client, new_data)
    {:noreply, state(state, client: nil)}
  end


  def handle_cast(:done, state(client: nil)=state) do
    {:noreply, state(state, done: true)}
  end

  def handle_cast(:done, state(data: [], client: client)) do
    log "Stream server did stop"
    GenServer.reply(client, nil)
    {:stop, :shutdown, nil}
  end

  def handle_cast(:done, state(data: data, client: client)) do
    log "Stream server did stop"
    GenServer.reply(client, data)
    {:stop, :shutdown, nil}
  end

  defp log(_), do: nil
  #defp log(msg), do: IO.puts msg
end
