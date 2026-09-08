#!/usr/bin/env python3
"""Talk to the Dawg Park board.

The board is the INBOX and `todo.md` is the RECORD. Cards are written by hand,
from a phone, by whoever noticed something; `todo.md` entries are triaged work
with a priority, an effort and the reasoning behind them. So this tool
deliberately does NOT generate cards from todo.md — that direction would bury
fifty-five real observations under synthetic ones. What it does is let a session
read the inbox and *close the loop*: comment on a card saying what happened to
it, and move it to Done when it has actually shipped.

    Tools/trello.py lists
    Tools/trello.py cards [LIST_NAME]
    Tools/trello.py show CARD
    Tools/trello.py comment CARD "what happened"
    Tools/trello.py done CARD ["closing comment"]

CARD is a Trello shortLink — the code in the card URL, e.g. `4yGLv4rb`.

Credentials come from the environment, or from ~/.config/noblestars/trello.env
(TRELLO_KEY and TRELLO_TOKEN). The key is public — it is in every authorize URL
— but the token acts as the whole account, so the file is mode 600 and lives
outside the repo. In CI both arrive as GitHub Actions secrets.

Two things learned setting this up, kept here because both cost real time:

- **The API key CANNOT be reset.** Trello says so on the API Key tab: "Because
  your API Key is public for any client-side applications, we do not currently
  offer a way to reset it." So a key that looks wrong is not wrong.
- **The Secret sits directly under the key and is also 64 hex characters**,
  which is close enough to a token's shape to pass every eyeball check. It was
  pasted in as the token and Trello answered `invalid key`, which points at the
  wrong field entirely. A real token is ~76 characters and starts `ATTA`.
  `Tools/trello.py whoami` exists to settle that in one command.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BOARD = "6a9f0dbe6b5b4443eff0e6f8"  # Dawg Park
ENV_FILE = os.path.expanduser("~/.config/noblestars/trello.env")
DONE_LIST = "Done"


def _creds() -> tuple[str, str]:
    key, token = os.environ.get("TRELLO_KEY"), os.environ.get("TRELLO_TOKEN")
    if not (key and token) and os.path.exists(ENV_FILE):
        for line in open(ENV_FILE, encoding="utf-8"):
            if "=" in line:
                name, _, value = line.strip().partition("=")
                if name == "TRELLO_KEY" and not key:
                    key = value
                elif name == "TRELLO_TOKEN" and not token:
                    token = value
    if not (key and token):
        sys.exit("no TRELLO_KEY/TRELLO_TOKEN in the environment or %s" % ENV_FILE)
    return key, token


def call(method: str, path: str, **params):
    key, token = _creds()
    params.update(key=key, token=token)
    url = "https://api.trello.com/1/%s?%s" % (path, urllib.parse.urlencode(params))
    request = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read().decode()
    except urllib.error.HTTPError as err:
        # Trello's errors are short prose, not JSON, and they are the useful
        # part — `invalid key` vs `invalid app token` is the whole diagnosis.
        sys.exit("trello %s %s: %s" % (method, path, err.read().decode()[:200]))
    return json.loads(body) if body.strip() else None


def lists() -> list:
    return call("GET", "boards/%s/lists" % BOARD, fields="name")


def find_card(short_link: str) -> dict:
    return call("GET", "cards/%s" % short_link,
                fields="name,desc,shortLink,idList,closed")


def cmd_whoami(_args) -> None:
    me = call("GET", "members/me", fields="username,fullName")
    print("%s (%s)" % (me["fullName"], me["username"]))


def cmd_lists(_args) -> None:
    for entry in lists():
        cards = call("GET", "lists/%s/cards" % entry["id"], fields="name")
        print("%-12s %2d  %s" % (entry["name"], len(cards), entry["id"]))


def cmd_cards(args) -> None:
    wanted = args[0].lower() if args else None
    for entry in lists():
        if wanted and wanted not in entry["name"].lower():
            continue
        cards = call("GET", "lists/%s/cards" % entry["id"],
                     fields="name,shortLink")
        print("\n%s (%d)" % (entry["name"], len(cards)))
        for card in cards:
            print("  %s  %s" % (card["shortLink"], card["name"]))


def cmd_show(args) -> None:
    card = find_card(args[0])
    print(card["name"])
    if card.get("desc", "").strip():
        print()
        print(card["desc"].strip())


def cmd_comment(args) -> None:
    call("POST", "cards/%s/actions/comments" % args[0], text=args[1])
    print("commented on %s" % args[0])


def cmd_done(args) -> None:
    target = next((e for e in lists() if e["name"] == DONE_LIST), None)
    if target is None:
        sys.exit("no %r list on the board" % DONE_LIST)
    if len(args) > 1:
        call("POST", "cards/%s/actions/comments" % args[0], text=args[1])
    call("PUT", "cards/%s" % args[0], idList=target["id"], pos="top")
    print("moved %s to %s" % (args[0], DONE_LIST))


COMMANDS = {
    "whoami": cmd_whoami,
    "lists": cmd_lists,
    "cards": cmd_cards,
    "show": cmd_show,
    "comment": cmd_comment,
    "done": cmd_done,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]](sys.argv[2:])
