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
