defmodule Porcelain do
  @moduledoc """
  The main module exposing the public API of Porcelain.

  ## Basic concepts

  Functions in this module can either spawn external programs directly
  (`exec/3` and `spawn/3`) or using a system shell (`shell/2` and
  `spawn_shell/2`).

  Functions `exec/3` and `shell/2` are synchronous (or blocking), meaning they
  don't return until the external program terminates.

  Functions `spawn/3` and `spawn_shell/2` are non-blocking: they immediately
  return a `Porcelain.Process` struct and use one of the available ways to
  exchange input and output with the external process asynchronously.

  ## Error handling

  Using undefined options, passing invalid values to options or any function
  arguments will fail with a function clause error or `Porcelain.UsageError`
  exception. Those are programmer errors and have to be fixed.

  Any other kinds of runtime errors are reported by returning an error tuple:
  `{:error, <reason>}` where `<reason>` is a string explaining the error.
  """


  defmodule Result do
    @moduledoc """
    A struct containing the result of running a program after it has
    terminated.
    """

    defstruct [:status, :out, :err]
    @type t :: %__MODULE__{}
  end


  @doc ~S"""
  Execute a program synchronously.

  Porcelain will look for the program in PATH and launch it directly, passing
  the `args` list as command-line arguments to it.

  Feeds all input into the program (synchronously or concurrently with reading
  output; see `:async_in` option below) and waits for it to terminate. Returns
  a `Porcelain.Result` struct containing program's output and exit status code.

  When no options are passed, the following defaults will be used:

      [in: "", out: :string, err: nil]

  This will run the program with no input and will capture its standard output.

  Available options:

    * `:in` – specify the way input will be passed to the program.

      Possible values:

      - `<iodata>` – the data is fed into stdin as the sole input for the
        program

      - `<stream>` – interprets `<stream>` as a stream of iodata to be fed into
        the program

      - `{:path, <string>}` – path to a file to be fed into stdin

      - `{:file, <file>}` – `<file>` is a file descriptor obtained from e.g.
        `File.open`; the file will be read from the current position until EOF

    * `:async_in` – can be `true` or `false` (default). When enabled, an
      additional process will be spawned to feed input to the program
      concurrently with receiving output.

    * `:out` – specify the way output will be passed back to Elixir.

      Possible values:

      - `nil` – discard the output

      - `:string` (default) – the whole output will be accumulated in memory
        and returned as one string to the caller

      - `:iodata` – the whole output will be accumulated in memory and returned
        as iodata to the caller

      - `{:path, <string>}` – the file at path will be created (or truncated)
        and the output will be written to it

      - `{:append, <string>}` – the output will be appended to the the file at
        path (it will be created first if needed)

      - `{:file, <file>}` – `<file>` is a file descriptor obtained from e.g.
        `File.open`; the file will be written to starting at the current
        position

      - `<coll>` – feeds program output (as iodata) into the collectable
        `<coll>`. Useful for outputting directly to the console, for example:

              stream = IO.binstream(:standard_io, :line)
              exec("echo", ["hello", "world"], out: stream)
              #=> prints "hello\nworld\n" to stdout

    * `:err` – specify the way stderr will be passed back to Elixir.

      Possible values are the same as for `:out`. In addition, it accepts the
      atom `:out` which denotes redirecting stderr to stdout.

      **Caveat**: when using `Porcelain.Driver.Basic`, the only supported
      values are `nil` (stderr will be printed to the terminal) and `:out`.

    * `:dir` – takes a path that will be used as the directory in which the
      program will be launched.

    * `:env` – set additional environment variables for the program. The value
      should be an enumerable with elements of the shape `{<key>, <val>}` where
      `<key>` is an atom or a binary and `<val>` is a binary or `false`
      (meaning removing the corresponding variable from the environment).
      Basically, it accepts any kind of dict, including keyword lists.

  """
  @spec exec(binary, [binary])            :: Porcelain.Result.t
  @spec exec(binary, [binary], Keyword.t) :: Porcelain.Result.t

  def exec(prog, args, options \\ [])
        when is_binary(prog) and is_list(args) and is_list(options)
  do
    catch_throws fn ->
      driver().exec(prog, args, compile_exec_options(options))
    end
  end


  @doc """
  Execute a shell invocation synchronously.

  This function will launch a system shell and pass the invocation to it. This
  allows using shell features like chaining multiple programs with pipes. The
  downside is that those advanced features may be unavailable on some
  platforms.

  It is similar to the `exec/3` function in all other respects.
  """
  @spec shell(binary)            :: Porcelain.Result.t
  @spec shell(binary, Keyword.t) :: Porcelain.Result.t

  def shell(cmd, options \\ []) when is_binary(cmd) and is_list(options) do
    catch_throws fn ->
      driver().exec_shell(cmd, compile_exec_options(options))
    end
  end


  @doc """
  Spawn an external process and return a `Porcelain.Process` struct to be able
  to communicate with it.

  You have to explicitly stop the process after reading its output or when it
  is no longer needed.

  Use the `Porcelain.Process.await/2` function to wait for the process to
  terminate.

  Supports all options defined for `exec/3` plus some additional ones:

    * `in: :receive` – input is expected to be sent to the process in chunks
      using the `Porcelain.Process.send_input/2` function.

    * `:out` and `:err` can choose from a few more values (with the familiar
      caveat that `Porcelain.Driver.Basic` does not support them for `:err`):

        - `:stream` – the corresponding field of the returned `Process` struct
          will contain a stream of iodata.

          Note that the underlying port implementation is message based. This
          means that the external program will be able to send all of its
          output to an Elixir process and terminate. The data will be kept in
          the Elixir process's memory until the stream is consumed.

        - `{:send, <pid>}` – send the output to the process denoted by `<pid>`.
          Will send zero or more data messages and will always send one result
          message in the end.

          The data messages have the following shape:

               {<from>, :data, :out | :err, <iodata>}

          where `<from>` will be the same pid as the one contained in the
          `Process` struct returned by this function.

          The result message has the following shape:

               {<from>, :result, %Porcelain.Result{} | nil}

          The result will be `nil` if the `:result` option that is passed to
          this function is set to `:discard`.

          **Note**: if both `:out` and `:err` are set up to send to the same
          pid, only one result message will be sent to that pid in the end.

    * `:result` – specify how the result of the external program should be
    returned after it has terminated.

      This option has a smart default value. If either `:out` or `:err` option
      is set to `:string` or `:iodata`, `:result` will be set to `:keep`.
      Otherwise, it will be set to `:discard`.

      Possible values:

      * `:keep` – the result will be kept in memory until requested by calling
        `Porcelain.Process.await/2` or discarded by calling
        `Porcelain.Process.stop/1`.

      * `:discard` – discards the result and automatically closes the port
        after program termination. Useful in combination with `out: :stream`
        and `err: :stream`.

  """
  @spec spawn(binary, [binary])            :: Porcelain.Process.t
  @spec spawn(binary, [binary], Keyword.t) :: Porcelain.Process.t

  def spawn(prog, args, options \\ [])
    when is_binary(prog) and is_list(args) and is_list(options)
  do
    catch_throws fn ->
      driver().spawn(prog, args, compile_spawn_options(options))
    end
  end


  @doc """
  Spawn a system shell and execute the command in it.

  Works similar to `spawn/3`.
  """
  @spec spawn_shell(binary)            :: Porcelain.Process.t
  @spec spawn_shell(binary, Keyword.t) :: Porcelain.Process.t

  def spawn_shell(cmd, options \\ [])
        when is_binary(cmd) and is_list(options)
  do
    catch_throws fn ->
      driver().spawn_shell(cmd, compile_spawn_options(options))
    end
  end


  @doc """
  Reruns the initialization and updates application env.

  This function is useful in the following cases:

    1. The currently used driver is Goon and the location of the goon
    executable has changed.

    2. You want to change the driver being used.

  """
  def reinit(driver \\ nil) do
    if driver do
      Porcelain.Init.init(driver)
    else
      Porcelain.Init.init()
    end
  end

  ###

  defp catch_throws(fun) do
    try do
      fun.()
    catch
      :throw, thing -> {:error, thing}
    end
  end


  defp compile_exec_options(options) do
    {good, bad} = Enum.reduce(options, {[], []}, fn {name, val}, {good, bad} ->
      case compile_exec_opt(name, val) do
        nil        -> {good, bad ++ [{name, val}]}
        {:ok, opt} -> {good ++ [{name, opt}], bad}
      end
    end)
    {apply_exec_defaults(options, good), bad}
  end

  defp compile_exec_opt(name, val) do
    case name do
      :in  -> compile_input_opt(val)
      :out -> compile_output_opt(val)
      :err -> compile_error_opt(val)
      :env -> compile_env_opt(val)
      :dir when is_binary(val) ->
        {:ok, val}
      :async_in when val in [true, false] ->
        {:ok, val}
      _ -> nil
    end
  end

  defp apply_exec_defaults(options, good) do
    if Keyword.has_key?(options, :out) do
      good
    else
      Keyword.put(good, :out, {:string, ""})
    end
  end


  defp compile_spawn_options(options) do
    {good, bad} = compile_exec_options(options)
    {good, bad} = Enum.reduce(bad, {good, []}, fn opt, {good, bad} ->
      case compile_spawn_opt(opt) do
        :ok -> {good ++ [opt], bad}
        nil -> {good, bad ++ [opt]}
      end
    end)
    {apply_spawn_defaults(options, good), bad}
  end

  defp compile_spawn_opt(opt) do
    case opt do
      {:in, :receive}     -> :ok
      {:out, :stream}     -> :ok
      {:out, {:send, pid}} when is_pid(pid) ->
        :ok
      {:err, :stream}     -> :ok
      {:err, {:send, pid}} when is_pid(pid) ->
        :ok
      {:result, :keep}    -> :ok
      {:result, :discard} -> :ok
      _ -> nil
    end
  end

  defp apply_spawn_defaults(options, good) do
    if Keyword.has_key?(options, :result) do
      good
    else
      default =
        if keep_result?(good[:out]) or keep_result?(good[:err]) do
          :keep
        else
          :discard
        end
      Keyword.put(good, :result, default)
    end
  end

  defp keep_result?({:string, _}), do: true
  defp keep_result?({:iodata, _}), do: true
  defp keep_result?({:send, _}), do: true
  defp keep_result?(_), do: false


  defp compile_input_opt(opt) do
    result = case opt do
      nil                                              -> nil
      {:file, _}=x                                     -> x
      {:path, path}=x when is_binary(path)             -> x
      iodata when is_binary(iodata) or is_list(iodata) -> iodata
      other ->
        if Enumerable.impl_for(other), do: other, else: :badval
    end
    if result != :badval, do: {:ok, result}
  end

  defp compile_output_opt(opt) do
    compile_out_opt(opt, nil)
  end

  defp compile_error_opt(opt) do
    compile_out_opt(opt, :out)
  end

  defp compile_out_opt(opt, typ) do
    result = case opt do
      ^typ                                   -> typ
      nil                                    -> nil
      :string                                -> {:string, ""}
      :iodata                                -> {:iodata, ""}
      {:file, _}=x                           -> x
      {:path, path}=x when is_binary(path)   -> x
      {:append, path}=x when is_binary(path) -> x
      coll ->
        if Collectable.impl_for(coll), do: coll, else: :badval
    end
    if result != :badval, do: {:ok, result}
  end

  defp compile_env_opt(val) do
    {vars, ok?} = Enum.map_reduce(val, true, fn
      {name, val}, ok? when (is_binary(name) or is_atom(name))
                        and (is_binary(val) or val == false) ->
        {{convert_env_name(name), convert_env_val(val)}, ok?}
      other, _ -> {other, false}
    end)
    if ok?, do: {:ok, vars}
  end

  defp convert_env_name(name) when is_binary(name),
    do: String.to_char_list(name)

  defp convert_env_name(name) when is_atom(name),
    do: Atom.to_char_list(name)

  defp convert_env_val(false), do: false

  defp convert_env_val(bin), do: String.to_char_list(bin)


  defp driver() do
    case Application.fetch_env(:porcelain, :driver_internal) do
      {:ok, mod} -> mod
      _ ->
        raise Porcelain.UsageError, message: "Looks like the :porcelain app is not running. " <>
          "Make sure you've added :porcelain to the list of applications in your mix.exs."
    end
  end
end
