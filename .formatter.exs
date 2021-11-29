[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "config/**/*.exs",
    "mix.exs"
  ],
  locals_without_parens: [
    assert_eventually: :*,
  ]
]
