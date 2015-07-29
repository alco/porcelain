defmodule Porcelain.Process do
  @moduledoc """
  Module for working with external processes launched with `Porcelain.spawn/3`
  or `Porcelain.spawn_shell/2`.
  """

  alias __MODULE__, as: P

  @doc """
  A struct representing a wrapped OS processes which provides the ability to
  exchange data with it.
  """
  defstruct [:pid, :out, :err]

  @type t :: %__MODULE__{}
  @type signal :: :int | :kill | non_neg_integer


  @doc """
  Send iodata to the process's stdin.

  End of input is indicated by sending an empty message.

  **Caveat**: when using `Porcelain.Driver.Basic`, it is not possible to
  indicate the end of input. You should stop the process explicitly using
  `stop/1`.
  """
  @spec send_input(t, iodata) :: iodata

  def send_input(%P{pid: pid}, data) do
    send(pid, {:input, data})
  end


  @doc """
  Wait for the external process to terminate.

  Returns `Porcelain.Result` struct with the process's exit status and output.
  Automatically closes the underlying port in this case.

  If timeout value is specified and the external process fails to terminate
  before it runs out, atom `:timeout` is returned.
  """
  @spec await(t, non_neg_integer | :infinity) :: {:ok, Porcelain.Result.t} | {:error, :noproc | :timeout}

  def await(%P{pid: pid}, timeout \\ :infinity) do
    mon = Process.monitor(pid)
    ref = make_ref()
    send(pid, {:get_result, self(), ref})
    receive do
      {^ref, result} ->
        Process.demonitor(mon, [:flush])
        {:ok, result}
      {:DOWN, ^mon, _, _, _info} -> {:error, :noproc}
    after timeout ->
      Process.demonitor(mon, [:flush])
      {:error, :timeout}
    end
  end


  @doc """
  Check if the process is still running.
  """
  @spec alive?(t) :: true | false

  def alive?(%P{pid: pid}) do
    #FIXME: does not work with pids from another node
    Process.alive?(pid)
  end


  @doc """
  Stops the process created with `Porcelain.spawn/3` or
  `Porcelain.spawn_shell/2`. Also closes the underlying Erlang port.

  May cause "broken pipe" message to be written to stderr.

  ## Caveats

  When using `Porcelain.Driver.Basic`, Porcelain will merely close the Erlang port
  connected to that process. This normally causes an external process to terminate provided that it
  is listening on its `stdin`. If not, the external process will continue running.

  See http://erlang.org/pipermail/erlang-questions/2010-March/050227.html for some background info.

  When using `Porcelain.Driver.Goon`, a `SIGTERM` signal will be sent to the external process. If it
  doesn't terminate after `:goon_stop_timeout` seconds, a `SIGKILL` will be sent to the process.
  """
  @spec stop(t) :: true

  def stop(%P{pid: pid}) do
    mon = Process.monitor(pid)
    ref = make_ref()
    send(pid, {:stop, self(), ref})
    receive do
      {^ref, :stopped} -> Process.demonitor(mon, [:flush])
      {:DOWN, ^mon, _, _, _info} -> true
    end
  end

  @doc """
  Send an OS signal to the processes.

  No further communication with the process is possible after sending it a
  signal.
  """
  @spec signal(t, signal) :: signal

  def signal(%P{pid: pid}, sig) do
    send(pid, {:signal, sig})
  end
end
