defmodule Porcelain.Process do
  @moduledoc """
  Module for working with external processes started with `Porcelain.spawn/2`.
  """

  alias __MODULE__

  @doc """
  A struct representing an OS processes which provides the ability to
  exchange data with it.
  """
  defstruct [:port, :out, :err]


  @doc """
  Send iodata to the process's stdin.

  End of input is indicated by sending an empty message.

  **Caveat**: when using `Porcelain.Driver.Simple`, it is not possible to
  indicate the end of input. You should close the port explicitly using
  `close/1`.
  """
  @spec send(t, iodata) :: iodata

  def send(%Process{port: port}, data) do
    Port.command(port, data)
  end


  @doc """
  Wait for the external process to terminate.

  Returns `Porcelain.Result` struct with the process's exit status and output.
  """
  @spec await(t) :: %Porcelain.Result{}

  def await(%Process{}) do
    %Porcelain.Result{}
  end


  @doc """
  Check if the underlying port is closed.
  """
  @spec closed?(t) :: true | false

  def closed?(%Process{port: port}) do
    Port.info(port) == :undefined
  end


  @doc """
  Closes the port to the external process created with `spawn/2`.

  Depending on the driver in use, this may or may not terminate the external
  process.
  """
  @spec close(t) :: true

  def close(%Process{port: port}) do
    Port.close(port)
  end
end
