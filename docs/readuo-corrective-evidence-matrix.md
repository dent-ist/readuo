# Corrective integration evidence matrix

This supplements, rather than rewrites, the build-25 historical audit. R = current Android fixture render at normal and small/large-text sizes, not a fidelity acceptance claim. B = additionally compared in the coordinator’s bounded structural review. Final Book/Circle refinements passed separate four-state runs at both sizes and were visually checked; see `manifest-refinements*.json`. H = retained earlier Android evidence, not freshly revalidated. All canonical reference PNGs now include Lucide icons. Production/physical-device end-to-end acceptance is not implied.

Current fixture coverage: 79 of 117 canonical IDs; 5 additional captures cover keyboard, photo access, and profile-bottom details. Remaining 38 IDs retain their prior evidence. See manifests and logs for run success; FAILED images never count.

| # | Canonical ID | Evidence | Location under app/test/artifacts |
|---|---|---|---|
| 1 | `login` | R | final-review/login.png; final-review/login-small-large-text.png |
| 2 | `login-error` | R | final-review/login-error.png; final-review/login-error-small-large-text.png |
| 3 | `setup` | B | final-review/setup.png; final-review/setup-small-large-text.png |
| 4 | `profile-photo` | R | final-review/profile-photo.png; final-review/profile-photo-small-large-text.png |
| 5 | `first-book` | H | p1-06-review/android/first-book-390x844.png |
| 6 | `terms` | R | final-review/terms.png; final-review/terms-small-large-text.png |
| 7 | `privacy` | R | final-review/privacy.png; final-review/privacy-small-large-text.png |
| 8 | `circle` | R | final-review/circle.png; final-review/circle-small-large-text.png |
| 9 | `circle-empty` | B | final-review/circle-empty.png; final-review/circle-empty-small-large-text.png |
| 10 | `compose` | H | p1-10-review/compose-corrected-390x844.png |
| 11 | `compose-photo` | H | p1-12-14-review/photo-source-sheet-safe-390x844.png |
| 12 | `attach-book` | H | p1-10-review/attach-book-corrected-360x640.png |
| 13 | `review` | H | p1-11-review/write-review-390x844.png |
| 14 | `post` | R | final-review/post.png; final-review/post-small-large-text.png |
| 15 | `post-menu` | R | final-review/post-menu.png; final-review/post-menu-small-large-text.png |
| 16 | `own-post-menu` | H | p1-10-review/own-post-menu-390x844.png |
| 17 | `edit-post` | H | p1-10-review/edit-post-corrected-390x844.png |
| 18 | `delete-post` | H | p1-10-review/delete-post-390x844.png |
| 19 | `comment-menu` | R | final-review/comment-menu.png; final-review/comment-menu-small-large-text.png |
| 20 | `own-comment-menu` | R | final-review/own-comment-menu.png; final-review/own-comment-menu-small-large-text.png |
| 21 | `owner-comment-menu` | H | p1-12-14-review/owner-comment-menu-safe-390x844.png |
| 22 | `edit-comment` | R | final-review/edit-comment.png; final-review/edit-comment-small-large-text.png |
| 23 | `delete-comment` | R | final-review/delete-comment.png; final-review/delete-comment-small-large-text.png |
| 24 | `report` | B | final-review/report.png; final-review/report-small-large-text.png |
| 25 | `report-sent` | R | final-review/report-sent.png; final-review/report-sent-small-large-text.png |
| 26 | `notifications` | B | final-review/notifications.png; final-review/notifications-small-large-text.png |
| 27 | `notifications-empty` | R | final-review/notifications-empty.png; final-review/notifications-empty-small-large-text.png |
| 28 | `library` | H | p1-07-review/library-390x844.png |
| 29 | `library-books` | R | final-review/library-books.png; final-review/library-books-small-large-text.png |
| 30 | `sort-books` | R | final-review/sort-books.png; final-review/sort-books-small-large-text.png |
| 31 | `library-empty` | R | final-review/library-empty.png; final-review/library-empty-small-large-text.png |
| 32 | `search-results` | R | final-review/search-results.png; final-review/search-results-small-large-text.png |
| 33 | `search-empty` | R | final-review/search-empty.png; final-review/search-empty-small-large-text.png |
| 34 | `filter-empty` | R | final-review/filter-empty.png; final-review/filter-empty-small-large-text.png |
| 35 | `shelf` | R | final-review/shelf.png; final-review/shelf-small-large-text.png |
| 36 | `shelf-empty` | R | final-review/shelf-empty.png; final-review/shelf-empty-small-large-text.png |
| 37 | `create-shelf` | R | final-review/create-shelf.png; final-review/create-shelf-small-large-text.png |
| 38 | `shelf-settings` | R | final-review/shelf-settings.png; final-review/shelf-settings-small-large-text.png |
| 39 | `private-confirm` | R | final-review/private-confirm.png; final-review/private-confirm-small-large-text.png |
| 40 | `delete-shelf` | R | final-review/delete-shelf.png; final-review/delete-shelf-small-large-text.png |
| 41 | `move-all` | R | final-review/move-all.png; final-review/move-all-small-large-text.png |
| 42 | `delete-shelf-confirm` | R | final-review/delete-shelf-confirm.png; final-review/delete-shelf-confirm-small-large-text.png |
| 43 | `book` | B | final-review/book.png; final-review/book-small-large-text.png |
| 44 | `saved-book` | R | final-review/saved-book.png; final-review/saved-book-small-large-text.png |
| 45 | `book-menu` | R | final-review/book-menu.png; final-review/book-menu-small-large-text.png |
| 46 | `reading-status` | R | final-review/reading-status.png; final-review/reading-status-small-large-text.png |
| 47 | `move-book` | R | final-review/move-book.png; final-review/move-book-small-large-text.png |
| 48 | `remove-book` | R | final-review/remove-book.png; final-review/remove-book-small-large-text.png |
| 49 | `explore` | H | p1-07-review/explore-390x844.png |
| 50 | `explore-public` | H | p1-08-review/explore-public-390x844.png |
| 51 | `explore-results` | H | p1-07-review/search-390x844.png |
| 52 | `explore-empty` | R | final-review/explore-empty.png; final-review/explore-empty-small-large-text.png |
| 53 | `explore-no-results` | R | final-review/explore-no-results.png; final-review/explore-no-results-small-large-text.png |
| 54 | `friend-shelf` | R | final-review/friend-shelf.png; final-review/friend-shelf-small-large-text.png |
| 55 | `public-shelf` | H | p1-08-review/public-shelf-390x844.png |
| 56 | `friend-book` | R | final-review/friend-book.png; final-review/friend-book-small-large-text.png |
| 57 | `public-book` | H | p1-08-review/public-book-390x844.png |
| 58 | `save-shelf` | R | final-review/save-shelf.png; final-review/save-shelf-small-large-text.png |
| 59 | `book-saved` | R | final-review/book-saved.png; final-review/book-saved-small-large-text.png |
| 60 | `unavailable` | R | final-review/unavailable.png; final-review/unavailable-small-large-text.png |
| 61 | `public-profile` | H | p1-08-review/public-profile-390x844.png |
| 62 | `camera-permission` | H | p1-05-review/android/permission-rationale-390x844.png |
| 63 | `scanner` | H | p1-05-review/android/destination-390x844.png |
| 64 | `camera-denied` | H | p1-05-review/android/camera-denied-390x844.png |
| 65 | `scan-loading` | H | p1-05-review/android/lookup-loading-390x844.png |
| 66 | `scan-found` | H | p1-05-review/android/confirmation-top-390x844.png |
| 67 | `scan-duplicate` | H | p1-05-review/android/duplicate-390x844.png |
| 68 | `manual-isbn` | H | p1-05-review/android/manual-isbn-390x844.png |
| 69 | `isbn-not-found` | H | p1-05-review/android/isbn-not-found-390x844.png |
| 70 | `catalogue-search` | H | p1-04-review2/app/catalogue-prompt-390x844.png |
| 71 | `catalogue-results` | H | p1-04-review2/app/catalogue-editions-390x844.png |
| 72 | `catalogue-no-results` | H | p1-04-review2/app/catalogue-no-results-390x844.png |
| 73 | `manual-book` | H | p1-22-manual-form.png |
| 74 | `book-photo` | H | p1-22-cover-final-sheet.png |
| 75 | `manual-confirm` | H | p1-22-photo-confirm-recovered.png |
| 76 | `manual-possible-duplicate` | R | final-review/manual-possible-duplicate.png; final-review/manual-possible-duplicate-small-large-text.png |
| 77 | `scan-saved` | H | p1-05-review/android/saved-390x844.png |
| 78 | `photo-denied` | H | p1-12-14-review/photo-denied-390x844.png |
| 79 | `friends` | B | final-review/friends.png; final-review/friends-small-large-text.png |
| 80 | `friends-empty` | R | final-review/friends-empty.png; final-review/friends-empty-small-large-text.png |
| 81 | `invite` | H | p1-21-invite-corrected.png |
| 82 | `enter-code` | R | final-review/enter-code.png; final-review/enter-code-small-large-text.png |
| 83 | `invalid-code` | R | final-review/invalid-code.png; final-review/invalid-code-small-large-text.png |
| 84 | `request-preview` | R | final-review/request-preview.png; final-review/request-preview-small-large-text.png |
| 85 | `request-sent` | B | final-review/request-sent.png; final-review/request-sent-small-large-text.png |
| 86 | `requests` | R | final-review/requests.png; final-review/requests-small-large-text.png |
| 87 | `request-detail` | R | final-review/request-detail.png; final-review/request-detail-small-large-text.png |
| 88 | `sent-requests` | R | final-review/sent-requests.png; final-review/sent-requests-small-large-text.png |
| 89 | `friend-profile` | R | final-review/friend-profile.png; final-review/friend-profile-small-large-text.png |
| 90 | `profile-menu` | R | final-review/profile-menu.png; final-review/profile-menu-small-large-text.png |
| 91 | `remove-friend` | R | final-review/remove-friend.png; final-review/remove-friend-small-large-text.png |
| 92 | `block-friend` | R | final-review/block-friend.png; final-review/block-friend-small-large-text.png |
| 93 | `blocked-users` | R | final-review/blocked-users.png; final-review/blocked-users-small-large-text.png |
| 94 | `unblock` | R | final-review/unblock.png; final-review/unblock-small-large-text.png |
| 95 | `profile` | B | final-review/profile.png; final-review/profile-small-large-text.png |
| 96 | `edit-profile` | R | final-review/edit-profile.png; final-review/edit-profile-small-large-text.png |
| 97 | `notification-settings` | R | final-review/notification-settings.png; final-review/notification-settings-small-large-text.png |
| 98 | `account` | R | final-review/account.png; final-review/account-small-large-text.png |
| 99 | `delete-account` | H | p1-19-acknowledgement.png |
| 100 | `reauth` | H | p1-19-21-verification.png |
| 101 | `deleting` | H | p1-19-21-processing.png |
| 102 | `delete-account-error` | H | p1-19-21-paused.png |
| 103 | `account-deleted` | H | p1-19-21-completed.png |
| 104 | `signout` | R | final-review/signout.png; final-review/signout-small-large-text.png |
| 105 | `support` | B | final-review/support.png; final-review/support-small-large-text.png |
| 106 | `support-message` | R | final-review/support-message.png; final-review/support-message-small-large-text.png |
| 107 | `offline-library` | R | final-review/offline-library.png; final-review/offline-library-small-large-text.png |
| 108 | `offline-book` | R | final-review/offline-book.png; final-review/offline-book-small-large-text.png |
| 109 | `offline-action` | R | final-review/offline-action.png; final-review/offline-action-small-large-text.png |
| 110 | `network-error` | R | final-review/network-error.png; final-review/network-error-small-large-text.png |
| 111 | `feed-loading` | R | final-review/feed-loading.png; final-review/feed-loading-small-large-text.png |
| 112 | `save-error` | R | final-review/save-error.png; final-review/save-error-small-large-text.png |
| 113 | `content-filtered` | R | final-review/content-filtered.png; final-review/content-filtered-small-large-text.png |
| 114 | `notification-permission` | R | final-review/notification-permission.png; final-review/notification-permission-small-large-text.png |
| 115 | `moderation` | B | final-review/moderation.png; final-review/moderation-small-large-text.png |
| 116 | `report-detail` | R | final-review/report-detail.png; final-review/report-detail-small-large-text.png |
| 117 | `moderation-action` | R | final-review/moderation-action.png; final-review/moderation-action-small-large-text.png |
