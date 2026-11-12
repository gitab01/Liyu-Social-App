# Liyu Social

A Flutter + Firebase social network — feed, stories, real-time messaging, media
sharing and push — engineered for the conditions Ethiopian users actually
connect under: metered mobile data, sockets that drop mid-request, and mid-range
Android hardware.

**Stack:** Flutter 3.29 / Dart 3.7 · Riverpod · go_router · Firebase Auth
(phone OTP), Firestore, Storage, Cloud Messaging · Cloud Functions (Node 20) ·
Amharic + English.

---

## 1. The problem this solves

Most social apps assume a stable, cheap connection and a fast phone. Neither
holds here, and the failure modes are invisible in a demo on office Wi-Fi:

| Assumption that breaks | What it costs the user | Here |
| --- | --- | --- |
| Images can be uploaded as shot | 4–8 MB per post on a prepaid bundle | Client-side downscale to 1280 px q80 + 320 px q70 thumbnail; the feed only ever loads the thumbnail |
| The request will finish | A send that silently vanished, or two identical sends after a retry | Client-minted ids + one retry owner (`LocalWriteQueue`), so replay is idempotent |
| The list is small enough to fetch | Dozens of documents read to render one screen | Denormalized, list-ready documents: a feed page is one query, no per-post follower lookups |
| The client can be trusted about what it may read | Someone else's story media, editable counters | Rules are the authorization layer; counters are writable only by Functions |
| Stories expire by themselves | Storage bytes billed forever after the story disappeared | A scheduled cleanup deletes document *and* object |

## 2. Feature tour

- **Feed** — paginated by a `(createdAt, postId)` cursor so a page boundary can
  never repeat or skip a row; infinite scroll on the same query the rules allow.
- **Stories** — 24 h TTL, seen/unseen ring, a viewer that auto-advances but
  stops the clock while a finger is held down, tap zones for previous and next,
  and real deletion once a story expires.
- **Composer** — camera or gallery, each picked item moving visibly through
  *compress → upload → publish*, public or followers-only audience, mentions.
- **Chat** — one-to-one threads, optimistic `pending / sent / failed` states,
  retry that reuses the same message id, image attachments, unread counts.
- **Search** — find people by display name, with the follow state and the two
  actions a profile card offers, plus a suggestions list when the query is empty.
- **Notifications** — like / comment / follow / mention / message fan-out, deep
  links into the right screen, unread marker, mark-all-read.
- **Profile** — posts grid, followers/following lists, bio, block, message.
- **Settings** — theme, language, data-saver, a simulate-offline switch (the
  queue badge updates live), and which backend this run picked plus why.

## 3. Architecture

```
lib/
  app/          main(), bootstrap() — backend choice happens once, here
  core/         router, providers, l10n, theme, offline queue, widgets
  domain/       models, repository interfaces, access_rules.dart
  data/
    firebase/   Firestore / Storage / Auth / FCM implementations
    local/      a complete second implementation of the same interfaces
    media/      image compression engine + in-process byte store
  features/     one folder per screen, no cross-screen imports
```

Two rules keep that structure honest:

1. **Features never import `data/`.** They read repositories through Riverpod
   providers, so nothing in the UI knows whether it is talking to Firebase or to
   the on-device backend.
2. **`domain/access_rules.dart` is the only place visibility is decided.** The
   local backend enforces it in Dart, and `firestore.rules` / `storage.rules`
   mirror the same predicates. A rule that cannot be expressed in both is a bug
   in whichever side is missing it.

The local backend exists so the app is *runnable with no credentials*: `flutter
run` on a fresh clone gives a working feed, chat, stories and media pipeline
backed by `SharedPreferences` plus an in-process byte store, seeded with
deterministic demo content. It is also what the widget and integration tests run
against, which keeps those tests honest about the real screens.

## 4. Data model

Firestore is document-oriented, so reads are shaped for the screen, not for
normal-form purity:

- `users/{uid}` — profile **plus** `postsCount`, `followersCount`,
  `followingCount`. Counters live on the document the profile screen already
  reads; paying a second query per badge is not justified.
- `posts/{postId}` — caption, media refs, `authorName`, `authorPhoto`,
  `likesCount`, `commentsCount`. A feed tile renders from one document.
- `posts/{postId}/comments/{id}` and `.../reactions/{uid}` — subcollections, so
  a thread pages independently and one reaction per author is enforced by the
  document id itself.
- `stories/{id}`, `follows/{followerUid_followingUid}`, `conversations/{id}`,
  `conversations/{id}/messages/{messageId}`, `notifications/{id}`,
  `devices/{token}`.
- Conversation ids are derived from the sorted uid pair
  (`u_dawit_u_selam`), so two clients opening the same chat cannot create two
  threads.
- `feed` reads for followers-only posts are resolved with an `authorUid IN
  [allowed set]` query rather than a client-side join.

## 5. Media: the cost decision

`ImageEngine.prepare()` runs before any network call:

- long edge 1280 px, JPEG q80 for the full image;
- 320 px q70 for the thumbnail that lists, rails and grids actually load;
- native codec first (`flutter_image_compress`), `dart:ui` fallback for web,
  desktop and odd HEIC — the post degrades, it does not fail;
- `MediaStore` caps its in-process cache at 64 MB with oldest-first eviction.

Lists request thumbnails only, and `cached_network_image` keeps them off repeat
bundles. Full images load on tap. The composer reports the bytes saved, because
"data thrifty" is a number, not a mood.

## 6. Offline, and the states a send can be in

`LocalWriteQueue` owns one question: *when do we retry?*

- Firestore persists document writes itself, but Storage uploads and message
  sends do not survive a dropped socket — so those go through the queue.
- ids are minted on the client *before* the first attempt, which is what makes a
  replay safe instead of duplicating.
- `MessageStatus` is `pending`, `sent` or `failed`, and the UI renders exactly
  that. Nothing in the chat thread ever claims "sent" before the write landed.
- The app bar shows a live pending-writes badge; Settings can force the offline
  state to test the whole path without leaving the house.

## 7. Security

- Phone OTP (or email) auth; no anonymous accounts.
- `firestore.rules` reads like `AccessRules`: who may list a feed, open a
  thread, move a counter. Counters, `*Count` fields and fan-out documents are
  frozen against client writes — only Cloud Functions may touch them.
- `storage.rules` enforce the `users/{uid}/{purpose}/{mediaId}` layout that
  `AccessRules.mediaPathFor` produces, images only, under 8 MB, and refuse
  client deletion of `story/` objects so a story document cannot outlive its
  bytes before the cleanup function runs.
- Anything not matched is denied by default.

## 8. Cloud Functions (`functions/index.js`)

| Trigger | Job |
| --- | --- |
| `maintainLikesOnAdd/Remove` | post `likesCount` |
| `maintainCommentsOnAdd/Remove` | post `commentsCount` |
| `maintainPostCountOnAdd/Remove` | author `postsCount` |
| `onFollowCreated/Removed` | both followers/following counters + a tray entry |
| `onMessageCreated` | unread counts, inbox header, push to the recipient's devices |
| `onPostMentions` | notification per mentioned account |
| `cleanupExpiredStories` (scheduled 03:00) | deletes expired story documents **and** their Storage objects |

Every counter mutation runs inside `runTransaction`, floored at zero;
notification ids are derived from the event so a retried invocation rewrites one
tray entry rather than adding a second.

## 9. Localisation and design

- Amharic-first: every string lives in `core/l10n/app_strings.dart` (112 keys,
  English and Amharic side by side). Ge'ez script is left-to-right, so this is a
  string table plus a font, not a direction flip.
- Android ships Noto Sans Ethiopic and iOS ships Kefa; `web/index.html` loads
  Noto Sans Ethiopic so the web build does not fall back to tofu.
- Ink-first theme: pure white and pure black canvases, one deep-green accent
  with a warm gold for social proof, red reserved for destructive and failure
  states. No gradients, glows or tinted section bands — every tint stays at
  component level. 44 dp touch targets, hairline dividers instead of shadows.

## 10. Run it

Requirements: Flutter 3.29+ (`flutter --version`). No Firebase project, no
emulator, no credentials.

```bash
flutter pub get
flutter run                 # starts on the local backend, seeded with demo content
```

The sign-in screen prefills the demo number; the local backend cannot send SMS,
so it displays the OTP code it minted and you type that in. Nothing is faked —
the same repositories, router and rules logic serve every screen.

```bash
flutter analyze
flutter test                # 30 tests: access rules, offline messaging, story expiry, the app itself, layout at 390 dp
```

### Switching to Firebase

You own the project, so the credentials are generated on your machine and never
written into this repository:

1. Create a Firebase project, then enable **Authentication → Sign-in method →
   Phone**, **Firestore**, **Storage** and **Cloud Messaging**.
2. Add an Android app (package name from `android/app/build.gradle.kts`) and, if
   you want it, an iOS app.
3. Generate the Dart options:

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

4. Tell the app to prefer Firebase, then deploy the backend it was designed
   against:

   ```bash
   npm --prefix functions install
   firebase deploy --only firestore:rules,storage:rules,functions,firestore:indexes
   ```

   `firebase.json` deliberately carries no project id — `flutterfire configure`
   or `firebase use --add` fills that in per machine.
5. Rebuild. If Firebase cannot initialize, `bootstrap()` falls back to the local
   backend and Settings says which one is running and why.

For iteration without billing, `firebase emulators:start` reads the same
`firebase.json`.

## 11. Testing

| File | What it proves |
| --- | --- |
| `test/access_rules_test.dart` | Every `AccessRules` predicate the rules files also encode: followers-only posts, story expiry, blocks in both directions, media path ownership, participant-only messages |
| `test/messaging_test.dart` | Online send lands as `sent` with one document; offline send stays `pending` and replays **exactly once** after reconnect; retry rewrites rather than duplicates; unread counts move only for the reader; fan-out writes the same notification shape Functions writes |
| `test/stories_test.dart` | A fresh story appears on the rail with resolvable media; an expired story leaves the rail *and* its document and both byte objects are deleted; a viewer is recorded once |
| `test/widget_test.dart` | The real app booted through `bootstrap()`: the gate holds a cold start, and the code the backend minted actually reaches the shell |
| `test/shell_layout_test.dart` | Every branch and every covered route — feed, search, composer, inbox, profile, settings, notifications, edit profile, post detail, thread, connections, story viewer — laid out on a 390 × 844 surface. An overflow at handset width fails this test |

## 12. Repo map

```
lib/                    the Flutter client (see §3)
test/                   rules, offline, expiry and full-app widget tests
firestore.rules         authorization, mirrored from domain/access_rules.dart
firestore.indexes.json  the composite indexes the queries above need
storage.rules           per-uid media prefix, image-only, size-capped
functions/index.js      counters, fan-out, push, nightly story cleanup
firebase.json           deploy + emulator wiring, no project id committed
```
