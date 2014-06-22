defmodule Porcelain.Driver.Common do
  @moduledoc false

  use Behaviour

  defcallback exec(prog :: binary, args :: [binary], opts :: Keyword.t)
  defcallback exec_shell(prog :: binary, opts :: Keyword.t)
  defcallback spawn(prog :: binary, args :: [binary], opts :: Keyword.t)
  defcallback spawn_shell(prog :: binary, opts :: Keyword.t)


  alias Porcelain.Driver.Common.StreamServer


  def find_executable(prog) do
    cond do
      File.exists?(prog) ->
        Path.absname(prog)
      exe=:os.find_executable(:erlang.binary_to_list(prog)) ->
        List.to_string(exe)
      true -> false
    end
  end


  def compile_options({opts, []}) do
    opts
  end

  def compile_options({_opts, extra_opts}) do
    msg = "Invalid options: #{inspect extra_opts}"
    raise Porcelain.UsageError, message: msg
  end

  @common_options [:binary, :use_stdio, :exit_status, :hide]
  def port_options(opts) do
    ret = @common_options
    if env=opts[:env],
      do: ret = [{:env, env}|ret]
    if opts[:in] && !(opts[:out] || opts[:err]),
      do: ret = [:in|ret]
    ret
  end


  def shell_command(command) do
    {:ok, {sh, args}} = :application.get_env(:porcelain, :shell_command)
    {sh, args ++ [command]}
  end

  ###

  def read_stream(server) do
    case StreamServer.get_data(server) do
      nil  -> nil
      data -> {data, server}
    end
  end

  ###

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

  # we read files in blocks to avoid excessive memory usage
  @file_block_size 1024*1024

  defp pipe_file(fid, port) do
    Stream.repeatedly(fn -> :file.read(fid, @file_block_size) end)
    |> Stream.take_while(fn
      :eof        -> false
      {:error, _} -> false
      _           -> true
    end)
    |> Stream.map(fn {:ok, data} -> data end)
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

  ###

  def communicate(port, input, output, error, data_handler, opts) do
    input_fun = fn -> send_input(port, input) end
    if opts[:async_input] do
      spawn(input_fun)
    else
      input_fun.()
    end
    collect_output(port, output, error, opts[:result], data_handler)
  end

  defp collect_output(port, output, error, result_opt, port_data_handler) do
    receive do
      { ^port, {:data, data} } ->
        {output, error} = port_data_handler.(data, output, error)
        collect_output(port, output, error, result_opt, port_data_handler)

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
        collect_output(port, output, error, result_opt, port_data_handler)

      {:stop, from, ref} ->
        Port.close(port)
        result = finalize_result(nil, output, error)
        send_result(output, result_opt, result)
        send(from, {ref, :stopped})
    end
  end

  ###

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

  ###

  def process_port_output(nil, _) do
    nil
  end

  def process_port_output({typ, data}, new_data)
    when typ in [:string, :iodata]
  do
    {typ, [data, new_data]}
  end

  def process_port_output({:file, fid}=x, data) do
    :ok = :file.write(fid, data)
    x
  end

  def process_port_output({:path, path}, data) do
    {:ok, fid} = File.open(path, [:write])
    process_port_output({:path, path, fid}, data)
  end

  def process_port_output({:append, path}, data) do
    {:ok, fid} = File.open(path, [:append])
    process_port_output({:path, path, fid}, data)
  end

  def process_port_output({:path, _, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  def process_port_output({:stream, server}=x, data) do
    StreamServer.put_data(server, data)
    x
  end

  def process_port_output({:send, pid}=x, data) do
    send(pid, {self(), :data, data})
    x
  end

  def process_port_output({:into, _, server}=x, data) do
    StreamServer.put_data(server, data)
    x
  end

  def process_port_output(coll, data) do
    {:ok, server} = StreamServer.start()
    parent = self()
    spawn(fn ->
      ret = Enum.into(Stream.unfold(server, &read_stream/1), coll)
      send(parent, {:into, ret, server})
    end)
    process_port_output({:into, coll, server}, data)
  end

  defp flatten(thing) do
    case thing do
      {:string, data}    -> IO.iodata_to_binary(data)
      {:iodata, data}    -> data
      {:path, path, fid} -> File.close(fid); {:path, path}
      {:stream, server}  -> StreamServer.finish(server)
      {:into, _, server} ->
        StreamServer.finish(server)
        receive do
          {:into, ret, ^server} -> ret
        end
      other -> other
    end
  end
end
