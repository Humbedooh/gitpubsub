#!/usr/bin/env python

import re
import os
import sys
import json
import ConfigParser;
import sys
import logging
from subprocess import Popen, PIPE
from httplib2 import Http

config = ConfigParser.ConfigParser()
config.read('gitpubsub.cfg')

logging.basicConfig(filename='gitpubsub.log',level=logging.DEBUG)

# Set this to point to your local gitpubsub server
# Since this requires a gitpubsub.cfg in the local 
# directory, we'll also hardcode it for now.
postURL = "http://localhost:2069/json"
try:
    postURL = config.get("Server", "URL", 0)
except:
    logging.info("gitpubsub.cfg not found, using hardcoded defaults")
    pass

project = os.path.basename(os.getcwd())

while True:
    line = sys.stdin.readline()
    if not line:
        break
    [old, new, ref] = line.split(None, 2)
    logging.info("Posting commit message for ref %s in project %s", new, project)

    process = Popen(["git", "show", "--name-only", new], stdout=PIPE)
    exit_code = os.waitpid(process.pid, 0)
    output = process.communicate()[0]

    commit = {'ref': ref, 'repository': "git", 'hash': new, 'project': project}

    arr = output.split("\n\n", 3)
    headers = arr[0]
    log = arr[1]
    if len(arr) == 3:
        commit['files'] = re.findall(r"([^\r\n]+)", arr[2])

    parsed = dict(re.findall(r"(?P<name>[^:\n]+): (?P<value>[^\r\n]+)", headers))

    author = re.match(r"^(.+) <(.+)>$", parsed.get("Author", "?? <??@??>"))
    if author:
        commit['author'] = author.group(1)
        commit['email'] = author.group(2)
    else:
        commit['author'] = "Unknown"
        commit['email'] = "unknown@unknown"

    data = json.dumps({'commit': commit}) + "\n\n"
    logging.info("Posting commit data to URL %s", postURL)
    try:
        Http().request(postURL, "PUT", data)
        logging.info("Commit %s was posted", new)
    except:
        logging.warning("Could not connect to %s, commit not reported", postURL)
        pass

