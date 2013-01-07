--[[
    GitPubSub: A subscribable Git commit notification server.
    Not nearly as awesome as SvnPubSub, but it works...
]]--

--[[ External dependencies ]]--
local json = false
local JSON = false
pcall(function() JSON = require "JSON" end) -- JSON: http://regex.info/code/JSON.lua
pcall(function() json = require "json" end) -- LuaJSON, if available
local lfs = false -- LuaFileSystem
local socket = require "socket" -- Lua Sockets

--[[ General settings ]] --
local rootFolder = nil -- Where the git repos live. Set it to nil to disable scanning
local criteria = "%.git" -- folders that match this are scanned
local gitFolder = "" -- Set this to "./git" if needed
local trustedPeers = { "127.*" } -- a list of IP patterns we trust to make publications from the outside
local port = 2069 -- port to bind to (or path of unix domain socket to use)

--[[ Miscellaneous variables used throughout the process ]]--
local latestGit = 0 -- timestamp for latest git update
local latestPing = 0 -- timestamp for latest ping
local X = 0 -- number of connections server so far, used to keep track of open sockets
local subscribers = {} -- socket placeholder for connections we are broadcasting to
local presubscribers = {} -- socket placeholder for connections being set up
local waitingForJSON = {} -- socket placeholders for input
local gitRepos = {} -- git commit information array
local gitTags = {} -- git tag array
local gitBranches = {} -- git branch array
local master, maccept -- the master socket
local SENT = 0
local RECEIVED = 0
local START = os.time()
local TIME = START
local greeting = "HTTP/1.1 200 OK\r\nServer: GitPubSub/0.7\r\n"
local z = 0

--[[ function shortcuts ]]--
local time, tinsert, strlen, sselect = os.time, table.insert, string.len, socket.select

if rootFolder then
    lfs = require "lfs"
end

local readFrom = {}
local writeTo = {}
local requests = {}

--[[ 
    checkGit(file-path, project-name):
    Runs a scan of the git directory and produces JSON output for new commits, tags and branches.
]]--
function checkGit(repo, name)
    local backlog = {}
    local prg = io.popen(("git --git-dir %s%s log -n 20 --summary --tags --raw --date=raw --reverse --pretty=format:\"%%H|%%h|%%ct|%%aN|%%ae|%%s|%%d\" --all"):format(repo, gitFolder), "r")
    local data = prg:read("*a")
    prg:close()
    gitRepos[repo] = gitRepos[repo] or {lastCommit=-1}
    gitTags[repo] = gitTags[repo] or {}
    gitBranches[repo] = gitBranches[repo] or {}
    local repoData = gitRepos[repo]
    repoData.lastLog = data
    repoData.lastCommit = repoData.lastCommit or -1
    if getLast then repoData.lastCommit = repoData.lastCommit - 1 end
    local commits = {}
    local Xcommit = {files={}}
    for commit in data:gmatch("([^\r\n]+)") do
        local bigHash,hash,id,author,email,subject,refs = commit:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)")
        refs = (refs and refs:len() > 0) and refs or "origin/master"
        id = tonumber(id)
        if not id then
            Xcommit.files = Xcommit.files or {}
            if commit:match("^:") then 
                table.insert(Xcommit.files, commit:match("%s+%S%s+(.+)") or "(unknown file)")
            end
        else
            local ref = refs:match("([^%s/]+/[^%s/,]+)") or refs or "(nil)"
            ref = ref:gsub("^%(", ""):gsub("%)$", "")
            Xcommit = { repository="git",dirs_changed={name},project=name,big_hash=bigHash,hash=hash,timestamp=id,author=author,email=email,subject=subject,log=subject,ref=ref,files={},revision=hash}
            table.insert(commits, Xcommit)
        end
    end
    for k, commit in pairs(commits) do
        if commit.timestamp then
            if repoData.lastCommit < 0 then 
                repoData.lastCommit = commit.timestamp
            end
            if commit.author and commit.subject and commit.email and commit.timestamp > repoData.lastCommit then
                local mod = #commit.files .. " files"
                if #commit.files == 1 then mod = commit.files[1] end
                commit.changes = mod
                local output = ""
                if JSON then 
                    output = JSON:encode({commit=commit})
                elseif json then
                    output = json.encode({commit=commit})
                end
                table.insert(backlog, output)
            end
            if commit.timestamp >= repoData.lastCommit then repoData.lastCommit = commit.timestamp end
        end
    end

    -- tags
    local prg = io.popen(("git --git-dir %s%s tag"):format(repo, gitFolder), "r")
    local data = prg:read("*a")
    prg:close()
    for tag in data:gmatch("([^\r\n]+)") do
        local found = false
        for k, v in pairs(gitTags[repo]) do
            if v == tag then
                found = true
                break
            end
        end
        if not found then
            table.insert(gitTags[repo], tag)
            local prg = io.popen(("git --git-dir %s%s show \"%s\""):format(repo, gitFolder, tag), "r")
            local tagdata = prg:read("*a")
            prg:close()
            local tagger, email = tagdata:match("Tagger: (.-) <(.-)>")
            if not email then
                tagger, email = tagdata:match("Author: (.-) <(.-)>")
            end
            local commit = {
                author = tagger or "??",
                email = email or "??@??",
                log="New tag: " .. tag,
                dirs_changed = {name},
                files = "(prop-edit)",
                ref=tag,
                repository="git-prop-edit",
                revision = "",
                project=name
            }
            local output = ""
            if JSON then 
                output = JSON:encode({commit=commit})
            elseif json then
                output = json.encode({commit=commit})
            end

            table.insert(backlog, output)
        end
    end

    -- branches
    local prg = io.popen(("git --git-dir %s%s branch"):format(repo, gitFolder), "r")
    local data = prg:read("*a")
    prg:close()
    for tag in data:gmatch("([^\r\n]+)") do
        tag = tag:sub(3)
        local found = false
        for k, v in pairs(gitBranches[repo]) do
            if v == tag then
                found = true
                break
            end
        end
        if not found then
            table.insert(gitBranches[repo], tag)
            local prg = io.popen(("git --git-dir %s%s show \"%s\""):format(repo, gitFolder, tag), "r")
            local tagdata = prg:read("*a")
            prg:close()
            local tagger, email = tagdata:match("Tagger: (.-) <(.-)>")
            if not email then
                tagger, email = tagdata:match("Author: (.-) <(.-)>")
            end
            local commit = {
                author = tagger or "??",
                email = email or "??@??",
                log="New branch: " .. tag,
                dirs_changed = {name},
                files = "(prop-edit)",
                ref=tag,
                repository="git-prop-edit",
                revision = "",
                project=name
            }
            local output = ""
            if JSON then 
                output = JSON:encode({commit=commit})
            elseif json then
                output = json.encode({commit=commit})
            end
            table.insert(backlog, output)
        end
    end
    return backlog
end



--[[ cwrite: Write to one or more sockets, close them if need be ]]--
function cwrite(who, what, uri) 
    if type(who) == "userdata" then
        who = {who}
    end
    local request
    for k, socket in pairs(who) do
        if socket then
            request = requests[socket]
            if not uri or uri:match("^"..request.uri) then
                local len = string.format("%x", what:len() + 2)
                local x = socket:send(len .. "\r\n" .. what .. "\r\n\r\n")
                if x == nil then
                    closeSocket(socket)
                end
            end
        end
    end
end

--[[ Function for scanning Git repos ]]--
function updateGit()
    if rootFolder then
        for repo in lfs.dir(rootFolder) do
            if repo:match(criteria) then
                local backlog = checkGit(rootFolder .. "/" .. repo, repo)
                for k, line in pairs(backlog) do
                    cwrite(writeTo, line..",")
                end
            end
        end
    end
end

--[[ The usual 'stillalive' message sent to clients ]]--
function ping(t)
    local t = socket.gettime()
    cwrite(writeTo, ("{\"stillalive\": %f},"):format(t))
end

--[[ 
checkJSON:
    
    Waits for clients with a POST request to send JSON, and then transmits it
    to subscribers.
]]--
function checkJSON()
    local now = os.time()
    for k, child in pairs(waitingForJSON) do
        if child then
            local rl, err = child.socket:receive("*l")
            if rl then 
                local okay = false
                if JSON then 
                    okay = pcall(function() return JSON:decode(rl) end)
                elseif json then
                    okay = pcall(function() return json.decode(rl) end)
                end
                if okay then
                    cwrite(writeTo, rl .. ",", child.uri)
                    child.socket:send(greeting .."\r\nMessage sent!\r\n")
                else
                    child.socket:send("HTTP/1.1 400 Bad request\r\n\r\nInvalid JSON data posted :(\r\n")
                end
                waitingForJSON[k] = nil
                closeSocket(child.socket)
            elseif err == "closed" then
                closeSocket(child.socket)
                waitingForJSON[k] = nil
            elseif (now - child.putTime > 5) then
                child.socket:send("HTTP/1.1 400 Bad request\r\n\r\nRequest timed out :(\r\n")
                closeSocket(child.socket)
                waitingForJSON[k] = nil
            end
        end
    end
end

--[[ 
processChildRequest(child):
    
    Processes a request once the initial headers have been sent.
]]--
function processChildRequest(child)
    local socket = child.socket
    if child.action == "GET" then
        socket:send(greeting .. "Transfer-Encoding: chunked\r\nContent-Type: application/json\r\n\r\n")
        table.insert(writeTo, socket)
        for k, v in pairs(readFrom) do if v == socket then table.remove(readFrom, k) break end end
    elseif child.action == "HEAD" then
        local msg = greeting .. ("Content-Length: 0\r\nConnection: keep-alive\r\nX-Uptime: %u\r\nX-Connections: %u\r\nX-Total-Connections: %u\r\nX-Received: %u\r\nX-Sent: %u\r\n\r\n"):format(TIME - START, #readFrom + #writeTo, X, RECEIVED, SENT)
        socket:send(msg)
        if not child['Connection'] or child['Connection'] == "close" then
            closeSocket(socket)
        else
            child.action = nil
            return
        end
    elseif child.action == "PUT" then
        local ip = child.socket.getpeername and child.socket:getpeername() or "?.?.?.?"
        for k, tip in pairs(trustedPeers or {}) do
            if ip:match("^"..tip.."$") then
                child.trusted = true
                break
            end
        end
        if child.trusted then
            child.putTime = os.time()
            tinsert(waitingForJSON, child)
        else
            socket:send("HTTP/1.1 403 Denied\r\n\r\nOnly trusted sources may send data!")
            closeSocket(socket)
        end
    else
         socket:send("HTTP/1.1 400 Bad request!\r\n\r\nBad request :(\r\n")
         closeSocket(socket)       
    end
end

--[[ closeSocket: Closes a socket and removes it from the various socket arrays ]]--
function closeSocket(socket)
    local r,s = socket:getstats()
    SENT = SENT + s
    RECEIVED = RECEIVED + r
    socket:close()
    for k, v in pairs(readFrom) do if v == socket then table.remove(readFrom, k) break end end
    for k, v in pairs(writeTo) do if v == socket then table.remove(writeTo, k) break end end
    requests[socket] = nil
end

--[[ Check if a client has provided request header data ]]--
function readRequests()
    local request = nil
    local arr
    local t = time()
    while true do
        arr = sselect(readFrom, nil, 0.001)
        if arr and #arr > 0 then
            for k,socket in pairs(readFrom) do
                if type(socket) == "userdata" then
                    local rl, err = socket:receive("*l")
                    if rl then
                        z = z + 1
                        request = requests[socket]
                        request.ping = t
                        if #rl == 0 then
                            readFrom[k] = nil
                            processChildRequest(request)
                        else
                            if not request.action then
                                local action, uri = rl:match("^(%S+) (.-) HTTP/1.%d$")
                                if not action or not uri then
                                    socket:send("HTTP/1.1 400 Bad request\r\n\r\nBad request sent!")
                                    closeSocket(socket)
                                else
                                    request.action = action:upper()
                                    request.uri = uri
                                end
                            else
                                local key, val = rl:match("(%S+): (.?)")
                                request[key] = val
                            end
                        end
                    elseif err == "closed" then
                        closeSocket(socket)
                    end
                end
            end
        else
            coroutine.yield()
        end
    end
end

--[[ timeoutSockets: gathers up orphaned connections ]]--
function timeoutSockets()
    while true do
        local t = time()
        for k, socket in pairs(readFrom) do
            local request = requests[socket]
            if t - request.ping > 20 then
                closeSocket(socket)
            end
        end
        coroutine.yield()
    end
end

--[[ acceptChildren: Accepts new connections and initializes them ]]--
function acceptChildren()
    while true do
        local socket = maccept(master)
        if socket then
            X = X + 1
            requests[socket] = { socket = socket, ping = time() }
            tinsert(readFrom, socket)
            z = z + 1
            socket:settimeout(1)
        else
            coroutine.yield()
        end
    end
end

-- Wrap accept and read as coroutines
local accept = coroutine.wrap(acceptChildren)
local read = coroutine.wrap(readRequests)
local timeout = coroutine.wrap(timeoutSockets)


--[[ Actual server program starts here ]]--
if type(port) == "string" then
    socket.unix = require "socket.unix"
    master = socket.unix()
    master:setsockname(port)
    assert(master:listen())
elseif type(port) == "number" then
    master = socket.bind("*", port)
end
if not master then
    print("Could not bind to port "..port..", exiting")
    os.exit()
end

master:settimeout(0)
maccept = master.accept
updateGit()

--[[ Event loop ]]--
while true do
    z = 0
    accept()
    read()
    checkJSON()
    TIME = time()
    if (TIME - latestPing) >= 5 then
        latestPing = TIME
        updateGit()
        ping(TIME)
        timeout()
    end
    if #readFrom == 0 or z == 0 then
        socket.sleep(0.05)
    end
end
