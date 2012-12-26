import re
import os
import sys
import json
import ConfigParser;
from subprocess import Popen, PIPE
from httplib2 import Http

config = ConfigParser.ConfigParser()
config.read('gitpubsub.cfg')

# Set this to point to your local gitpubsub server
postURL = config.get("Server", "URL", 0)

if len(sys.argv) <= 3:
    print("Usage: post-receive [old] [new] [ref]")
    exit()

old, new, ref = sys.argv[1:4]
project = os.path.basename(os.getcwd())
print("Posting commit message for project " + project)

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
print(data)
Http().request(postURL, "PUT", data)

