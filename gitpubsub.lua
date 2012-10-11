--[[
    GitPubSub: A subscribable Git commit notification server.
    Not nearly as awesome as SvnPubSub, but it works...
]]--

--[[ External dependencies ]]--
local JSON = require "JSON" -- JSON: http://regex.info/code/JSON.lua
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
local master -- the master socket
local SENT = 0
local RECEIVED = 0
local START = os.time()
local greeting = "HTTP/1.1 OK\r\nServer: GitPubSub/0.5\r\n"

if rootFolder then
    lfs = require "lfs"
end

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
                local output = JSON:encode({commit=commit})
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
            local output = JSON:encode({commit=commit})
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
            local output = JSON:encode({commit=commit})
            table.insert(backlog, output)
        end
    end
    return backlog
end


--[[ closeConn: Close a connection and remove reference ]]--
function closeConn(who)
    for k, child in pairs(subscribers) do
        if who == child then
            subscribers[k] = nil
            child:close()
            return
        end
    end
end

--[[ cwrite: Write to one or more sockets, close them if need be ]]--
function cwrite(who, what) 
    if type(who) == "userdata" then
        who = {who}
    end
    local s = what:len() + 2
    for k, child in pairs(who) do
        if child then
            local x = child:send(what .. "\r\n")
            SENT = SENT + s
            if x == nil then
                closeConn(child)
            end
        end
    end
end

--[[ Function for scanning Git repos ]]--
function updateGit(force)
    if rootFolder then
        for repo in lfs.dir(rootFolder) do
            if repo:match(criteria) then
                local backlog = checkGit(rootFolder .. "/" .. repo, repo)
                for k, line in pairs(backlog) do
                    cwrite(subscribers, line..",")
                end
            end
        end
    end
end

--[[ The usual 'stillalive' message sent to clients ]]--
function ping(t)
   cwrite(subscribers, ("{\"stillalive\": %u},"):format(t))
end

--[[ Server event loop ]]--
function eventLoop()
    local child = master:accept()
    if child then
        createChild(child)
    end
    readRequests()
    checkJSON()
    local t = os.time()
    if (t - latestPing) >= 5 then
        latestPing = t
        updateGit()
        ping(t)
    end
end

function upRec(line)
    if line then
        RECEIVED = RECEIVED + line:len()
    end
end


function checkJSON()
    for k, child in pairs(waitingForJSON) do
        if child then
            local rl, err = child.socket:receive("*l")
            if rl then 
                upRec(rl)
                local arr = pcall(function() return JSON:decode(rl) end)
                if arr then
                    cwrite(subscribers, rl .. ",")
                end
                child.socket:close()
                waitingForJSON[k] = nil
                child.socket:send(greeting)
                child.socket:send("\r\n")
                SENT = SENT + (select(2, child.socket:getstats()) or 0)
                child.socket:close()
            elseif err == "closed" then
                child.socket:close()
                waitingForJSON[k] = nil
            end
        end
    end
end

function processChildRequest(child)
    if child.action == "GET" then
        child.socket:send(greeting)
        child.socket:send("\r\n")
        SENT = SENT + (select(2, child.socket:getstats()) or 0)
        table.insert(subscribers, child.socket)
    elseif child.action == "HEAD" then
        child.socket:send(greeting)
        local uptime = os.time() - START
        local y = 0
        for k, v in pairs(subscribers) do y = y + 1 end
        child.socket:send( ("X-Uptime: %u\r\nX-Connections: %u\r\nX-Total-Connections: %u\r\nX-Received: %u\r\nX-Sent: %u\r\n\r\n"):format(uptime, y, X, RECEIVED, SENT) )
        SENT = SENT + (select(2, child.socket:getstats()) or 0)
        child.socket:close()
    elseif child.action == "POST" then
        if child.trusted then
            table.insert(waitingForJSON, child)
        end
    end
end

--[[ Check if a client has provided request header data ]]--
function readRequests()
    for k, child in pairs(presubscribers) do
        if child then
            local rl, err = child.socket:receive("*l")
            if rl then 
                upRec(rl)
                if rl:len() == 0 then
                    processChildRequest(child)
                    presubscribers[k] = nil
                else
                    if not child.action then
                        local action, uri = rl:match("^(%S+) (.-) HTTP/1.%d$")
                        if not action or not uri then
                            child.socket:send("HTTP/1.1 400 Bad request\r\n\r\nBad request sent!")
                            child.socket:close()
                            presubscribers[k] = nil
                        else
                            child.action = action:upper()
                            child.uri = uri
                        end
                    end
                end
            elseif err == "closed" then
                presubscribers[k] = nil
                child.socket:close()
            end
        end
    end
end

--[[ Initial client creation ]]--
function createChild(socket)
    X = X + 1
    socket:settimeout(0)
    local ip = socket.getpeername and socket:getpeername() or "?.?.?.?"
    local obj = { 
        ip = ip,
        socket = socket, 
        trusted = false,
        URI = nil,
        action = nil
    }
    for k, tip in pairs(trustedPeers or {}) do
        if ip:match("^"..tip.."$") then
            obj.trusted = true
            break
        end
    end
    presubscribers[X] = obj
end



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

master:settimeout(0.01)
updateGit(true)

while true do
    eventLoop()
end
