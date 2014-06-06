defmodule Porcelain.Process do
  @moduledoc """
  Module for working with external processes started with `Porcelain.spawn/2`.
  """

  alias __MODULE__, as: P

  @doc """
  A struct representing an OS processes which provides the ability to
  exchange data with it.
  """
  defstruct [:port, :parent, :out, :err, :result]


  @doc """
  Send iodata to the process's stdin.

  End of input is indicated by sending an empty message.

  **Caveat**: when using `Porcelain.Driver.Simple`, it is not possible to
  indicate the end of input. You should close the port explicitly using
  `close/1`.
  """
  @spec send_input(t, iodata) :: iodata

  def send_input(%P{port: port}, data) do
    Port.command(port, data)
  end


  @doc """
  Wait for the external process to terminate.

  Returns `Porcelain.Result` struct with the process's exit status and output.
  Automatically closes the port in this case.

  If timeout value is specified and the external process fails to terminate
  before it runs out, atom `:infinity` is returned.
  """
  @spec await(t, non_neg_integer | :infinity) :: %Porcelain.Result{}

  def await(%P{parent: pid}, timeout \\ :infinity) do
    ref = make_ref()
    send(pid, {:get_result, self(), ref})
    receive do
      {^ref, result} -> result
    after timeout ->
      :timeout
    end
  end


  @doc """
  Check if the underlying port is closed.
  """
  @spec closed?(t) :: true | false

  def closed?(%P{parent: pid}) do
    not Process.alive?(pid)
  end


  @doc """
  Closes the port to the external process created with `spawn/2`.

  Depending on the driver in use, this may or may not terminate the external
  process.
  """
  @spec close(t) :: true

  def close(%P{port: port, parent: pid}) do
    try do
      Port.close(port)
    rescue
      _ -> nil
    end

    mon = Process.monitor(pid)
    ref = make_ref()
    send(pid, {:close, self(), ref})
    receive do
      {^ref, :closed} -> true
      {:DOWN, ^mon, _, _, _info} -> true
    end
  end
end
