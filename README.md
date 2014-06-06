Porcelain
=========

**The library is undergoing a revamp. Some things in this README are a lie**

Launch and communicate with external OS processes in Elixir without limitations
of Erlang ports. Porcelain builds on ports for easy integration, but provides
richer functionality and simple API for managing external processes.

Simply put, Porcelain removes the pain of dealing with ports and substitutes it
with happiness and peace of mind.


## Usage

Examples below show some of the common use cases. Refer to the API docs to
learn the complete set of provided functions and options.


### Launching one-off programs

If you need to launch an external program, feed it some input and capture its output and maybe also exit status, use `exec()` or `shell()`:

```elixir
alias Porcelain.Result

%Result{out: output, status: status} = Porcelain.shell("date")
IO.inspect status   #=> 0
IO.inspect output   #=> "Fri Jun  6 14:12:02 EEST 2014\n"

result = Porcelain.shell("date | cut -b 1-3")
IO.inspect result.out   #=> "Fri\n"

# Use exec() when you want launch a program directly without using a shell
File.write!("input.txt", "lines\nread\nfrom\nfile\n")
result = Porcelain.exec("sort", ["input.txt"])
IO.inspect result.out   #=> "file\nfrom\nlines\nread\n"
```


### Passing input and getting output

Porcelain gives you many options when it comes to interacting with external
processes. It is possible to feed input from a file or a stream, same for
output:

```elixir
File.write!("input.txt", """
  This file contains some patterns
  >like this<
  interspersed with other text
  ... >like this< the end.
  """)

Porcelain.exec("grep", [">like this<", "-m", "2"],
                    in: {:path, "input.txt"}, out: {:append, "output.txt"})
IO.inspect File.read!("output.txt")
#=> ">like this<\n... >like this< the end.\n"
```

Programs can be spawned asynchronously (using `spawn()` and `spawn_shell()`)
allowing for continuously exchaning data between Elixir and the external
process.

In the next example we will use streams for both input and output.

```elixir
alias Porcelain.Process

opts = [in: SocketStream.new('example.com', 80), out: :stream]
proc = %Process{out: outstream} = Porcelain.spawn("grep", ["div", "-m", "4"], opts)

IO.write(outstream)
#     div {
#         div {
# <div>
# </div>

Process.closed?(proc)   #=> true
```

The `SocketStream` module used above wraps a tcp socket in a stream. Its
implementation can be found in the `test/test_helper.exs` file.

By using streams we can chain multiple external processes together:

```elixir
alias Porcelain.Process

opts = [in: SocketStream.new('example.com', 80), out: :stream]
%Process{out: grep_stream} = Porcelain.spawn("grep", ["div", "-m", "4"], opts)

IO.inspect Porcelain.shell("head -n 4 | wc -l", in: grep_stream).out
```

**Caveat #1**: we are using `head` above in order to stop reading input after
the first 4 lines. Otherwise `wc` alone would wait indefenitily for EOF which
cannot be signaled when using bare Erlang ports. The (_currently not
implemented_) Goon driver fixes the issue.

**Caveat #2**: of course it would be more efficient to just use shell piping if
portability to non-POSIX systems isn't required.


## Accessing the underlying port


## Future work

TODO:
* mention wiki
* mention drivers

Porcelain relies on one external dependency to provide some of its features:
[goon](https://github.com/alco/goon). Get the binary for your OS and put it in
your application's working directory or somewhere in your `$PATH`.

In case `goon` is not found, Porcelain will fall back to the pure Elixir driver.


## License

This software is licensed under [the MIT license](LICENSE).
