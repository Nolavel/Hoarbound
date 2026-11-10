#!/usr/bin/env python3
"""Relay comments between one GitHub Discussion and one GitHub Issue.

No external dependencies. A source marker plus destination lookup prevents
duplicates on workflow reruns. No instructions found in comments are executed.
"""
from __future__ import annotations

import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

MARKER_PREFIX = "<!-- hoarbound-bridge:"
MAX_BODY = 25000
MAX_PAGES = 10


class BridgeError(RuntimeError):
    pass


def is_relay(body: str) -> bool:
    return MARKER_PREFIX in body


def source_marker(kind: str, source_id: str) -> str:
    if kind not in {"issue", "discussion"} or not source_id.isdigit():
        raise BridgeError("Invalid comment source marker")
    return f"<!-- hoarbound-bridge:{kind}:{source_id} -->"


def destination(event_name: str, event: dict, issue_number: int, discussion_number: int) -> str | None:
    comment = event.get("comment", {})
    if not isinstance(comment, dict) or not comment.get("body") or is_relay(str(comment["body"])):
        return None
    if comment.get("user", {}).get("login") == "github-actions[bot]":
        return None
    if event_name == "issue_comment":
        issue = event.get("issue", {})
        if issue.get("number") == issue_number and "pull_request" not in issue:
            return "discussion"
    if event_name == "discussion_comment" and event.get("discussion", {}).get("number") == discussion_number:
        return "issue"
    return None


def format_relay(*, source: str, source_number: int, author: str, url: str, body: str, source_id: str) -> str:
    if len(body) > MAX_BODY:
        raise BridgeError(f"Source comment exceeds {MAX_BODY} characters; refusing to truncate")
    if source not in {"issue", "discussion"}:
        raise BridgeError("Unknown relay source")
    label = f"Issue #{source_number}" if source == "issue" else f"Discussion #{source_number}"
    # GitHub account attribution, not proof of which AI produced the message.
    return (f"**Mirrored from [{label}]({url}) · GitHub author @{author}**\n\n"
            f"{body.strip()}\n\n{source_marker(source, source_id)}")


class Github:
    def __init__(self, token: str, owner: str, repo: str):
        self.token, self.owner, self.repo = token, owner, repo
        self.base = f"https://api.github.com/repos/{quote(owner)}/{quote(repo)}"

    def _api(self, url: str, *, data: dict | None = None) -> object:
        raw = None if data is None else json.dumps(data, ensure_ascii=False).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "hoarbound-discussion-bridge",
        }
        if raw is not None:
            headers["Content-Type"] = "application/json"
        req = Request(url, data=raw, headers=headers, method="POST" if raw is not None else "GET")
        try:
            with urlopen(req, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            detail = error.read(1000).decode("utf-8", "replace")
            raise BridgeError(f"GitHub HTTP {error.code}: {detail}") from error
        except URLError as error:
            raise BridgeError(f"GitHub connection failed: {error.reason}") from error

    def rest(self, path: str, payload: dict | None = None) -> object:
        return self._api(f"{self.base}/{path.lstrip('/')}", data=payload)

    def graphql(self, query: str, variables: dict) -> dict:
        result = self._api("https://api.github.com/graphql", data={"query": query, "variables": variables})
        if not isinstance(result, dict) or result.get("errors"):
            raise BridgeError(f"GitHub GraphQL error: {result.get('errors') if isinstance(result, dict) else result}")
        return result["data"]

    def discussion(self, number: int) -> dict:
        query = """query($owner:String!, $repo:String!, $number:Int!) {
          repository(owner:$owner, name:$repo) {
            discussion(number:$number) { id url number }
          }
        }"""
        data = self.graphql(query, {"owner": self.owner, "repo": self.repo, "number": number})
        discussion = (data.get("repository") or {}).get("discussion")
        if discussion is None:
            raise BridgeError(f"Discussion #{number} missing or inaccessible to GITHUB_TOKEN")
        return discussion

    def discussion_has_marker(self, number: int, marker: str) -> bool:
        query = """query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
          repository(owner:$owner, name:$repo) {
            discussion(number:$number) {
              comments(first:100, after:$cursor) {
                nodes { body }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }"""
        cursor = None
        for _ in range(MAX_PAGES):
            data = self.graphql(query, {"owner": self.owner, "repo": self.repo,
                                        "number": number, "cursor": cursor})
            discussion = (data.get("repository") or {}).get("discussion")
            if discussion is None:
                raise BridgeError("Discussion missing during duplicate check")
            comments = discussion["comments"]
            if any(marker in (node or {}).get("body", "") for node in comments["nodes"]):
                return True
            if not comments["pageInfo"]["hasNextPage"]:
                return False
            cursor = comments["pageInfo"]["endCursor"]
        raise BridgeError("Too many Discussion comments for safe deduplication")

    def issue_has_marker(self, number: int, marker: str) -> bool:
        for page in range(1, MAX_PAGES + 1):
            comments = self.rest(f"issues/{number}/comments?per_page=100&page={page}")
            if not isinstance(comments, list):
                raise BridgeError("Unexpected issue comments response")
            if any(marker in (comment.get("body") or "") for comment in comments):
                return True
            if len(comments) < 100:
                return False
        raise BridgeError("Too many Issue comments for safe deduplication")

    def add_discussion_comment(self, discussion_id: str, body: str) -> str:
        query = """mutation($id:ID!, $body:String!) {
          addDiscussionComment(input:{discussionId:$id, body:$body}) { comment { url } }
        }"""
        data = self.graphql(query, {"id": discussion_id, "body": body})
        return data["addDiscussionComment"]["comment"]["url"]

    def add_issue_comment(self, issue_number: int, body: str) -> str:
        data = self.rest(f"issues/{issue_number}/comments", {"body": body})
        return data["html_url"]


def main() -> int:
    token = os.getenv("GH_TOKEN", "")
    repo_full = os.getenv("GITHUB_REPOSITORY", "")
    event_name = os.getenv("GITHUB_EVENT_NAME", "")
    event_path = os.getenv("GITHUB_EVENT_PATH", "")
    issue_number = int(os.getenv("BRIDGE_ISSUE_NUMBER", "0"))
    discussion_number = int(os.getenv("BRIDGE_DISCUSSION_NUMBER", "0"))
    if not token or "/" not in repo_full or not event_path or min(issue_number, discussion_number) <= 0:
        raise BridgeError("Missing token, repository, event file, or bridge pair configuration")
    with open(event_path, encoding="utf-8") as fh:
        event = json.load(fh)
    owner, repo = repo_full.split("/", 1)
    gh = Github(token, owner, repo)

    if event_name == "workflow_dispatch":
        # Read-only smoke: proves endpoints are visible, not permission to post.
        gh.rest(f"issues/{issue_number}")
        discussion = gh.discussion(discussion_number)
        print(f"Bridge read check OK: Issue #{issue_number} ↔ {discussion['url']}")
        return 0

    target = destination(event_name, event, issue_number, discussion_number)
    if target is None:
        print("Bridge: irrelevant, missing, or relayed comment; no action")
        return 0

    comment = event["comment"]
    comment_id = str(comment["id"])
    source = "issue" if target == "discussion" else "discussion"
    src_number = issue_number if source == "issue" else discussion_number
    marker = source_marker(source, comment_id)
    message = format_relay(source=source, source_number=src_number,
                           author=comment.get("user", {}).get("login", "unknown"),
                           url=comment["html_url"], body=comment["body"], source_id=comment_id)
    if target == "discussion":
        discussion = gh.discussion(discussion_number)
        if gh.discussion_has_marker(discussion_number, marker):
            print("Bridge: already mirrored to Discussion; skipping")
            return 0
        url = gh.add_discussion_comment(discussion["id"], message)
    else:
        if gh.issue_has_marker(issue_number, marker):
            print("Bridge: already mirrored to Issue; skipping")
            return 0
        url = gh.add_issue_comment(issue_number, message)
    print(f"Bridge: {source} comment {comment_id} → {url}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BridgeError, KeyError, ValueError, TypeError) as error:
        print(f"Bridge failure: {error}", file=sys.stderr)
        sys.exit(1)
