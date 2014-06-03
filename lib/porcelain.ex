defmodule Porcelain do
  defmodule Result do
    defstruct [:status, :out, :err]
  end

  @doc """
  Takes a shell invocation and produces a tuple `{ cmd, args }` suitable for
  use in `exec()` and `spawn()` functions. The format of the invocation should
  conform to POSIX shell specification.

  TODO: define behaviour of env variables, pipes, redirects

  ## Examples

      iex> Porcelain.shplit(~s(echo "Multiple arguments" in one line))
      {"echo", ["Multiple arguments", "in", "one", "line"]}

  """
  def shplit(invocation) when is_binary(invocation) do
    case String.split(invocation, " ", global: false) do
      [cmd, rest] ->
        { cmd, split(rest) }
      [cmd] ->
        { cmd, [] }
    end
  end

  # This splits the list of arguments with the command name already stripped
  defp split(args) when is_binary(args) do
    String.split args, " "
  end

  @doc """
  Executes the command synchronously.
  """
  @spec exec(String.t, Keyword.t) :: %Result{}
  @spec exec({String.t, [String.t]}, Keyword.t) :: %Result{}

  def exec(cmdspec, options \\ [])

  def exec(cmd, options) when is_binary(cmd) do
    {common_opts, extra_opts} = compile_options(options)
    driver().exec_shell(cmd, common_opts, extra_opts)
  end

  def exec({cmd, args}, options)
    when is_binary(cmd) and is_list(args) and is_list(options)
  do
    {common_opts, extra_opts} = compile_options(options)
    driver().exec(cmd, args, common_opts, extra_opts)
  end

  #@file_block_size 1024

  #defp send_input(port, input) do
    #case input do
      #bin when is_binary(bin) and byte_size(bin) > 0 ->
        ##IO.puts "sending input #{bin}"
        #Port.command(port, input)

      #{:file, fid} ->
        #pipe_file(fid, port)

      #{:path, path} ->
        #File.open path, [:read], fn(fid) ->
          #pipe_file(fid, port)
        #end

      #_ -> nil
    #end
    ## Send EOF to indicate the end of input or no input
    #Port.command(port, "")
  #end

  ## Synchronous communication with a port
  #defp communicate(port, input, output, error) do
    #send_input(port, input)
    #collect_output(port, output, error)
  #end

  #defp pipe_file(fid, port) do
    #Stream.repeatedly(fn -> IO.read(fid, @file_block_size) end)
    #|> Stream.take_while(fn
      #:eof -> false
      #{:error, _} -> false
      #_ -> true
    #end)
    #|> Enum.each(&Port.command(port, &1))
  #end

  ## Runs in a recursive loop until the process exits
  #defp collect_output(port, output, error) do
    ##IO.puts "Collecting output"
    #receive do
      #{ ^port, {:data, <<?o, data :: binary>>} } ->
        ##IO.puts "Did receive out"
        #output = process_port_output(output, data, :stdout)
        #collect_output(port, output, error)

      #{ ^port, {:data, <<?e, data :: binary>>} } ->
        ##IO.puts "Did receive err"
        #error = process_port_output(error, data, :stderr)
        #collect_output(port, output, error)

      #{ ^port, {:exit_status, status} } ->
        #{ status, flatten(output), flatten(error) }

      ##{ ^port, :eof } ->
        ##collect_output(port, output, out_data, err_data, true, did_see_exit, status)
    #end
  #end

  #defp process_port_output(nil, _, _) do
    #raise RuntimeError, message: "Unexpected data on client's end"
  #end

  #defp process_port_output({ :buffer, out_data }, in_data, _) do
    #{:buffer, [out_data, in_data]}
  #end

  #defp process_port_output({ :file, fid }=a, in_data, _) do
    #:ok = IO.write fid, in_data
    #a
  #end

  #defp process_port_output({ :path, path}=a, in_data, _) do
    #{:ok, fid} = File.open(path, [:write])
    #process_port_output({ :path, a, fid }, in_data, nil)
  #end

  #defp process_port_output({ :append, path}=a, in_data, _) do
    #{:ok, fid} = File.open(path, [:append])
    #process_port_output({ :path, a, fid }, in_data, nil)
  #end

  #defp process_port_output({ :path, _, fid}=a, in_data, _) do
    #:ok = IO.write fid, in_data
    #a
  #end

  #defp process_port_output({ pid, ref }=a, in_data, type) when is_pid(pid) do
    #Kernel.send(pid, { ref, type, in_data })
    #a
  #end

  ## Takes the output which is a nested list of binaries and produces a single
  ## binary from it
  #defp flatten({:buffer, iolist}) do
    ##IO.puts "Flattening an io list #{inspect iolist}"
    #IO.chardata_to_string iolist
  #end

  #defp flatten({:path, a, fid}) do
    #:ok = File.close(fid)
    #a
  #end

  #defp flatten(other) do
    ##IO.puts "Flattening #{inspect other}"
    #other
  #end

  #@doc """
  #Spawn an external process and returns `Process` record ready for
  #communication.
  #"""
  #def spawn(cmdspec, options \\ [])

  #def spawn(cmd, options) when is_binary(cmd) do
    #spawn(shplit(cmd), options)
  #end

  #def spawn({ cmd, args }, options) when is_binary(cmd)
                                     #and is_list(args)
                                     #and is_list(options) do
    #{port, input, output, error} = init_port_connection(cmd, args, options)
    #proc = %Process{in: input, out: output, err: error}
    #parent = self
    #pid = Kernel.spawn(fn -> do_loop(port, proc, parent) end)
    ##Port.connect port, pid
    #{pid, port}
  #end

  #defp do_loop(port, proc=%Process{in: in_opt}, parent) do
    #Port.connect port, self
    #if in_opt != :pid do
      #send_input(port, in_opt)
    #end
    #exchange_data(port, proc, parent)
  #end

  #defp exchange_data(port, proc=%Process{in: input, out: output, err: error}, parent) do
    #receive do
      #{ ^port, {:data, <<?o, data :: binary>>} } ->
        ##IO.puts "Did receive out"
        #output = process_port_output(output, data, :stdout)
        #exchange_data(port, %{proc|out: output}, parent)

      #{ ^port, {:data, <<?e, data :: binary>>} } ->
        ##IO.puts "Did receive err"
        #error = process_port_output(error, data, :stderr)
        #exchange_data(port, %{proc|err: error}, parent)

      #{ ^port, {:exit_status, status} } ->
        #Kernel.send(parent, {self, %Process{status: status,
                                            #in: input,
                                            #out: flatten(output),
                                            #err: flatten(error)}})

      #{ :data, :eof } ->
        #Port.command(port, "")
        #exchange_data(port, proc, parent)

      #{ :data, data } when is_binary(data) ->
        #Port.command(port, data)
        #exchange_data(port, proc, parent)
    #end
  #end

  #defp port_options(options, cmd, args) do
    #flags = get_flags(options)
    ##[{:args, List.flatten([["run", "main.go"], flags, ["--"], [cmd | args]])},
    #all_args = List.flatten([flags, ["--"], [cmd | args]])
    #[{:args, all_args}, :binary, {:packet, 2}, :exit_status, :use_stdio, :hide]
  #end

  #defp get_flags(options) do
    #[
      #["-proto", "2l"],

      #case options[:out] do
        #nil  -> ["-out", ""]
        #:err -> ["-out", "err"]
        #_    -> []
      #end,

      #case options[:err] do
        #nil  -> ["-err", ""]
        #:out -> ["-err", "out"]
        #_    -> []
      #end
    #]
  #end

  #defp open_port(opts) do
    #goon = if File.exists?("goon") do
      #'goon'
    #else
      #:os.find_executable 'goon'
    #end
    #Port.open { :spawn_executable, goon }, opts
  #end

  ## Processes port options opens a port. Used in both call() and spawn()
  #defp init_port_connection(cmd, args, options) do
    #port = open_port(port_options(options, cmd, args))

    #input  = process_input_opts(options[:in])
    #output = process_output_opts(options[:out])
    #error  = process_error_opts(options[:err])

    #{ port, input, output, error }
  #end

  defp compile_options(options) do
    Enum.reduce(options, {[], []}, fn {name, val}, {good, bad} ->
      compiled = case name do
        :in  -> {:ok, compile_input_opt(val)}
        :out -> {:ok, compile_output_opt(val)}
        :err -> {:ok, compile_error_opt(val)}
        _    -> nil
      end
      case compiled do
        nil        -> {good, bad ++ [{name, val}]}
        {:ok, opt} -> {good ++ [{name, opt}], bad}
      end
    end)
  end

  defp compile_input_opt(opt) do
    case opt do
      nil                                  -> nil
      #:pid                                 -> :pid
      {:file, fid}=x when is_pid(fid)      -> x
      {:path, path}=x when is_binary(path) -> x
      bin when is_binary(bin)              -> bin
    end
  end

  defp compile_output_opt(opt) do
    compile_out_opt(opt, :err)
  end

  defp compile_error_opt(opt) do
    compile_out_opt(opt, :out)
  end

  defp compile_out_opt(opt, typ) do
    case opt do
      ^typ                                   -> nil
      nil                                    -> nil
      :buffer                                -> {:buffer, ""}
      {:file, fid}=x when is_pid(fid)        -> x
      {:path, path}=x when is_binary(path)   -> x
      {:append, path}=x when is_binary(path) -> x
      #{pid, ref} when is_pid(pid) -> { pid, ref }
    end
  end

  defp driver() do
    case :application.get_env(:porcelain, :driver) do
      :undefined -> Porcelain.Driver.Simple
      other -> other
    end
  end
end
