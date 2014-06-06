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
  defstruct [:pid, :out, :err, :result]


  @doc """
  Send iodata to the process's stdin.

  End of input is indicated by sending an empty message.

  **Caveat**: when using `Porcelain.Driver.Simple`, it is not possible to
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
  @spec await(t, non_neg_integer | :infinity) :: Porcelain.Result.t

  def await(%P{pid: pid}, timeout \\ :infinity) do
    ref = make_ref()
    send(pid, {:get_result, self(), ref})
    receive do
      {^ref, result} -> result
    after timeout ->
      :timeout
    end
  end


  @doc """
  Check if the process is still running.
  """
  @spec alive?(t) :: true | false

  def alive?(%P{pid: pid}) do
    Process.alive?(pid)
  end


  @doc """
  Stops the process created with `Porcelain.spawn/3` or
  `Porcelain.spawn_shell/2`. Also closes the underlying port.
  """
  @spec stop(t) :: true

  def stop(%P{pid: pid}) do
    mon = Process.monitor(pid)
    ref = make_ref()
    send(pid, {:stop, self(), ref})
    receive do
      {^ref, :stopped} -> true
      {:DOWN, ^mon, _, _, _info} -> true
    end
  end
end
