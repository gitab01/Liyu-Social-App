'use strict';

// Cloud Functions — the only writer of shared counters and the only producer of
// notifications and push. Firebase is the entire backend, so the two things that
// must be correct and race-free (counters, expiry) live here rather than in
// clients. Every counter mutation runs inside runTransaction: two simultaneous
// likes on the same post would otherwise read the same old value and lose one.
//
// The Admin SDK bypasses Firestore/Storage security rules, which is exactly why
// firestore.rules can refuse to let a client move a counter — these functions are
// the sole owner of those fields.
//
// Notification documents mirror the local backend's fan-out (`lib/data/local/
// local_counters.dart`): ids are derived from the event rather than random, so a
// retried invocation rewrites one tray entry instead of adding a second, and the
// bodies and targets are the same fields the on-device repositories write. Two
// backends that disagree about a tray document would make the widget tests lie.

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');

// Guarded init: the emulator and a reused container share one process, and a
// second initializeApp() throws. v2 triggers do not initialise Admin for you.
if (!getApps().length) {
  initializeApp();
}

const db = () => getFirestore();

// --- helpers ----------------------------------------------------------------

// Move a counter atomically, floored at zero.
//
// If the target document has not landed yet — a brand-new account whose profile
// write lost the race against this trigger — the field is set rather than
// failing an update on a missing document.
async function bumpCounter(ref, field, delta) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      tx.set(ref, { [field]: Math.max(0, delta) }, { merge: true });
      return;
    }
    const current = snap.data()[field] || 0;
    tx.update(ref, { [field]: Math.max(0, current + delta) });
  });
}

// `n_like_p_07_u_dawit`, `n_message_msg_03`, `n_follow_u_hiwot_u_selam` — the same
// derivation the local backend uses, for the same reason: the write can replay.
function notificationId(kind, parts) {
  return ['n_' + kind, ...parts.filter((p) => p)].join('_');
}

// Tray copy in the recipient's language, without the actor's name: `actorName` is
// its own field, and the UI (and the push title) puts the two together.
function phraseFor(type, languageCode) {
  const am = languageCode === 'am';
  switch (type) {
    case 'like':
      return am ? 'ልጥፍዎን ወድዷል' : 'liked your post';
    case 'follow':
      return am ? 'እየተከተሉዎት ነው' : 'started following you';
    case 'comment':
      return am ? 'ላይ አስተያየት ሰጥቷል' : 'commented on your post';
    case 'mention':
      return am ? 'ስምዎን አወሳል' : 'mentioned you';
    case 'message':
      return am ? 'ቅሬታ ልኳልዎታል' : 'sent you a message';
    default:
      return am ? 'ማሳወቂያ ላክልዎታል' : 'sent you a notification';
  }
}

// Exactly AppNotification.deepLink, in the same precedence order, so a push tap
// and a tray tap land on the same route whatever created the entry.
function deepLinkFor(entry) {
  if (entry.conversationId) return `/chat/${entry.conversationId}`;
  if (entry.postId) return `/feed/post/${entry.postId}`;
  if (entry.actorUid && entry.type === 'follow') return `/profile/${entry.actorUid}`;
  return '/notifications';
}

async function profileSnapshot(uid) {
  if (!uid) return {};
  const snap = await db().collection('users').doc(uid).get();
  return snap.exists ? snap.data() : {};
}

async function sendPushToUser(recipientUid, { title, body, data }) {
  const deviceSnap = await db().collection('devices').doc(recipientUid).get();
  const token = deviceSnap.exists && deviceSnap.data().fcmToken;
  if (!token) {
    // Not an error: an account that never granted permission has no token, and the
    // durable tray document above is still written.
    logger.info('no registered device token for recipient, push skipped', { recipientUid });
    return;
  }
  // FCM data values must be strings; the client router reads `deepLink` on tap.
  const stringData = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, v == null ? '' : String(v)]),
  );
  await deliverPush({ token, notification: { title, body }, data: stringData });
}

// Split out so a test can stub delivery without reaching FCM.
async function deliverPush(message) {
  const { getMessaging } = require('firebase-admin/messaging');
  try {
    await getMessaging().send(message);
  } catch (error) {
    // A dead token (uninstall) or a quota blip must not fail the trigger: the
    // notification document is already written, and a thrown error here would
    // retry the whole handler and re-notify the user.
    logger.warn('push delivery failed', { error: error && error.message });
  }
}

// One tray entry plus its push. Silently returns for a self-event, matching
// `LocalNotificationRepository`'s guard so neither backend notifies you about
// your own like, comment or follow.
async function emitNotification(entry) {
  const recipientUid = entry.recipientUid;
  if (!recipientUid || recipientUid === entry.actorUid) return;

  const id = entry.id;
  const doc = {
    id,
    recipientUid,
    type: entry.type,
    actorName: entry.actorName || '',
    actorUid: entry.actorUid || null,
    actorPhoto: entry.actorPhoto || null,
    body: entry.body || '',
    postId: entry.postId || null,
    commentId: entry.commentId || null,
    conversationId: entry.conversationId || null,
    storyId: entry.storyId || null,
    readAt: null,
    createdAt: FieldValue.serverTimestamp(),
  };
  await db().collection('notifications').doc(id).set(doc, { merge: true });

  await sendPushToUser(recipientUid, {
    title: doc.actorName || 'Liyu',
    body: doc.body,
    data: {
      type: doc.type,
      actorUid: doc.actorUid,
      actorName: doc.actorName,
      deepLink: deepLinkFor(doc),
      conversationId: doc.conversationId,
      postId: doc.postId,
      commentId: doc.commentId,
    },
  });
}

// --- likes ------------------------------------------------------------------

exports.maintainLikesOnAdd = onDocumentCreated('posts/{postId}/reactions/{uid}', async (event) => {
  // The rules keep `likesCount` off-limits to clients, so this is the only place a
  // like raises it. The reaction document is keyed by the reactor's uid, so one
  // reader cannot add two votes to the same post.
  const { postId, uid } = event.params;
  const postRef = db().collection('posts').doc(postId);
  await bumpCounter(postRef, 'likesCount', 1);

  const post = (await postRef.get()).data();
  if (!post) return;
  const [actor, recipient] = await Promise.all([profileSnapshot(uid), profileSnapshot(post.authorUid)]);
  await emitNotification({
    id: notificationId('like', [postId, uid]),
    recipientUid: post.authorUid,
    type: 'like',
    actorUid: uid,
    actorName: actor.displayName || uid,
    actorPhoto: actor.photoUrl,
    body: phraseFor('like', (recipient && recipient.languageCode) || 'en'),
    postId,
  });
});

exports.maintainLikesOnRemove = onDocumentDeleted('posts/{postId}/reactions/{uid}', async (event) => {
  const { postId } = event.params;
  await bumpCounter(db().collection('posts').doc(postId), 'likesCount', -1);
  // The tray entry is left in place on purpose: an unread badge that vanished when
  // someone un-liked would be harder to explain than one that opens a post with no
  // like on it, and the local backend keeps the same behaviour.
});

// --- comments ---------------------------------------------------------------

exports.maintainCommentsOnAdd = onDocumentCreated('posts/{postId}/comments/{commentId}', async (event) => {
  const { postId, commentId } = event.params;
  await bumpCounter(db().collection('posts').doc(postId), 'commentsCount', 1);

  const comment = event.data.data();
  if (!comment) return;
  const post = (await db().collection('posts').doc(postId).get()).data();
  const recipient = await profileSnapshot(post && post.authorUid);
  await emitNotification({
    id: notificationId('comment', [commentId]),
    recipientUid: post && post.authorUid,
    type: 'comment',
    actorUid: comment.authorUid,
    actorName: comment.authorName || comment.authorUid,
    actorPhoto: comment.authorPhoto,
    // The reply itself is the content of this notification, not a generated
    // sentence — same as the local backend's tray.
    body: comment.text || phraseFor('comment', (recipient && recipient.languageCode) || 'en'),
    commentId,
  });

  await fanOutMentions({
    actorUid: comment.authorUid,
    actorName: comment.authorName || comment.authorUid,
    actorPhoto: comment.authorPhoto,
    mentions: comment.mentions,
    text: comment.text || '',
    sourceId: commentId,
    commentId,
  });
});

exports.maintainCommentsOnRemove = onDocumentDeleted('posts/{postId}/comments/{commentId}', async (event) => {
  const { postId } = event.params;
  await bumpCounter(db().collection('posts').doc(postId), 'commentsCount', -1);
});

// --- author post count ------------------------------------------------------

exports.maintainPostCountOnAdd = onDocumentCreated('posts/{postId}', async (event) => {
  const post = event.data.data();
  if (!post || !post.authorUid) return;
  await bumpCounter(db().collection('users').doc(post.authorUid), 'postsCount', 1);
});

exports.maintainPostCountOnRemove = onDocumentDeleted('posts/{postId}', async (event) => {
  const post = event.data.data();
  if (!post || !post.authorUid) return;
  await bumpCounter(db().collection('users').doc(post.authorUid), 'postsCount', -1);
});

// --- follow edges -----------------------------------------------------------

exports.onFollowCreated = onDocumentCreated('follows/{edgeId}', async (event) => {
  const edge = event.data.data();
  if (!edge) return;
  const { followerUid, followingUid } = edge;

  // A follow moves a counter on two different documents. Both run as their own
  // transaction so a partial failure still leaves two individually-correct counts
  // rather than a torn pair that no later write can reconcile.
  await bumpCounter(db().collection('users').doc(followingUid), 'followersCount', 1);
  await bumpCounter(db().collection('users').doc(followerUid), 'followingCount', 1);

  const [actor, recipient] = await Promise.all([
    profileSnapshot(followerUid),
    profileSnapshot(followingUid),
  ]);
  await emitNotification({
    id: notificationId('follow', [followerUid, followingUid]),
    recipientUid: followingUid,
    type: 'follow',
    actorUid: followerUid,
    actorName: actor.displayName || followerUid,
    actorPhoto: actor.photoUrl,
    body: phraseFor('follow', recipient.languageCode || 'en'),
  });
});

exports.onFollowRemoved = onDocumentDeleted('follows/{edgeId}', async (event) => {
  const edge = event.data.data();
  if (!edge) return;
  await bumpCounter(db().collection('users').doc(edge.followingUid), 'followersCount', -1);
  await bumpCounter(db().collection('users').doc(edge.followerUid), 'followingCount', -1);
});

// --- direct messages --------------------------------------------------------

exports.onMessageCreated = onDocumentCreated(
  'conversations/{conversationId}/messages/{messageId}',
  async (event) => {
    const message = event.data.data();
    if (!message) return;
    const { conversationId, messageId } = event.params;
    const sender = await profileSnapshot(message.senderUid);
    const recipient = await profileSnapshot(message.recipientUid);
    const actorName = sender.displayName || message.senderUid;

    // A preview, not a generated sentence: the thread is the destination. A
    // photo-only message says so, matching the local backend's wording, and only a
    // genuinely empty message falls back to the localized phrase.
    const body =
      message.text ||
      (message.mediaRef ? 'Sent you a photo' : phraseFor('message', recipient.languageCode || 'en'));

    await emitNotification({
      id: notificationId('message', [message.messageId || messageId]),
      recipientUid: message.recipientUid,
      type: 'message',
      actorUid: message.senderUid,
      actorName,
      actorPhoto: sender.photoUrl,
      body,
      conversationId,
    });
  },
);

// --- mention fan-out --------------------------------------------------------

// Mentions arrive as resolved uids on the document (`posts.mentions`,
// `comments.mentions`), because re-parsing text in a Function would need the
// mention index to live server-side too.
async function fanOutMentions({ actorUid, actorName, actorPhoto, mentions, text, sourceId, postId, commentId }) {
  if (!Array.isArray(mentions) || mentions.length === 0) return;
  const unique = [...new Set(mentions)].filter((uid) => uid && uid !== actorUid);
  for (const mentionedUid of unique) {
    const mentioned = await profileSnapshot(mentionedUid);
    await emitNotification({
      id: notificationId('mention', [sourceId, mentionedUid]),
      recipientUid: mentionedUid,
      type: 'mention',
      actorUid,
      actorName,
      actorPhoto: actorPhoto || null,
      body: text || phraseFor('mention', mentioned.languageCode || 'en'),
      postId,
      commentId,
    });
  }
}

exports.onPostMentions = onDocumentCreated('posts/{postId}', async (event) => {
  const post = event.data.data();
  if (!post) return;
  await fanOutMentions({
    actorUid: post.authorUid,
    actorName: post.authorName || post.authorUid,
    actorPhoto: post.authorPhoto,
    mentions: post.mentions,
    text: post.caption || '',
    sourceId: event.params.postId,
    postId: event.params.postId,
  });
});

// --- nightly story cleanup --------------------------------------------------

// Firestore TTL would delete the expired story *document* and leave the image plus
// its thumbnail sitting in Storage, billed forever — a leak invisible in the app
// and very visible on the bill. So this job removes both: the two objects first, so
// a story is never left pointing at bytes that vanished mid-run, then the document.
// The Admin SDK bypasses storage.rules, which is what lets a story object be
// deleted at all — clients are refused there.
exports.cleanupExpiredStories = onSchedule('0 3 * * *', async () => {
  const cutoff = new Date();
  const expired = await db().collection('stories').where('expiresAt', '<', cutoff).get();
  if (expired.empty) {
    logger.info('story cleanup: nothing expired');
    return;
  }

  // `bucket()` resolves the project's default bucket — the same one
  // firebase_options.dart hands the app.
  const bucket = getStorage().bucket();
  let deleted = 0;

  for (const doc of expired.docs) {
    const story = doc.data();
    const mediaId = story.mediaRef && story.mediaRef.id;
    if (mediaId && story.authorUid) {
      const base = `users/${story.authorUid}/story/${mediaId}`;
      // ignoreNotFound keeps an already-reaped story from failing the run.
      await bucket.file(base).delete({ ignoreNotFound: true }).catch(() => {});
      await bucket.file(`${base}/thumb.jpg`).delete({ ignoreNotFound: true }).catch(() => {});
    }
    await doc.ref.delete();
    deleted += 1;
  }

  logger.info('story cleanup complete', { deleted });
});
