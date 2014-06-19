defmodule Porcelain.Driver.Common.StreamServer do
  @moduledoc false

  # Internal module used to make output streams work

  require Record
  Record.defrecordp :state, [:done, :chunks, :client]

  use GenServer

  def start() do
    GenServer.start(__MODULE__, state(chunks: :queue.new))
  end

  def get_data(pid) do
    log "Stream server get data #{inspect self()}"
    GenServer.call(pid, :get_data, :infinity)
  end

  def put_data(pid, data) do
    log "Stream server put data #{inspect data}"
    :ok = GenServer.call(pid, {:data, data})
  end

  def finish(pid) do
    log "Stream server finish"
    GenServer.cast(pid, :done)
  end

  ###

  def handle_call(:get_data, _from, state(done: true, chunks: q)=state) do
    if :queue.is_empty(q) do
      log "Stream server did stop"
      {:stop, :shutdown, nil, nil}
    else
      log "Stream server reply"
      {:reply, :queue.head(q), state(state, chunks: :queue.tail(q))}
    end
  end

  def handle_call(:get_data, from, state(chunks: q)=state) do
    if :queue.is_empty(q) do
      log "get_data: []"
      {:noreply, state(state, client: from)}
    else
      log "get_data: <data>"
      {:reply, :queue.head(q), state(state, chunks: :queue.tail(q))}
    end
  end


  def handle_call({:data, data}, _from, state(chunks: q, client: nil)=state) do
    log "Stream server got data"
    {:reply, :ok, state(state, chunks: :queue.in(data, q))}
  end

  def handle_call({:data, data}, _from, state(chunks: q, client: client)=state) do
    true = :queue.is_empty(q)

    log "Stream server got data. Sending to client"
    GenServer.reply(client, data)
    {:reply, :ok, state(state, client: nil)}
  end


  def handle_cast(:done, state(client: nil)=state) do
    {:noreply, state(state, done: true)}
  end

  def handle_cast(:done, state(chunks: q, client: client)=state) do
    if :queue.is_empty(q) do
      log "Stream server did stop"
      GenServer.reply(client, nil)
      {:stop, :shutdown, nil}
    else
      GenServer.reply(client, :queue.head(q))
      {:noreply, state(state, done: true, chunks: :queue.tail(q))}
    end
  end

  defp log(_), do: nil
  #defp log(msg), do: IO.puts msg
end
