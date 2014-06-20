ExUnit.start max_cases: 1, exclude: :localbin

defmodule TestUtil do
  def fixture_path(name) do
    Path.join([__DIR__, "fixtures", name])
  end
end
