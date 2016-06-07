defmodule Porcelain.Driver.Basic do
  @moduledoc """
  Porcelain driver that offers basic functionality for interacting with
  external programs.

  Users are not supposed to call functions in this module directly. Use
  functions in `Porcelain` instead.

  This driver has two major limitations compared to `Porcelain.Driver.Goon`:

    * the `exec` function does not work with programs that read all input until
      EOF before producing any output. Such programs will hang since Erlang
      ports don't provide any mechanism to indicate the end of input.

      If a program is continuously consuming input and producing output, it
      could work with the `spawn` function, but you'll also have to explicitly
      close the connection with the external program when you're done with it.

    * sending OS signals to external processes is not supported

  """

  alias Porcelain.Driver.Common
  alias Common.StreamServer
  @behaviour Common


  @doc false
  def exec(prog, args, opts) do
    do_exec(prog, args, opts, :noshell)
  end

  @doc false
  def exec_shell(prog, opts) do
    do_exec(prog, nil, opts, :shell)
  end


  @doc false
  def spawn(prog, args, opts) do
    do_spawn(prog, args, opts, :noshell)
  end

  @doc false
  def spawn_shell(prog, opts) do
    do_spawn(prog, nil, opts, :shell)
  end

  ###

  defp do_exec(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, shell_flag)
    port = Port.open(exe, port_options(shell_flag, prog, args, opts))
    Common.communicate(
      port, opts[:in], opts[:out], opts[:err], __MODULE__, async_input: opts[:async_in]
    )
  end

  defp do_spawn(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, shell_flag)

    {out_opt, out_ret} = case opts[:out] do
      :stream ->
        {:ok, server} = StreamServer.start()
        {{:stream, server}, Stream.unfold(server, &Common.read_stream/1)}

      {atom, ""} = opt when atom in [:string, :iodata] ->
        {opt, atom}

      other ->
        {other, other}
    end

    pid = spawn(fn ->
      port = Port.open(exe, port_options(shell_flag, prog, args, opts))
      Common.communicate(
        port, opts[:in], out_opt, opts[:err], __MODULE__, async_input: true, result: opts[:result]
      )
    end)

    %Porcelain.Process{
      pid: pid,
      out: out_ret,
      err: opts[:err],
    }
  end


  @doc false
  defp find_executable(prog, :noshell) do
    if exe=Common.find_executable(prog) do
      {:spawn_executable, exe}
    else
      throw "Command not found: #{prog}"
    end
  end

  defp find_executable(prog, :shell) do
    {sh, _} = Common.shell_command(prog)
    if exe=:os.find_executable(sh) do
      {:spawn_executable, exe}
    else
      throw "Shell not found for: #{prog}"
    end
  end


  defp port_options(:noshell, _, args, opts),
    do: [{:args, args} | common_port_options(opts)]

  defp port_options(:shell, prog, _, opts) do
    {_, args} = Common.shell_command(prog)
    [{:args, args} | common_port_options(opts)]
  end

  defp common_port_options(opts) do
    [:stream | Common.port_options(opts)]
    ++ (if dir=opts[:dir], do: [{:cd, dir}], else: [])
    ++ (if opts[:err] == :out, do: [:stderr_to_stdout], else: [])
  end

  ###

  @doc false
  def feed_input(port, iodata) when is_list(iodata) do
    # we deconstruct the list here to avoid recursive calls in do_feed_input
    Enum.each(iodata, &do_feed_input(port, &1))
  end

  def feed_input(port, iodata) do
    do_feed_input(port, iodata)
  end

  defp do_feed_input(_port, :eof) do
    # basic driver does not support handling EOF
  end

  defp do_feed_input(port, byte) when is_integer(byte) do
    Port.command(port, [byte])
  end

  defp do_feed_input(port, data) do
    Port.command(port, data)
  end

  @doc false
  def process_data(data, output, error) do
    {Common.process_port_output(output, data, :out), error}
  end

  @doc false
  def send_signal(_port, _sig) do
    # basic driver does not support signals
  end

  @doc false
  def stop_process(port) do
    Port.close(port)
    nil
  end
end
