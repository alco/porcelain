defmodule Porcelain.Driver.Goon do
  @moduledoc """
  Porcelain driver that offers additional features over the basic one.

  Users are not supposed to call functions in this module directly. Use
  functions in `Porcelain` instead.

  This driver will be used by default if it can locate the external program
  named `goon` in the executable path. If `goon` is not found, Porcelain will
  fall back to the basic driver.

  The additional functionality provided by this driver is as follows:

    * ability to signal EOF to the external program
    * (to be implemented) send an OS signal to the program
    * (to be implemented) more efficient piping of multiple programs

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
    exe = find_executable(prog, opts, shell_flag)
    port = Port.open(exe, port_options(shell_flag, prog, args, opts))
    Common.communicate(port, opts[:in], opts[:out], opts[:err], &process_data/3,
        async_input: opts[:async_in])
  end

  defp do_spawn(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, opts, shell_flag)

    out_opt = opts[:out]
    out_ret = case out_opt do
      :stream ->
        {:ok, server} = StreamServer.start()
        out_opt = {:stream, server}
        Stream.unfold(server, &Common.read_stream/1)

      {atom, ""} when atom in [:string, :iodata] ->
        atom

      _ -> out_opt
    end

    pid = spawn(fn ->
      port = Port.open(exe, port_options(shell_flag, prog, args, opts))
      Common.communicate(port, opts[:in], out_opt, opts[:err], &process_data/3,
          async_input: true, result: opts[:result])
    end)

    %Porcelain.Process{
      pid: pid,
      out: out_ret,
      err: opts[:err],
    }
  end


  @proto_version "1.0"

  @doc false
  defp find_executable(prog, _, :noshell) do
    if Common.find_executable(prog) do
      {:spawn_executable, goon_exe()}
    else
      throw "Command not found: #{prog}"
    end
  end

  defp find_executable(_, _, :shell) do
    {:spawn_executable, goon_exe()}
  end

  defp goon_exe() do
    {:ok, goon} = :application.get_env(:porcelain, :driver_state)
    goon
  end


  defp port_options(:noshell, prog, args, opts) do
    args = List.flatten([goon_options(opts), "--", Common.find_executable(prog), args])
    [{:args, args} | common_port_options(opts)]
  end

  defp port_options(:shell, prog, _, opts) do
    {sh, sh_args} = Common.shell_command(prog)
    args = List.flatten([goon_options(opts), "--", List.to_string(sh), sh_args])
    [{:args, args} | common_port_options(opts)]
  end

  defp goon_options(opts) do
    ret = []
    if opts[:in], do: ret = ["-in"|ret]
    if opts[:out], do: ret = ["-out"|ret]
    case opts[:err] do
      :out -> ret = ["-err", "out"|ret]
      nil -> nil
      _ -> ret = ["-err", "err"|ret]
    end
    if dir=opts[:dir], do: ret = ["-dir", dir|ret]
    case :application.get_env(:porcelain, :goon_driver_log) do
      :undefined -> nil
      {:ok, val} -> ret = ["-log", val|ret]
    end
    ["-proto", @proto_version|ret]
  end

  defp common_port_options(opts) do
    [{:packet,2}|Common.port_options(opts)]
  end

  ###

  defp process_data(<<0x0>> <> data, output, error) do
    {Common.process_port_output(output, data), error}
  end

  defp process_data(<<0x1>> <> data, output, error) do
    {output, Common.process_port_output(error, data)}
  end

  ###

  @doc false
  def check_goon_version(path) do
    ackstr = for << <<byte>> <- :crypto.rand_bytes(8) >>,
                 byte != 0, into: "", do: <<byte>>
    args = ["-proto", @proto_version, "-ack", ackstr]
    opts = {[out: {:string, ""}], []}
    result = %Porcelain.Result{} = Porcelain.Driver.Basic.exec(path, args, opts)
    result.status == 0 and result.out == ackstr
  end

  @doc false
  def proto_version, do: @proto_version
end
