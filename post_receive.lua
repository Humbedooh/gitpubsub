#!/usr/bin/lua

local JSON = require "JSON"
local socket = require "socket"

local old = arg[1] or "??"
local new = arg[2] or "??"
local ref = arg[3] or "(master?)"

local commit = {repository="git", ref=ref}

local prog = io.popen("pwd")
local pwd = prog:read("*l")
prog:close()
local project = pwd:match("([^/]+)$") or "unknown"

local pipe = io.popen("git show --name-only " .. new or "??")
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

local out = JSON:encode({commit=commit})
print(out)

local f = io.open("test.txt", "w")
f:write("JSON:\n" .. out .. "\n")
f:close()

local s = socket.tcp()
s:settimeout(0.5)
local success, err = s:connect("127.0.0.1", 2069)
if not success then
    print("Failed to connect: ".. err .. "\n")
    os.exit()
end

print("Connected to gitpubsub")

while true do
    local line = s:receive("*l")
    if not line or line:len() == 0 then break end
end

s:send("POST /json HTTP/1.1\r\n")
s:send("Host: localhost\r\n\r\n")
s:send(out .."\r\n")
s:shutdown()
s:close()
print("All done!")

