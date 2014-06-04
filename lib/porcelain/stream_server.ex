defmodule Porcelain.Driver.Simple.StreamServer do
  @moduledoc false

  # Internal module used to make output streams work

  require Record
  Record.defrecordp :state, [:done, :data, :client]

  use GenServer

  def start() do
    GenServer.start(__MODULE__, state(data: []))
  end

  def get_data(pid) do
    GenServer.call(pid, :get_data, :infinity)
  end

  def put_data(pid, data) do
    GenServer.cast(pid, {:data, data})
  end

  def finish(pid) do
    GenServer.cast(pid, :done)
  end

  ###

  def handle_call(:get_data, from, state(data: [])=state) do
    {:noreply, state(state, client: from)}
  end

  def handle_call(:get_data, _from, state(done: true, data: data)) do
    # {:stop, reason, reply, new_state}
    {:stop, :shutdown, data, nil}
  end

  def handle_call(:get_data, _from, state(data: data)=state) do
    {:reply, data, state(state, data: [])}
  end


  def handle_cast({:data, new_data}, state(data: data, client: nil)=state) do
    {:noreply, state(state, data: [data, new_data])}
  end

  def handle_cast({:data, new_data}, state(data: [], client: client)=state) do
    GenServer.reply(client, new_data)
    {:noreply, state(state, client: nil)}
  end


  def handle_cast(:done, state(client: nil)=state) do
    {:noreply, state(state, done: true)}
  end

  def handle_cast(:done, state(data: [], client: client)) do
    GenServer.reply(client, nil)
    {:stop, :shutdown, nil}
  end

  def handle_cast(:done, state(data: data, client: client)) do
    GenServer.reply(client, data)
    {:stop, :shutdown, nil}
  end
end
