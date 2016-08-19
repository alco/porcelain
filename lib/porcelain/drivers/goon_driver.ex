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
    * send an OS signal to the program
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
    Common.communicate(
      port, opts[:in], opts[:out], opts[:err], __MODULE__, async_input: opts[:async_in]
    )
  end

  defp do_spawn(prog, args, opts, shell_flag) do
    opts = Common.compile_options(opts)
    exe = find_executable(prog, opts, shell_flag)

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


  @proto_version "2.0"

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
    {:ok, goon} = Application.fetch_env(:porcelain, :driver_state)
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
    out_opts = Enum.reduce(opts, [], fn
     {:in, _}, acc -> ["-in"|acc]
     {:out, _}, acc -> ["-out"|acc]
     {:err, :out}, acc -> ["-err", "out" | acc]
     {:err, other}, acc when not is_nil(other) -> ["-err", "err" | acc]
     {:dir, dir}, acc -> ["-dir", dir | acc]
     _, acc -> acc
    end)
    out_opts = case Application.fetch_env(:porcelain, :goon_driver_log) do
      :error -> out_opts
      {:ok, val} -> ["-log", val | out_opts]
    end
    ["-proto", @proto_version | out_opts]
  end

  defp common_port_options(opts) do
    [{:packet,2} | Common.port_options(opts)]
  end

  ###

  @doc false
  def process_data(<<0x0>> <> data, output, error) do
    {Common.process_port_output(output, data, :out), error}
  end

  def process_data(<<0x1>> <> data, output, error) do
    {output, Common.process_port_output(error, data, :err)}
  end

  # Maximum chunk size to fit in a single packet. One byte is used as a marker
  # in the Goex protocol v2.0.
  @input_chunk_size 65535-1

  @doc false
  # EOF from user code
  def feed_input(port, "") do
    send_eof(port)
  end

  def feed_input(port, iodata) do
    do_feed_input(port, iodata)
  end

  # EOF internal EOF marker
  defp do_feed_input(port, :eof) do
    send_eof(port)
  end

  defp do_feed_input(port, data) when is_binary(data) do
    size = byte_size(data)
    feed_in_chunks(port, data, @input_chunk_size, 0, size)
  end

  defp do_feed_input(port, iolist) when is_list(iolist) do
    for_each(iolist, &do_feed_input(port, &1))
  end

  defp do_feed_input(port, byte) when is_integer(byte) do
    port_command(port, [byte])
  end

  defp feed_in_chunks(_port, _data, _chunk_size, data_size, data_size), do: nil

  defp feed_in_chunks(port, data, chunk_size, start, data_size) do
    size = min(chunk_size, data_size-start)
    chunk = :binary.part(data, start, size)
    port_command(port, chunk)
    feed_in_chunks(port, data, chunk_size, start+size, data_size)
  end

  defp for_each([], _fun), do: :ok
  defp for_each([h|t], fun) do
    fun.(h)
    for_each(t, fun)
  end

  defp port_command(port, data) do
    Port.command(port, [0,data])
    #:timer.sleep(1)
  end

  defp send_eof(port) do
    Port.command(port, [])
  end

  @doc false
  def send_signal(port, :int) do
    Port.command(port, [1,128])
  end

  def send_signal(port, :kill) do
    Port.command(port, [1,129])
  end

  def send_signal(port, sig) when is_integer(sig) do
    Port.command(port, [1,sig])
  end

  @doc false
  def stop_process(port) do
    status = nil
    #status = Port.command(port, [2, Application.get_env(:porcelain, :goon_stop_timeout, 10)])
    Port.close(port)
    status
  end

  ###

  @doc false
  def check_goon_version(path) do
    ackstr = for << <<byte>> <- :crypto.strong_rand_bytes(8) >>,
                 byte != 0, into: "", do: <<byte>>
    args = ["-proto", @proto_version, "-ack", ackstr]
    opts = {[out: {:string, ""}], []}
    result = %Porcelain.Result{} = Porcelain.Driver.Basic.exec(path, args, opts)
    result.status == 0 and result.out == ackstr
  end

  @doc false
  def proto_version, do: @proto_version
end
