local json = require("lunajson")
local http = require("atlas.http")
local socket = require("socket")
local function cache_dir()
  return ((os.getenv("HOME") or ".") .. "/.cache/atlas/tokens")
end
local function token_path(profile_name)
  return (cache_dir() .. "/" .. profile_name .. ".json")
end
local function shell_quote(s)
  return ("'" .. tostring(s):gsub("'", "'\\''") .. "'")
end
local function url_encode(s)
  local function _1_(c)
    return string.format("%%%02X", string.byte(c))
  end
  return tostring(s):gsub("[^%w%-%.%_%~]", _1_)
end
local function form_encode(t)
  local parts = {}
  for k, v in pairs(t) do
    table.insert(parts, (url_encode(k) .. "=" .. url_encode(v)))
  end
  return table.concat(parts, "&")
end
local function qs_append(base, params)
  return (base .. "?" .. form_encode(params))
end
local function expand_env(s)
  if ((type(s) == "string") and s:match("^env:(.+)")) then
    local var_name = s:match("^env:(.+)")
    return (os.getenv(var_name) or error(("environment variable not set: " .. var_name)))
  else
    return s
  end
end
local function sha256_base64url(s)
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if f then
    f:write(s)
    f:close()
    local h = io.popen(("openssl dgst -sha256 -binary " .. shell_quote(tmp) .. " | openssl base64 | tr '+/' '-_' | tr -d '='"))
    local result
    if h then
      local r = h:read("*l")
      h:close()
      result = r
    else
      result = nil
    end
    os.remove(tmp)
    if (result and (#result > 0)) then
      return result
    else
      return nil
    end
  else
    return nil
  end
end
local function random_string(n)
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  local nchars = #chars
  local out = {}
  local f = io.open("/dev/urandom", "rb")
  if f then
    for _ = 1, n do
      local byte = string.byte(f:read(1))
      local i = (1 + (byte % nchars))
      table.insert(out, chars:sub(i, i))
    end
    f:close()
  else
    math.randomseed(os.time())
    for _ = 1, n do
      local i = math.random(1, nchars)
      table.insert(out, chars:sub(i, i))
    end
  end
  return table.concat(out)
end
local function load_token(profile_name)
  local f = io.open(token_path(profile_name), "r")
  if f then
    local ok, data = pcall(json.decode, f:read("*a"))
    f:close()
    if (ok and data) then
      return data
    else
      return nil
    end
  else
    return nil
  end
end
local function save_token(profile_name, data)
  local dir = cache_dir()
  local path = token_path(profile_name)
  os.execute(("mkdir -p " .. shell_quote(dir) .. " && chmod 700 " .. shell_quote(dir)))
  local f = io.open(path, "w")
  if f then
    f:write(json.encode(data))
    f:close()
    return os.execute(("chmod 600 " .. shell_quote(path)))
  else
    return nil
  end
end
local function clear_token(profile_name)
  return os.remove(token_path(profile_name))
end
local function token_valid_3f(data)
  return (data and data.access_token and (not data.expires_at or (data.expires_at > (os.time() + 30))))
end
local function post_form(url, params, ssl)
  local body = form_encode(params)
  return http.request({method = "POST", url = url, headers = {["content-type"] = "application/x-www-form-urlencoded", accept = "application/json"}, ["raw-body"] = body, ssl = (ssl or {})})
end
local function store_token(resp, profile_name)
  local function _11_()
    local detail
    if (type(resp.body) == "table") then
      detail = (resp.body.error_description or resp.body.error or "")
    else
      detail = nil
    end
    local _12_
    if (detail and (#detail > 0)) then
      _12_ = (" \226\128\148 " .. detail)
    else
      _12_ = ""
    end
    return ("token request failed: HTTP " .. resp.status .. _12_)
  end
  assert(((resp.status >= 200) and (resp.status < 300)), _11_())
  local body
  if (type(resp.body) == "table") then
    body = resp.body
  else
    local ok, decoded = pcall(json.decode, resp.body)
    assert(ok, ("token response is not JSON: " .. tostring(resp.body)))
    body = decoded
  end
  local data = {access_token = body.access_token, token_type = (body.token_type or "Bearer")}
  if body.expires_in then
    data["expires_at"] = (os.time() + body.expires_in)
  else
  end
  if body.refresh_token then
    data["refresh_token"] = body.refresh_token
  else
  end
  save_token(profile_name, data)
  return data
end
local function try_refresh(profile_name, params, ssl, cached)
  local ok, resp = pcall(post_form, params.token_url, {grant_type = "refresh_token", refresh_token = cached.refresh_token, client_id = expand_env(params.client_id)}, ssl)
  if (ok and (resp.status >= 200) and (resp.status < 300)) then
    return store_token(resp, profile_name)
  else
    return nil
  end
end
local function client_credentials(profile_name, params, ssl)
  local form = {grant_type = "client_credentials", client_id = expand_env(params.client_id), client_secret = expand_env((params.client_secret or ""))}
  if params.scope then
    form["scope"] = params.scope
  else
  end
  if params.audience then
    form["audience"] = params.audience
  else
  end
  return store_token(post_form(params.token_url, form, ssl), profile_name)
end
local function open_browser(url)
  local h = io.popen("uname -s")
  local sys
  if h then
    local s = h:read("*l")
    h:close()
    sys = s
  else
    sys = "Linux"
  end
  local quoted = shell_quote(url)
  if (sys == "Darwin") then
    return os.execute(("open " .. quoted))
  else
    return os.execute(("xdg-open " .. quoted .. " 2>/dev/null &"))
  end
end
local function start_local_server(_3fport)
  local srv = socket.tcp()
  local ok_b, err_b = srv:bind("127.0.0.1", (_3fport or 0))
  assert(ok_b, ("OAuth callback bind failed: " .. tostring(err_b)))
  local ok_l, err_l = srv:listen(1)
  assert(ok_l, ("OAuth callback listen failed: " .. tostring(err_l)))
  local _, port = srv:getsockname()
  return srv, port
end
local function wait_for_callback(srv, expected_state)
  srv:settimeout(120)
  local client, err = srv:accept()
  assert(client, ("OAuth callback timed out: " .. tostring(err)))
  client:settimeout(10)
  local first = client:receive("*l")
  local line = client:receive("*l")
  while (line and (#line > 2)) do
    line = client:receive("*l")
  end
  if not first then
    client:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
    client:close()
    srv:close()
    return error("malformed OAuth callback request")
  else
    local path = first:match("GET (%S+) ")
    if not path then
      client:send("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
      client:close()
      srv:close()
      return error("malformed OAuth callback request")
    else
      local code = path:match("[?&]code=([^&]+)")
      local state = path:match("[?&]state=([^&]+)")
      client:send(("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n" .. "<html><body><h1>Authentication successful.</h1>" .. "<p>You can close this tab.</p></body></html>"))
      client:close()
      srv:close()
      assert(code, "no authorization code in callback")
      assert((state == expected_state), "OAuth state mismatch \226\128\148 possible CSRF")
      return code
    end
  end
end
local function authorization_code(profile_name, params, ssl)
  local srv, port = start_local_server(params.redirect_port)
  local redirect_host = (params.redirect_host or "127.0.0.1")
  local redirect_uri = ("http://" .. redirect_host .. ":" .. port .. (params.redirect_path or "/callback"))
  local state = random_string(16)
  local code_verifier = random_string(64)
  local code_challenge = sha256_base64url(code_verifier)
  local auth_params = {response_type = "code", client_id = expand_env(params.client_id), redirect_uri = redirect_uri, state = state, scope = (params.scope or "")}
  if (code_challenge and (#code_challenge > 0)) then
    auth_params["code_challenge"] = code_challenge
    auth_params["code_challenge_method"] = "S256"
  else
  end
  local auth_url = qs_append(params.authorize_url, auth_params)
  io.stderr:write("Opening browser for authentication...\n")
  io.stderr:write(("If browser does not open, visit:\n" .. auth_url .. "\n"))
  open_browser(auth_url)
  local code = wait_for_callback(srv, state)
  local form = {grant_type = "authorization_code", code = code, redirect_uri = redirect_uri, client_id = expand_env(params.client_id)}
  if params.client_secret then
    form["client_secret"] = expand_env(params.client_secret)
  else
  end
  if (code_challenge and (#code_challenge > 0)) then
    form["code_verifier"] = code_verifier
  else
  end
  return store_token(post_form(params.token_url, form, ssl), profile_name)
end
local function run_external(params, stdin_json)
  assert(params.commandline, "external-tool auth requires params.commandline")
  local cmd
  if stdin_json then
    local tmp = os.tmpname()
    local f = io.open(tmp, "w")
    assert(f, "failed to write external tool input")
    f:write(stdin_json)
    f:close()
    local c = ("/bin/sh -c " .. shell_quote((params.commandline .. " < " .. shell_quote(tmp))))
    cmd = c
  else
    cmd = ("/bin/sh -c " .. shell_quote(params.commandline))
  end
  local h = io.popen(cmd)
  assert(h, "failed to start external auth command")
  local out = h:read("*a")
  h:close()
  return out
end
local function external_bearer(params)
  local out = run_external(params, nil):match("^%s*(.-)%s*$")
  assert((out and (#out > 0)), "external auth command produced no output")
  return {authorization = ("Bearer " .. out)}
end
local function external_signing_headers(params, req)
  local body
  if not params.omitbody then
    body = (req.body or "")
  else
    body = nil
  end
  local payload = json.encode({method = (req.method or "GET"), uri = req.url, headers = (req.headers or {}), body = body})
  local raw = run_external(params, payload)
  if (raw and (#raw > 0)) then
    local ok, result = pcall(json.decode, raw)
    if (ok and result and result.headers) then
      return result.headers
    else
      return nil
    end
  else
    return nil
  end
end
local function authenticate(profile_name, auth_config, ssl)
  local params = auth_config.params
  local case_31_ = auth_config.name
  if (case_31_ == "oauth-authorization-code") then
    return authorization_code(profile_name, params, ssl)
  elseif (case_31_ == "oauth-client-credentials") then
    return client_credentials(profile_name, params, ssl)
  else
    local _ = case_31_
    return error(("unsupported auth type: " .. auth_config.name))
  end
end
local function ensure_token(profile_name, auth_config, ssl)
  local cached = load_token(profile_name)
  if token_valid_3f(cached) then
    return cached.access_token
  else
    local data
    if (cached and cached.refresh_token) then
      io.stderr:write("Refreshing token...\n")
      data = (try_refresh(profile_name, auth_config.params, ssl, cached) or authenticate(profile_name, auth_config, ssl))
    else
      data = authenticate(profile_name, auth_config, ssl)
    end
    return data.access_token
  end
end
local function get_headers(profile_name, auth_config, ssl)
  local case_35_ = auth_config.name
  if (case_35_ == "external-tool") then
    local _37_
    do
      local t_36_ = auth_config
      if (nil ~= t_36_) then
        t_36_ = t_36_.params
      else
      end
      if (nil ~= t_36_) then
        t_36_ = t_36_.output
      else
      end
      _37_ = t_36_
    end
    if (_37_ == "bearer-token") then
      return external_bearer(auth_config.params)
    else
      return {}
    end
  else
    local _ = case_35_
    return {authorization = ("Bearer " .. ensure_token(profile_name, auth_config, ssl))}
  end
end
local function wrap_http_fn(auth_config, base_fn)
  local and_42_ = (auth_config.name == "external-tool")
  if and_42_ then
    local _44_
    do
      local t_43_ = auth_config
      if (nil ~= t_43_) then
        t_43_ = t_43_.params
      else
      end
      if (nil ~= t_43_) then
        t_43_ = t_43_.output
      else
      end
      _44_ = t_43_
    end
    and_42_ = (_44_ ~= "bearer-token")
  end
  if and_42_ then
    local params = auth_config.params
    local function _47_(req)
      local extra = external_signing_headers(params, req)
      if extra then
        local headers = (req.headers or {})
        for k, vs in pairs(extra) do
          local _48_
          if (type(vs) == "table") then
            _48_ = vs[1]
          else
            _48_ = vs
          end
          headers[k] = _48_
        end
        req["headers"] = headers
      else
      end
      return base_fn(req)
    end
    return _47_
  else
    return nil
  end
end
return {["get-headers"] = get_headers, ["wrap-http-fn"] = wrap_http_fn, authenticate = authenticate, ["clear-token"] = clear_token}
