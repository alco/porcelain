ExUnit.start

defmodule TestUtil do
  def fixture_path(name) do
    Path.join([__DIR__, "fixtures", name])
  end
end
