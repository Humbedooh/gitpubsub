#!/usr/bin/lua

local json = false
local JSON = false
pcall(function() JSON = require "JSON" end) -- JSON: http://regex.info/code/JSON.lua
pcall(function() json = require "json" end) -- LuaJSON, if available
local socket = require "socket"
local lfs = false
pcall(function() lfs = require "lfs" end)

local old = arg[1]
local new = arg[2]
local ref = arg[3] or "(no ref)"

if not old or not new then
    print("Usage: post-receive [old] [new] [ref]")
    os.exit()
end

local commit = {repository="git", ref=ref}

local pwd = ""
if lfs then
    pwd = lfs.currentdir()
else
    local p = io.popen("pwd")
    if p then
        pwd = p:read("*l")
        p:close()
    end
end
local project = pwd:match("([^/]+)$") or "unknown"

local pipe = io.popen("git show --name-only " .. new)
commit.hash = new
commit.shortHash = commit.hash:sub(1,7)
commit.project = project

while true do
    local line = pipe:read("*l")
    if not line or line:len() == 0 then break end
    local key, val = line:match("^(%S+):%s+(.+)$")
    if key and val then
        key = key:lower()
        if key == "author" then
            local author, email = val:match("^(.-) <(.-)>$")
            commit.author = author or "(uknown)"
            commit.email = email or "(unknown)"
        else
            commit[key] = val
        end
    end
end

commit.log = ""
while true do
    local line = pipe:read("*l")
    if not line or line:len() == 0 then break end
    commit.log = commit.log .. line:gsub("^    ", "") .. "\n"
end

commit.log = commit.log:gsub("\n$", "")


commit.files = {}
while true do
    local line = pipe:read("*l")
    if not line or line:len() == 0 then break end
    table.insert(commit.files, line)
end

pipe:close()

if #commit.files == 1 then
    commit.changes = commit.files[1]
else
    commit.changes = #commit.files .. " files"
end


local output = ""
if JSON then 
    output = JSON:encode({commit=commit})
elseif json then
    output = json.encode({commit=commit})
end
print(output)
local s = socket.tcp()
s:settimeout(0.5)
local success, err = s:connect("127.0.0.1", 2069)
if not success then
    os.exit()
end

s:send("POST /json HTTP/1.1\r\n")
s:send("Host: localhost\r\n\r\n")
s:send(output .."\r\n")
s:shutdown()
s:close()

