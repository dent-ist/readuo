'use strict';

class DeletionError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function caller(request) {
  const uid = request.auth?.uid;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new DeletionError('unauthenticated', 'Sign in to continue.');
  }
  return uid;
}

function validateStart(request, nowMillis) {
  const uid = caller(request);
  const data = request.data;
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).length !== 1 || data.confirmed !== true) {
    throw new DeletionError('invalid-argument', 'Confirm permanent account deletion.');
  }
  const token = request.auth.token;
  const age = nowMillis / 1000 - token?.auth_time;
  if (!Number.isFinite(token?.auth_time) || age < 0 || age > 300 ||
      token.firebase?.sign_in_provider !== 'google.com') {
    throw new DeletionError('failed-precondition', 'Verify this account with Google again before deleting it.');
  }
  return uid;
}

const groups = [
  'users', 'shelves', 'circlePosts', 'circleReviews', 'posts',
  'books', 'activities', 'activityGenerations', 'comments', 'likes', 'replies', 'reactions',
  'friendships', 'friendRequests', 'friends', 'blocked', 'blocks',
  'readerProfiles', 'inviteCodes', 'publicShelfDirectory', 'activeAccounts', 'profilePhotoUploads', 'profileWriteLeases',
  'notifications', 'notificationEvents', 'notificationTokens',
  'bookAdditionNotifications', 'bookAdditionGroups', 'bookAdditionEntries',
  'bookAdditionPairs', 'bookAdditionReceipts', 'bookAdditionFanouts',
  'reports', 'moderationActions', 'moderationLocks', 'moderatedProfiles', 'reportLimits',
  'supportRequests', 'roomPlacements', 'roomCompliments', 'roomVisits', 'roomTipDaily', 'leafLedger',
  'onboarding', 'circleDrafts', 'reviewDrafts', 'shelfOperations', 'bookMoves', 'bookRemovals', 'libraryBookIsbns',
];

function ownedMedia(value, uid) {
  if (typeof value !== 'string') return false;
  let decoded = value;
  try { decoded = decodeURIComponent(value); } catch (_) {}
  return ['circlePosts', 'profilePhotos', 'bookCovers'].some(prefix =>
    decoded.startsWith(`${prefix}/${uid}/`) || decoded.includes(`/${prefix}/${uid}/`));
}

function identityIn(value, uid, key = '') {
  if (Array.isArray(value)) return value.some(item => identityIn(item, uid, key));
  if (value && typeof value === 'object') {
    if (typeof value.toDate === 'function') return false;
    return Object.entries(value).some(([field, item]) => identityIn(item, uid, field));
  }
  if (typeof value !== 'string') return false;
  if (/(?:id|uid|ids)$/i.test(key)) return value === uid || (key === 'pairId' && value.split('--').includes(uid));
  return false;
}

function pathsIn(value) {
  if (!value || typeof value !== 'object' || typeof value.toDate === 'function') return [];
  if (typeof value.path === 'string' && value.firestore) return [value.path];
  return Object.entries(value).flatMap(([key, item]) =>
    /path$/i.test(key) && typeof item === 'string' && !item.startsWith('http')
      ? [item] : typeof item === 'object' ? pathsIn(item) : []);
}

function classify(path, data, uid) {
  const segments = path.split('/');
  const parentGroup = segments.at(-2);
  const pathOwned = (['users', 'blocks'].includes(segments[0]) && segments[1] === uid) ||
    (['readerProfiles', 'moderatedProfiles', 'reportLimits', 'activeAccounts'].includes(parentGroup) && segments.at(-1) === uid) ||
    (['likes', 'reactions', 'friends', 'friendRequests', 'roomCompliments', 'roomVisits'].includes(parentGroup) && segments.at(-1) === uid) ||
    (parentGroup === 'roomTipDaily' && segments.at(-1).startsWith(`${uid}_`));
  if (pathOwned || identityIn(data, uid)) return { type: 'delete' };
  const patch = {};
  for (const [key, value] of Object.entries(data)) {
    if (ownedMedia(value, uid)) patch[key] = null;
  }
  return Object.keys(patch).length ? { type: 'redact', patch } : { type: 'keep' };
}

module.exports = { DeletionError, caller, validateStart, groups, ownedMedia, identityIn, pathsIn, classify };
