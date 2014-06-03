defmodule Porcelain.Driver.Simple do
  @moduledoc """
  Porcelain driver that offers basic functionality for interacting with
  external programs.

  Some of the provided features:

    * spawn one-off or long-running programs
    * add external programs to Elixir's supervision trees
    * balance between multiple instances of external program
    * specify maximum number of program instances allowed
    * rate limiting of input and output

  """

  @common_port_options [:binary, :stream, :exit_status, :use_stdio, :hide]

  def exec(cmd, args, opts, extra_opts) do
    opts = compile_options(opts, extra_opts)
    exe = :os.find_executable(:erlang.binary_to_list(cmd))
    port = Port.open({:spawn_executable, exe},
                     port_options(:proc, args, opts))
    communicate(port, opts[:in], opts[:out], opts[:err])
  end

  def exec_shell(cmd, opts, extra_opts) do
    opts = compile_options(opts, extra_opts)
    port = Port.open({:spawn, cmd}, port_options(:shell, opts))
    communicate(port, opts[:in], opts[:out], opts[:err])
  end

  defp compile_options(opts, []) do
    opts
  end

  defp compile_options(_opts, extra_opts) do
    raise RuntimeError, message: "Undefined options: #{inspect extra_opts}"
  end

  defp port_options(:proc, args, _opts),
    do: [{:args, args} | @common_port_options]

  defp port_options(:shell, _opts),
    do: @common_port_options


  # Synchronous communication with port
  defp communicate(port, input, output, error) do
    send_input(port, input)
    collect_output(port, output, error)
  end

  defp send_input(port, input) do
    case input do
      bin when is_binary(bin) and byte_size(bin) > 0 ->
        #IO.puts "sending input #{bin}"
        Port.command(port, input)

      {:file, fid} ->
        pipe_file(fid, port)

      {:path, path} ->
        File.open path, [:read], fn(fid) ->
          pipe_file(fid, port)
        end

      _ -> nil
    end
  end

  # we read files in blocks to avoid excessive memory usage
  @file_block_size 1024*1024

  defp pipe_file(fid, port) do
    Stream.repeatedly(fn -> IO.read(fid, @file_block_size) end)
    |> Stream.take_while(fn
      :eof -> false
      {:error, _} -> false
      _ -> true
    end)
    |> Enum.each(&Port.command(port, &1))
  end

  defp collect_output(port, output, error) do
    #IO.puts "Collecting output"
    receive do
      { ^port, {:data, data} } ->
        #IO.puts "Did receive out"
        output = process_port_output(output, data)
        collect_output(port, output, error)

      { ^port, {:exit_status, status} } ->
        %Porcelain.Result{
          status: status,
          out: flatten(output),
          err: flatten(error)
        }
    end
  end


  defp flatten(nil),  do: nil
  defp flatten({:buffer, data}), do: IO.iodata_to_binary(data)
  defp flatten(other), do: other


  defp process_port_output(nil, _) do
    nil
    #raise RuntimeError, message: "Unexpected data on client's end"
  end

  defp process_port_output({:buffer, data}, new_data) do
    {:buffer, [data, new_data]}
  end

  defp process_port_output({:file, fid}=x, new_data) do
    :ok = IO.write(fid, new_data)
    x
  end

  defp process_port_output({:path, path}, new_data) do
    {:ok, fid} = File.open(path, [:write])
    process_port_output({:path, path, fid}, new_data)
  end

  defp process_port_output({:append, path}, new_data) do
    {:ok, fid} = File.open(path, [:append])
    process_port_output({:path, path, fid}, new_data)
  end

  defp process_port_output({:path, _, fid}=x, data) do
    :ok = IO.write(fid, data)
    x
  end

  #defp process_port_output({ pid, ref }=a, in_data, type) when is_pid(pid) do
    #Kernel.send(pid, { ref, type, in_data })
    #a
  #end
end
