local M = {}

M.setup = function(opts)
  local keybind  = (opts and opts.keybind)  or "cmd+b"
  local terminal = (opts and opts.terminal) or "com.superlogical.terminal"
  rex.action({
    name     = "bitwarden",
    title    = "Bitwarden",
    keywords = "bitwarden password picker vault",
    run = function()
      local _, err = rex.session.new_layer({
        bounds = { 0.05, 0.05, 0.9, 0.9 },
        layout = rex.layout.block({
          flavor  = terminal .. ".shell",
          options = { command = { os.getenv("HOME") .. "/.config/rex/rex-bitwarden/bw.sh" } },
        }),
        focus = true,
      })
      if err then error(err) end
    end,
  })
  rex.bind(keybind, "bitwarden")
end

return M
