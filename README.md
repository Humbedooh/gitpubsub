gitpubsub
=========

A subscribable Git commit notification server written in Lua.

The server scans the local git repositories for changes and 
publishes these changes through a HTTP service (listening on 
the default svnpubsub port 2069) in JSON format.
