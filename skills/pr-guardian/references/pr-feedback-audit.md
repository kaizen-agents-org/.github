# PR Feedback Audit

Use an explicit pull request URL or repository and number. Resolve a usable `gh` executable and authenticate to the target host before running the audit.

## Read state and checks

```sh
gh pr view <pr> --repo <owner/repo> \
  --json url,headRefOid,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,reviews,comments,latestReviews,reviewRequests
gh pr checks <pr> --repo <owner/repo>
```

## Read every review thread

Run this query and follow `pageInfo.endCursor` while `hasNextPage` is true:

```sh
gh api graphql \
  -f owner='<owner>' \
  -f name='<repo>' \
  -F number=<number> \
  -f query='
query($owner:String!, $name:String!, $number:Int!, $cursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      headRefOid
      reviewDecision
      mergeStateStatus
      reviewThreads(first:100, after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          comments(first:100) {
            pageInfo { hasNextPage endCursor }
            nodes {
              fullDatabaseId
              url
              author { login }
              body
              createdAt
              outdated
            }
          }
        }
      }
    }
  }
}'
```

Paginate nested comments too when their `hasNextPage` is true. Also paginate REST reviews, review comments, issue comments, check runs, and annotations; do not treat summaries or the first page as complete evidence.

## Reply, then resolve

For every addressed thread, reply to its first comment using `fullDatabaseId` after the fix is pushed and verified:

```sh
gh api --method POST \
  repos/<owner>/<repo>/pulls/<pr>/comments/<first-comment-full-database-id>/replies \
  -f body='Fixed in <commit>: <disposition>. Verified with <command>.'
```

Then resolve the thread using its GraphQL `id`:

```sh
gh api graphql \
  -f threadId='<review-thread-id>' \
  -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) {
    thread { id isResolved }
  }
}'
```

Reply and resolve each thread individually, including duplicates and outdated threads. If a finding is not applicable, reply with the evidence before resolving it. If either operation is forbidden, preserve the thread URL and report `blocked: unresolved required conversation`.

## Current-head completion

After a push, discard prior completion evidence. Pin the new `headRefOid`, wait for required checks and expected bot reviews tied to that SHA, and then repeat the full audit. Success requires zero unresolved threads and two unchanged passing snapshots at least 30 seconds apart after automated review finishes.
