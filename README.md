GitPubSub
=========

GitPubSub Publisher/Subscriber service for JSON based communication, 
developed for broadcasting git commits.

Changes to git repositories are transmitted in JSON format to 
anyone listening in on the HTTP service.

## Pub/Sub model ##
GitPubSub broadcasts based on the URI requested. If a client subscribes 
to `/foo`, then all messages sent to `/foo` or its sub-directories (such 
as `/foo/bar`) will be broadcast to this client. This enables clients to 
subscribe to whichever specific segment they wish to listen in on.


## Publishing data to GitPubSub ##
If `rootFolder` is set, the server scans the local git repositories for 
changes and publishes these through the HTTP service (listening on 
the default svnpubsub port 2069) in JSON format at the URI `/json`.

### Using a post-receive hook to publish commits ###
If you don't feel like parsing the git repo every 5 seconds, you 
can instead add a post-receive hook to your Git server. Simply 
use the following script (edit it to fit your server):

    while read oldrev newrev refname
    do
       /usr/bin/lua /path/to/post_receive.lua $oldrev $newrev $refname
    done

This will cause new commits to publish to `http://localhost:2069/json` 
by default.

### Manually publishing JSON data ###
GitPubSub offers any client matching the `trustedPeers` list 
to publicise data to all other clients. This is done by doing 
a `POST` request to the URI they wish to publish to:

    POST /json HTTP/1.1
    Content-Length: 1234
    
    {"commit":{...}}


## Pulling data off GitPubSub ##
Self-explanatory.
Once you've set up GitPubSub, try running 
`curl -i http://yourhost:2069/json` and watch the output.

## Retrieving past commits ##
While the Pub/Sub model usually deals with real-time events, it is possible to go back in time and retrieve past events 
using the `X-Fetch-Since` request header. This value must be set to the UTC UNIX timestamp of the last time 
a client visited the Pub/Sub service, in order to continue where it left off. For example, one could construct the 
following request:

    GET /json HTTP/1.1
    X-Fetch-Since: 1366268954

These timestamps can be acquired by parsing the `stillalive` messages sent by GitPubSub, using the 
`X-Timestamp` response header sent back from POST/PUT requests, or by using whatever time function 
your programming language provides.

## Access control: ##
The `trustedPeers` array contains a list of clients allowed to publish 
to the GitPubSub server. By default, only 127.0.0.1 is allowed to publish.

Any client can grab the JSON feeds off the server.


### Running the server: ###

Then simply run: `nohup lua gitpubsub.lua &` and you're done!

### Polling for statistics ###

If your IP is within the `trustedPeers` list, you can poll the server for 
statistics by running: `curl -I http://localhost:2069`. This will output 
something similar to:

    Server: GitPubSub/0.4
    X-Uptime: 200
    X-Connections: 1
    X-Total-Connections: 39017
    X-Received: 584421
    X-Sent: 1563105


### Other uses ###
GitPubSub can be used to broadcast any form of JSON-encoded data to multiple 
recipients, not just Git commits.


### Pre-requisites: ###
GitPubSub requires the following modules/scripts:

`luafilesystem` http://keplerproject.github.com/luafilesystem/ (only required if local scanning is active)

`luasocket` http://luaforge.net/projects/luasocket/

`LuaJSON` http://luaforge.net/projects/luajson/

OR

`JSON` http://regex.info/code/JSON.lua

