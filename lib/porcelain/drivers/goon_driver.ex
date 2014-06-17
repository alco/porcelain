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
    communicate(port, opts[:in], opts[:out], opts[:err],
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
        Stream.unfold(server, &read_stream/1)

      {atom, ""} when atom in [:string, :iodata] ->
        atom

      _ -> out_opt
    end

    pid = spawn(fn ->
      port = Port.open(exe, port_options(shell_flag, prog, args, opts))
      communicate(port, opts[:in], out_opt, opts[:err],
          async_input: true, result: opts[:result])
    end)

    %Porcelain.Process{
      pid: pid,
      out: out_ret,
      err: opts[:err],
    }
  end


  @proto_version "0.0"

  @doc false
  defp find_executable(prog, _, :noshell) do
    if :os.find_executable(:erlang.binary_to_list(prog)) do
      {:spawn_executable, Common.find_goon(:noshell)}
    else
      throw "Command not found: #{prog}"
    end
  end

  defp find_executable(prog, opts, :shell) do
    invocation =
      [Common.find_goon(:shell), goon_options(opts), "--", prog]
      |> List.flatten
      |> Enum.join(" ")
      #|> IO.inspect
    {:spawn, invocation}
  end


  defp port_options(:noshell, prog, args, opts) do
    #IO.puts "Choosing port options for :noshell, #{prog} with args #{inspect args} and opts #{inspect opts}"
    args = List.flatten([goon_options(opts), "--", prog, args])
    [{:args, args} | common_port_options(opts)] #|> IO.inspect
  end

  defp port_options(:shell, _, _, opts) do
    common_port_options(opts) #|> IO.inspect
  end

  defp goon_options(opts) do
    ret = []
    if opts[:in] != nil,
      do: ret = ["-in"|ret]
    if opts[:out] == nil,
      do: ret = ["-out", "nil"|ret]
    case opts[:err] do
      nil ->
        ret = ["-err", "nil"|ret]
      :out ->
        flag = if opts[:out], do: "out", else: "nil"
        ret = ["-err", flag|ret]
      _ -> nil
    end
    if dir=opts[:dir],
      do: ret = ["-dir", dir|ret]
    ["-proto", @proto_version|ret]
  end

  defp common_port_options(opts) do
    [{:packet,2}|Common.port_options(opts)]
  end

  defp communicate(port, input, output, error, opts) do
    input_fun = fn -> send_input(port, input) end
    if opts[:async_input] do
      spawn(input_fun)
    else
      input_fun.()
    end
    collect_output(port, output, error, opts[:result])
  end

  defp send_input(port, input) do
    case input do
      iodata when is_binary(iodata) or is_list(iodata) ->
        Port.command(port, input)
        send_eof(port)

      {:file, fid} ->
        pipe_file(fid, port)

      {:path, path} ->
        File.open(path, [:read], fn(fid) ->
          pipe_file(fid, port)
        end)

      null when null in [nil, :receive] ->
        nil

      other -> stream_to_port(other, port)
    end
  end

  defp send_eof(port), do: Port.command(port, "")

  defp read_stream(server) do
    case StreamServer.get_data(server) do
      nil  -> nil
      data -> {data, server}
    end
  end

  # we read files in blocks to avoid excessive memory usage
  @file_block_size 1024*1024

  defp pipe_file(fid, port) do
    Stream.repeatedly(fn -> IO.read(fid, @file_block_size) end)
    |> Stream.take_while(fn
      :eof        -> false
      {:error, _} -> false
      _           -> true
    end)
    |> stream_to_port(port)
  end

  defp stream_to_port(enum, port) do
    # set up a try block, because the port may close before consuming all input
    try do
      Enum.each(enum, fn
        iodata when is_list(iodata) or is_binary(iodata) ->
          # the sleep is needed to work around the problem of port hanging
          :timer.sleep(1)
          Port.command(port, iodata, [:nosuspend])
        byte ->
          :timer.sleep(1)
          Port.command(port, [byte])
      end)
    catch
      :error, :badarg -> nil
    end
    send_eof(port)
  end

  defp collect_output(port, output, error, result_opt) do
    receive do
      { ^port, {:data, <<?o>> <> data} } ->
        output = process_port_output(output, data)
        collect_output(port, output, error, result_opt)

      { ^port, {:data, <<?e>> <> data} } ->
        error = process_port_output(error, data)
        collect_output(port, output, error, result_opt)

      { ^port, {:exit_status, status} } ->
        result = finalize_result(status, output, error)
        send_result(output, result_opt, result)
        || case result_opt do
          nil      -> result
          :discard -> nil
          :keep    -> wait_for_command(result)
        end

      {:input, data} ->
        Port.command(port, data)
        collect_output(port, output, error, result_opt)

      {:stop, from, ref} ->
        Port.close(port)
        result = finalize_result(nil, output, error)
        send_result(output, result_opt, result)
        send(from, {ref, :stopped})
    end
  end

  defp finalize_result(status, out, err) do
    %Porcelain.Result{status: status, out: flatten(out), err: flatten(err)}
  end

  defp send_result({:send, pid}, opt, result) do
    if opt == :discard, do: result = nil
    send(pid, {self(), :result, result})
    true
  end

  defp send_result(_, _, _), do: false

  defp wait_for_command(result) do
    receive do
      {:stop, from, ref} ->
        send(from, {ref, :stopped})
      {:get_result, from, ref} ->
        send(from, {ref, result})
    end
  end


  defp process_port_output(nil, _) do
    nil
  end

  defp process_port_output({typ, data}, new_data)
    when typ in [:string, :iodata]
  do
    {typ, [data, new_data]}
  end

  defp process_port_output({:file, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  defp process_port_output({:path, path}, data) do
    {:ok, fid} = File.open(path, [:write])
    process_port_output({:path, path, fid}, data)
  end

  defp process_port_output({:append, path}, data) do
    {:ok, fid} = File.open(path, [:append])
    process_port_output({:path, path, fid}, data)
  end

  defp process_port_output({:path, _, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  defp process_port_output({:stream, server}=x, data) do
    StreamServer.put_data(server, data)
    x
  end

  defp process_port_output({:send, pid}=x, data) do
    send(pid, {self(), :data, data})
    x
  end

  defp flatten(thing) do
    case thing do
      {:string, data}    -> IO.iodata_to_binary(data)
      {:iodata, data}    -> data
      {:path, path, fid} -> File.close(fid); {:path, path}
      {:stream, server}  -> StreamServer.finish(server)
      other              -> other
    end
  end
end
