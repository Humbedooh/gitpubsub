gitpubsub
=========

A subscribable Git commit notification server written in Lua.

The server scans the local git repositories for changes and 
publishes these changes through a HTTP service (listening on 
the default svnpubsub port 2069) in JSON format.

Setting up the server is quite easy:

configure the location of your git repositories by setting the 
`rootFolder` variable and write up a fitting criteria for which 
folders to consider git repositories.

Then simply run: `nohup lua gitpubsub.lua &` and you're done!

## Pulling data off gitpubsub ##
Self-explanatory.
Once you've set up gitpubsub, try running 
`curl -i http://yourhost:2069/json` and watch the output.


## Pushing data to gitpubsub ##
In addition to the manual labor, gitpubsub also offers any client 
matching the `trustedPeers` list to publicise data to all other 
clients. This is done by doing a `POST` request to /json:

    POST /json HTTP/1.1
    Content-Length: 1234
    
    {"commit":{...}}

## Using a post-receive hook instead ##
If you don't feel like parsing the git repo every 5 seconds, you 
can instead add a post-receive hook to your Git server. Simply 
use the following script (edit it to fit your server):

    while read oldrev newrev refname
    do
       echo $oldrev $newrev $refname | /usr/bin/lua /path/to/post_receive.lua
    done

