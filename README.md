GitPubSub
=========

GitPubSub is a subscribable Git commit notification server 
similar to SvnPubSub.

Changes to git repositories are transmitted in JSON format to 
anyone listening in on the HTTP service.

By default, the server scans the local git repositories for 
changes and publishes these through the HTTP service (listening on 
the default svnpubsub port 2069) in JSON format.

A post-receive hook is also available for notifying when a commit 
has been pushed to the server.

## Setting up the server: ##

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
       /usr/bin/lua /path/to/post_receive.lua $oldrev $newrev $refname
    done

