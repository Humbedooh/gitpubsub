--[[
    GitPubSub: A subscribable Git commit notification server.
    Not nearly as awesome as SvnPubSub, but it works...
]]--

--[[ External dependencies ]]--
local JSON = require "JSON" -- JSON: http://regex.info/code/JSON.lua
local lfs = require "lfs" -- LuaFileSystem
local socket = require "socket" -- Lua Sockets

--[[ General settings ]] --
local rootFolder = "/var/git" -- Where the git repos live
local criteria = "%.git" -- folders that match this are scanned
local trustedPeers = { ".+" } -- a list of IP patterns we trust to make publications from the outside

--[[ Miscellaneous variables used throughout the process ]]--
local latestGit = 0 -- timestamp for latest git update
local latestPing = 0 -- timestamp for latest ping
local X = 0 -- number of connections server so far, used to keep track of open sockets
local connections = {} -- socket placeholder
local gitRepos = {} -- git commit information array
local gitTags = {} -- git tag array
local gitBranches = {} -- git branch array
local master -- the master socket


--[[ 
    checkGit(file-path, project-name):
    Runs a scan of the git directory and produces JSON output for new commits, tags and branches.
]]--
function checkGit(repo, name)
    local backlog = {}
    local prg = io.popen(("git --git-dir %s/.git log -n 20 --summary --tags --raw --date=raw --reverse --pretty=format:\"%%H|%%h|%%ct|%%aN|%%ae|%%s|%%d\" --all"):format(repo), "r")
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
        if commit.id then
            if repoData.lastCommit < 0 then 
                repoData.lastCommit = commit.id
            end
            if commit.author and commit.subject and commit.email and commit.id > repoData.lastCommit then
                local mod = #commit.files .. " files"
                if #commit.files == 1 then mod = commit.files[1] end
                commit.files = mod
                local output = JSON:encode({commit=commit})
                table.insert(backlog, output)
            end
            if commit.id >= repoData.lastCommit then repoData.lastCommit = commit.id end
        end
    end

    -- tags
    local prg = io.popen(("git --git-dir %s/.git tag"):format(repo), "r")
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
            local prg = io.popen(("git --git-dir %s/.git show \"%s\""):format(repo, tag), "r")
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
    local prg = io.popen(("git --git-dir %s/.git branch"):format(repo), "r")
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
            local prg = io.popen(("git --git-dir %s/.git show \"%s\""):format(repo, tag), "r")
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
    for k, child in pairs(connections) do
        if who == child then
            connections[k] = nil
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
    for k, child in pairs(connections) do
        if child then
            local x = child:send(what .. "\r\n")
            if x == nil then
                closeConn(child)
            end
        end
    end
end

--[[ Timer function for scanning Git repos ]]--
function updateGit(force)
    local t = os.time()
    if (t - latestGit) >= 5 or force then
        latestGit = t
        for repo in lfs.dir(rootFolder) do
            if repo:match(criteria) then
                local backlog = checkGit(rootFolder .. "/" .. repo, repo)
                for k, line in pairs(backlog) do
                    cwrite(connections, line..",")
                end
            end
        end
    end
end

--[[ The usual 'stillalive' message sent to clients ]]--
function ping()
    local t = os.time()
    if (t - latestPing) >= 5 then
        cwrite(connections, ("{\"stillalive\": %u},"):format(t))
        latestPing = t
    end
end

--[[ Server event loop ]]--
function eventLoop()
    local child = master:accept()
    if child then
        greetChild(child)
    end
    updateGit()
    ping()
end

--[[ If we trust an IP, actually check the request for POST data ]]--
function checkRequest(child)
    local a = os.time()
    child:settimeout(0.5)
    local rl = child:receive("*l") or "GET /"
    if rl:match("^POST /json") then
        while rl and rl:len() > 0 do
            b = os.time()
            if b-a > 10 then
                child:send("Request timed out!\r\n")
                closeConn(child)
                return
            end
            rl = child:receive("*l")
            eventLoop()
        end
        local json = child:receive("*l")
        if json then
            --local arr = JSON:decode(json)
            cwrite(connections, json..",")
            closeConn(child)
        end
    end
end

--[[ Initial client greeting ]]--
function greetChild(child)
    child:settimeout(0.5)
    X = X + 1
    connections[X] = child
    cwrite(child, "Server: gitpubsub/0.2\r\n\r\n{\"commits\": [")
    local trusted = false
    local ip = child:getpeername()
    for k, tip in pairs(trustedPeers or {}) do
        if ip:match("^"..tip.."$") then
            trusted = true
            break
        end
    end
    if trusted then
        checkRequest(child)
    end
end



--[[ Actual server program starts here ]]--
local portnum = tonumber(arg[1]) or 2069
master = socket.bind("*", portnum)
if not master then
    print("Could not bind to port "..portnum..", exiting")
    os.exit()
end

master:settimeout(0.01)
updateGit(true)

while true do
    eventLoop()
end
