defmodule Porcelain.Init do
  @moduledoc false

  alias Porcelain.Driver.Basic
  alias Porcelain.Driver.Goon

  def init() do
    driver = get_env(:driver)
    init(driver)
    init_shell()
  end

  def init(nil) do
    if path=find_goon() do
      set_driver(Goon, path)
    else
      IO.puts :stderr, "[Porcelain]: goon executable not found. Falling back to the basic driver"
      set_driver(Basic)
    end
  end

  def init(Goon) do
    if path=find_goon() do
      set_driver(Goon, path)
    else
      {:error, "goon executable not found"}
    end
  end

  def init(mod) when is_atom(mod), do: set_driver(mod)


  defp init_shell() do
    # Finding shell command logic from :os.cmd in OTP
    # https://github.com/erlang/otp/blob/8deb96fb1d017307e22d2ab88968b9ef9f1b71d0/lib/kernel/src/os.erl#L184
    case :os.type do
      {:unix, _} ->
        set_env(:shell_command, {'sh', ["-c"]})

      {:win32, osname} ->
        shell = case {System.get_env("COMSPEC"), osname} do
          {nil, :windows} -> 'command.com'
          {nil, _}        -> 'cmd'
          {cmd, _}        -> cmd
        end
        set_env(:shell_command, {shell, ["/c"]})
    end
  end


  defp get_env(key) do
    case :application.get_env(:porcelain, key) do
      :undefined -> nil
      {:ok, val} -> val
    end
  end

  defp set_driver(mod, state \\ nil) do
    set_env(:driver_internal, mod)
    set_env(:driver_state, state)
  end

  defp set_env(key, term) do
    :application.set_env(:porcelain, key, term)
  end

  defp find_goon() do
    cond do
      path=get_env(:goon_driver_path) ->
        path
      File.exists?("goon") ->
        Path.absname("goon")
      exe=:os.find_executable('goon') ->
        List.to_string(exe)
      true -> false
    end
  end
end
