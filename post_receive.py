import re
import os
import sys
import json
from subprocess import Popen, PIPE
from httplib2 import Http

# Set this to point to your local gitpubsub server
postURL = "http://localhost:2069/json"

pwd = os.getcwd()
if len(sys.argv) <= 3:
    print("Usage: post-receive [old] [new] [ref]")
    exit()

old, new, ref = sys.argv[1:4]
m = re.match(r"^.*/([^/]+)$", pwd)
if not m:
    print("Could not figure out which project this is :(", project)
    exit()

project = m.group(1)
print("Posting commit message for project " + project)

process = Popen(["git", "show", "--name-only", new], stdout=PIPE)
#process = Popen(["ls", "-la"], stdout=PIPE)
exit_code = os.waitpid(process.pid, 0)
output = process.communicate()[0]

output = """
Author: Humbedooh <humbedooh@apache.org>
Stuffs: Mooo

Log message goes here
"""

commit = {'ref': ref, 'repository': "git", 'hash': new, 'project': project}

headers, commit['log'] = output.split("\n\n", 2)

parsed = dict(re.findall(r"(?P<name>[^:\n]+): (?P<value>[^\r\n]+)", headers))

author = re.match(r"^(.+) <(.+)>$", parsed.get("Author", "?? <??@??>"))
if author:
    commit['author'] = author.group(1)
    commit['email'] = author.group(2)
else:
    commit['author'] = "Unknown"
    commit['email'] = "unknown@unknown"


data = json.dumps(commit) + "\n\n"
print(data)
Http().request(postURL, "PUT", data)

